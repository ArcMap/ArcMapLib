import { LitElement, PropertyValues } from 'lit';
import { customElement, property } from 'lit/decorators.js';
import { FeatureCollection } from 'geojson';
import { isEqual } from 'lodash-es';

import FeatureLayer from '@arcgis/core/layers/FeatureLayer';
import Graphic from '@arcgis/core/Graphic';
import Point from '@arcgis/core/geometry/Point';
import Polyline from '@arcgis/core/geometry/Polyline';
import Polygon from '@arcgis/core/geometry/Polygon';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer';
import Draw from '@arcgis/core/views/draw/Draw';
import SketchViewModel from '@arcgis/core/widgets/Sketch/SketchViewModel';
import SimpleRenderer from '@arcgis/core/renderers/SimpleRenderer';
import SimpleMarkerSymbol from '@arcgis/core/symbols/SimpleMarkerSymbol';
import SimpleLineSymbol from '@arcgis/core/symbols/SimpleLineSymbol';
import SimpleFillSymbol from '@arcgis/core/symbols/SimpleFillSymbol';

import DrawEditUtils from '../../common/draw-edit-utils';
import JsonUtils from '../../common/json-utils';
import PopupUtils from '../../common/popup-utils';
import ValidationService from '../../common/validation-service';
import type {
  ArcMapElement,
  InfoTemplateDetails,
  MouseEvent as LayerMouseEvent,
} from '../../external-api';

interface IHandle {
  remove(): void;
}

@customElement('arc-geojson-layer')
export class ArcGeoJsonLayer extends LitElement {

  // ─── Private fields ───────────────────────────────────────────────────────
  private graphicsEditor!: SketchViewModel;
  private ancestorMap!: ArcMapElement;
  private readonly DEFAULT_SYMBOL_COLOR: number[] = JsonUtils.getRandomColor();
  private static readonly DEFAULT_SYMBOL_LINE_WIDTH = 1;
  private static readonly DEFAULT_SYMBOL_MARKER_SIZE = 10;
  private featureLayer!: FeatureLayer;
  private esriDraw!: Draw;
  private eventHandles: IHandle[] = [];
  private inDrawingMode = false;
  private removingItem = false;
  private blockGeoJsonUpdate = false;
  private graphicMoved = false;
  private objectIdField = {
    name: 'OBJECTID',
    type: 'oid' as const,
    alias: 'OBJECTID',
  };

  // ─── Properties ───────────────────────────────────────────────────────────
  @property({ type: Boolean }) enableUserEdit = false;
  @property({ type: Boolean }) enableUserEditAddVertices = true;
  @property({ type: Boolean }) enableUserEditDeleteVertices = true;
  @property({ type: Boolean }) enableUserEditMove = true;
  @property({ type: Boolean }) enableUserEditRemove = true;
  @property({ type: Boolean }) enableUserEditRotating = true;
  @property({ type: Boolean }) enableUserEditScaling = true;
  @property({ type: Boolean }) enableUserEditUniformScaling = true;
  @property({ type: Boolean }) enableUserEditVertices = true;
  @property() geojson: string | FeatureCollection = '';
  @property() infoTemplate: string | InfoTemplateDetails = '';
  @property({ type: Array }) labelColor: string | number[] = this.DEFAULT_SYMBOL_COLOR;
  @property() labelJson: string | object | object[] = '';
  @property({ type: Number }) labelSize: number = JsonUtils.DEFAULT_LABEL_SIZE;
  @property() layerClass: string = '';
  @property({ reflect: true }) name: string = '';
  @property({ type: Object }) renderer: any = null;
  @property() uniqueIdPropertyName: string = 'id';

  // ─── Lit Lifecycle ────────────────────────────────────────────────────────
  createRenderRoot() { return this; }
  render() { return null; }

  connectedCallback() {
    super.connectedCallback();
    this._init();
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._cleanup();
  }

  updated(changedProperties: PropertyValues) {
    super.updated(changedProperties);

    if (changedProperties.has('enableUserEdit')) {
      this.updateEditing(this.enableUserEdit);
    }
    if (
      changedProperties.has('enableUserEditAddVertices') ||
      changedProperties.has('enableUserEditDeleteVertices') ||
      changedProperties.has('enableUserEditMove') ||
      changedProperties.has('enableUserEditRotating') ||
      changedProperties.has('enableUserEditScaling') ||
      changedProperties.has('enableUserEditUniformScaling')
    ) {
      this.graphicsEditor?.cancel();
    }
    if (changedProperties.has('geojson')) {
      this._onGeojsonChanged(this.geojson);
    }
    if (changedProperties.has('infoTemplate') && this.featureLayer) {
      PopupUtils.updatePopup(
        this.infoTemplate,
        this.ancestorMap,
        this.featureLayer
      );
    }
    if (changedProperties.has('labelJson') && this.featureLayer) {
      JsonUtils.updateLabelJson(this.labelJson, this.featureLayer);
    }
    if (changedProperties.has('layerClass') && this.featureLayer) {
      this.featureLayer.className = this.layerClass;
    }
    if (changedProperties.has('renderer')) {
      this._updateRenderer(this.renderer);
    }
  }

  // ─── Init / Cleanup ───────────────────────────────────────────────────────
  private async _init() {
    this.ancestorMap = this.closest('arc-map') as unknown as ArcMapElement;
    if (!this.ancestorMap) {
      console.error(
        '<arc-geojson-layer> must be a descendent of a <arc-map> element'
      );
      return;
    }
    this.createLayer(this.geojson);
  }

  private async _cleanup() {
    if (this.ancestorMap && this.featureLayer) {
      await this.ancestorMap.removeLayer(this.featureLayer);
    }
    this.eventHandles.forEach((h) => h.remove());
    this.eventHandles = [];
    this.blockGeoJsonUpdate = false;
    this.featureLayer = null as any;
  }

  // ─── GeoJSON watcher ──────────────────────────────────────────────────────
  private async _onGeojsonChanged(newGeojson: string | FeatureCollection) {
    // Check blockGeoJsonUpdate FIRST
    if (this.blockGeoJsonUpdate) return;
    if (this.removingItem) return;

    if ((this.enableUserEdit || this.inDrawingMode) && this.featureLayer) {
      console.warn(
        'Cannot update GeoJson while user is editing or drawing new features.'
      );
      return;
    }

    if (!this.featureLayer) {
      this.createLayer(newGeojson);
      return;
    }

    this._updateRenderer(this.renderer);

    const fsInfo = this._getArcGisJson(newGeojson);
    if (fsInfo == null) return;

    if (fsInfo.jsonFS.geometryType !== this.featureLayer.geometryType) {
      await this._cleanup();
      this.createLayer(newGeojson);
      return;
    }

    const featuresToUpdate: Graphic[] = [];
    const featuresToAdd: Graphic[] = [];

    for (const feature of fsInfo.jsonFS.features) {
      const matchingFeature = await this.findFeatureByUniqueId(
        feature.attributes[this.uniqueIdPropertyName]
      );
      if (matchingFeature) {
        feature.attributes.OBJECTID = (matchingFeature as any).attributes.OBJECTID;
        featuresToUpdate.push(feature);
      } else {
        featuresToAdd.push(feature);
      }
    }

    const newUniqueIds = fsInfo.jsonFS.features.map(
      (g: any) => g.attributes[this.uniqueIdPropertyName]
    );

    const existingResult = await this.featureLayer.queryFeatures();
    const featuresToRemove = existingResult.features.filter((graphic: any) => {
      const existingId = graphic.attributes[this.uniqueIdPropertyName];
      return existingId === undefined || !newUniqueIds.includes(existingId);
    });

    await this.featureLayer.applyEdits({
      addFeatures: featuresToAdd,
      updateFeatures: featuresToUpdate,
      deleteFeatures: featuresToRemove,
    });
    this.featureLayer.refresh();

    const geoJson = await this._getCurrentGeoJson();
    this.blockGeoJsonUpdate = true;
    this.geojson = geoJson;
    this.blockGeoJsonUpdate = false;

    // Update popup if visible
    const esriMap = await this.ancestorMap.getEsriMap();
    const popup = (esriMap as any).popup;
    if (popup?.visible && popup?.features) {
      if (popup.features.length === 1) {
        const detailsFeature = popup.features[0];
        if (detailsFeature?.layer !== this.featureLayer) return;
        const stillExists = existingResult.features.some(
          (f: any) =>
            f.attributes[this.uniqueIdPropertyName] ===
            detailsFeature.attributes[this.uniqueIdPropertyName]
        );
        if (!stillExists) {
          popup.visible = false;
        } else if (
          !isEqual(popup.features[0]?.geometry, detailsFeature.geometry)
        ) {
          popup.features = [detailsFeature];
          popup.location = ArcGeoJsonLayer.getPopupPoint(detailsFeature.geometry);
          popup.visible = true;
        }
      } else {
        const featuresToKeep = popup.features.filter(
          (f: any) => !featuresToRemove.includes(f)
        );
        popup.features = featuresToKeep;
        if (featuresToKeep.length === 0) popup.visible = false;
      }
    }
  }

  // ─── Prop helpers ─────────────────────────────────────────────────────────
  private updateEditing(newUserEnableEdit: boolean) {
    this.enableInfoPopupWindow(!newUserEnableEdit);
    if (!newUserEnableEdit) this.graphicsEditor?.cancel();
  }

  private _updateRenderer(newRenderer: any) {
    if (!this.featureLayer) return;
    if (newRenderer) {
      const rendererParseResult = JsonUtils.getJsonFor(newRenderer);
      if (rendererParseResult.error) {
        console.warn('Could not parse renderer', rendererParseResult.error);
        return;
      }
      const parsedConfig = rendererParseResult.parsedJson;
      const rendererTypeToModule: any = {
        simple: SimpleRenderer,
      };
      const RendererClass = rendererTypeToModule[parsedConfig.type];
      if (RendererClass) {
        this.featureLayer.renderer = new RendererClass(parsedConfig);
      } else {
        this.featureLayer.renderer = new SimpleRenderer(parsedConfig);
      }
      this.featureLayer.refresh();
    } else {
      this.featureLayer.renderer = this._buildRenderer(
        this.featureLayer.geometryType
      );
      this.featureLayer.refresh();
    }
  }

  // ─── Public methods ───────────────────────────────────────────────────────
  async startDrawing(drawGeometryType: string) {
    const existingResult = await this.featureLayer.queryFeatures();
    if (existingResult.features.length === 0) {
      this.featureLayer.geometryType =
        DrawEditUtils.determineFeatureLayerGeometryType(
          drawGeometryType
        ) as any;
    }

    if (
      !DrawEditUtils.validGeometryType(
        drawGeometryType,
        this.featureLayer.geometryType
      )
    )
      return;

    if (!(drawGeometryType.toUpperCase() in DrawEditUtils.DrawGeometryTypes)) {
      console.error(
        'The geometry type ' + drawGeometryType + ' is invalid. Drawing cancelled.'
      );
      return;
    }

    this.inDrawingMode = true;
    this.enableInfoPopupWindow(false);

    const esriMap = await this.ancestorMap.getEsriMap();
    if (this.esriDraw) {
      this.esriDraw.reset();
    } else {
      this.esriDraw = new Draw({ view: esriMap as any });
    }

    const action = this.esriDraw.create(
      drawGeometryType.toLowerCase() as any
    ) as any;

    action.on('draw-complete', async (evt: any) => {
      await this.ancestorMap.showZoomSlider();
      await this.ancestorMap.showScaleBarMethod();
      this.esriDraw.reset();

      const newGeometry = evt.geometry;
      let graphic: Graphic;

      if (this.renderer) {
        graphic = new Graphic({ geometry: newGeometry });
      } else {
        let symbol: any;
        switch (newGeometry.type) {
          case 'point':
          case 'multipoint':
            symbol = new SimpleMarkerSymbol();
            break;
          case 'polyline':
            symbol = new SimpleLineSymbol();
            break;
          default:
            symbol = new SimpleFillSymbol();
        }
        graphic = new Graphic({ geometry: newGeometry, symbol });
      }

      const currentFeatures = await this.featureLayer.queryFeatures();
      const addingFirstGeometry = currentFeatures.features.length === 0;
      await this.addToGeoJson(graphic);
      if (this.renderer && addingFirstGeometry) {
        this._updateRenderer(this.renderer);
      }

      this.inDrawingMode = false;
      this.enableInfoPopupWindow(true);
    });

    await this.ancestorMap.hideZoomSlider();
    await this.ancestorMap.hideScaleBar();
  }

  async cancelDrawing() {
    this.inDrawingMode = false;
    this.esriDraw?.reset();
    await this.ancestorMap.showZoomSlider();
    await this.ancestorMap.showScaleBarMethod();
    this.enableInfoPopupWindow(true);
  }

  async findFeatureByUniqueId(uniqueId: string | number): Promise<any> {
    const result = await this.featureLayer.queryFeatures({
      where: `${this.uniqueIdPropertyName} = '${uniqueId}'`,
      outFields: ['*'],
      returnGeometry: true,
    });
    return result.features[0];
  }

  async getLayerId(): Promise<string> {
    return this.featureLayer?.id ?? '';
  }

  async openPopup(id: string | number) {
    const graphicMatch: Graphic = await this.findFeatureByUniqueId(id);
    if (graphicMatch === undefined) {
      console.warn(
        'No feature found with a',
        this.uniqueIdPropertyName,
        'value of',
        id,
        '. Cannot open popup.'
      );
      return;
    }
    const esriMap = await this.ancestorMap.getEsriMap();
    const popup = (esriMap as any).popup;
    popup.features = [graphicMatch];
    popup.location = ArcGeoJsonLayer.getPopupPoint(graphicMatch.geometry);
    popup.visible = true;
  }

  async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {
    const graphicMatch: Graphic = await this.findFeatureByUniqueId(id);
    if (graphicMatch === undefined) {
      console.warn(
        'No feature found with a',
        this.uniqueIdPropertyName,
        'value of',
        id,
        '. Cannot zoom to.'
      );
      return;
    }
    const esriMap = await this.ancestorMap.getEsriMap();
    const view = esriMap as any;
    const geometry = graphicMatch.geometry;
    if (ValidationService.isPoint(geometry)) {
      return view.goTo({ target: geometry, zoom: zoomLevel });
    } else if (
      ValidationService.isPolyline(geometry) ||
      ValidationService.isPolygon(geometry)
    ) {
      return view.goTo((geometry as any).extent);
    } else {
      console.error('Unrecognized geometry type', (geometry as any).type);
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  // ✅ Build proper ArcGIS renderer using symbol class instances
  private _buildRenderer(geomType: string): SimpleRenderer {
    switch (geomType) {
      case 'point':
      case 'multipoint':
        return new SimpleRenderer({
          symbol: new SimpleMarkerSymbol({
            style: 'circle',
            color: this.DEFAULT_SYMBOL_COLOR,
            size: ArcGeoJsonLayer.DEFAULT_SYMBOL_MARKER_SIZE,
            outline: new SimpleLineSymbol({
              color: [0, 0, 0, 255],
              width: 1,
            }),
          }),
        });
      case 'polyline':
        return new SimpleRenderer({
          symbol: new SimpleLineSymbol({
            style: 'solid',
            color: this.DEFAULT_SYMBOL_COLOR,
            width: ArcGeoJsonLayer.DEFAULT_SYMBOL_LINE_WIDTH + 1,
          }),
        });
      case 'polygon':
      default:
        return new SimpleRenderer({
          symbol: new SimpleFillSymbol({
            style: 'solid',
            color: [
              this.DEFAULT_SYMBOL_COLOR[0],
              this.DEFAULT_SYMBOL_COLOR[1],
              this.DEFAULT_SYMBOL_COLOR[2],
              100,
            ],
            outline: new SimpleLineSymbol({
              style: 'solid',
              color: this.DEFAULT_SYMBOL_COLOR,
              width: 1,
            }),
          }),
        });
    }
  }

  // ✅ Convert GeoJSON geometry to real ArcGIS geometry object
  private _geojsonGeometryToArcGIS(geojsonGeometry: any): any {
    if (!geojsonGeometry) return null;
    const sr = { wkid: 4326 };
    switch (geojsonGeometry.type) {
      case 'Point':
        return new Point({
          longitude: geojsonGeometry.coordinates[0],
          latitude: geojsonGeometry.coordinates[1],
          spatialReference: sr,
        });
      case 'LineString':
        return new Polyline({
          paths: [geojsonGeometry.coordinates],
          spatialReference: sr,
        });
      case 'MultiLineString':
        return new Polyline({
          paths: geojsonGeometry.coordinates,
          spatialReference: sr,
        });
      case 'Polygon':
        return new Polygon({
          rings: geojsonGeometry.coordinates,
          spatialReference: sr,
        });
      case 'MultiPolygon':
        return new Polygon({
          rings: geojsonGeometry.coordinates.flat(1),
          spatialReference: sr,
        });
      case 'MultiPoint':
        return new Point({
          longitude: geojsonGeometry.coordinates[0][0],
          latitude: geojsonGeometry.coordinates[0][1],
          spatialReference: sr,
        });
      default:
        return null;
    }
  }

  // ✅ Convert ArcGIS Graphic back to GeoJSON Feature
  private _arcGisGraphicToGeoJson(graphic: Graphic): any {
    if (!graphic) {
      console.warn('_arcGisGraphicToGeoJson: graphic is undefined');
      return null;
    }
    if (!graphic.geometry) {
      return {
        type: 'Feature',
        id: graphic.attributes?.[this.uniqueIdPropertyName],
        geometry: null,
        properties: { ...graphic.attributes },
      };
    }

    let geoJsonGeometry: any = null;
    switch (graphic.geometry.type) {
      case 'point': {
        const g = graphic.geometry as Point;
        geoJsonGeometry = {
          type: 'Point',
          coordinates: [g.longitude, g.latitude],
        };
        break;
      }
      case 'polyline': {
        const g = graphic.geometry as Polyline;
        geoJsonGeometry = {
          type: g.paths.length === 1 ? 'LineString' : 'MultiLineString',
          coordinates: g.paths.length === 1 ? g.paths[0] : g.paths,
        };
        break;
      }
      case 'polygon': {
        const g = graphic.geometry as Polygon;
        geoJsonGeometry = {
          type: 'Polygon',
          coordinates: g.rings,
        };
        break;
      }
      default:
        geoJsonGeometry = null;
    }

    return {
      type: 'Feature',
      id: graphic.attributes?.[this.uniqueIdPropertyName],
      geometry: geoJsonGeometry,
      properties: { ...graphic.attributes },
    };
  }

  // ✅ Get current layer features as GeoJSON FeatureCollection
  private async _getCurrentGeoJson(): Promise<any> {
    try {
      const result = await this.featureLayer.queryFeatures();
      const features = (result?.features ?? [])
        .filter((g: any) => g != null)
        .map((g: Graphic) => this._arcGisGraphicToGeoJson(g))
        .filter((f: any) => f !== null);
      return { type: 'FeatureCollection', features };
    } catch (e) {
      console.warn('_getCurrentGeoJson error:', e);
      return { type: 'FeatureCollection', features: [] };
    }
  }

  private async createDrawing() {
    const esriMap = await this.ancestorMap.getEsriMap();
    this.esriDraw = new Draw({ view: esriMap as any });
  }

  private async createEditor() {
    if (!this.featureLayer) return;

    const esriMap = await this.ancestorMap.getEsriMap();
    const sketchLayer = new GraphicsLayer();
    (esriMap as any).add(sketchLayer);

    this.graphicsEditor = new SketchViewModel({
      view: esriMap as any,
      layer: sketchLayer,
    });

    this.graphicsEditor.on('update', (evt: any) => {
      if (!evt.toolEventInfo) return;
      const type = evt.toolEventInfo.type as string;

      if (type === 'move-start') this.graphicMoved = false;
      if (type === 'move') this.graphicMoved = true;

      if (
        type === 'rotate-stop' ||
        type === 'scale-stop' ||
        type === 'vertex-add' ||
        type === 'vertex-remove' ||
        type === 'reshape-stop'
      ) {
        evt.graphics?.forEach((g: Graphic) =>
          this.updateGeoJsonWithChanges(g)
        );
      }

      if (type === 'move-stop' && this.graphicMoved) {
        this.graphicMoved = false;
        evt.graphics?.forEach((g: Graphic) =>
          this.updateGeoJsonWithChanges(g)
        );
      }
    });

    this.graphicsEditor.on('delete', (evt: any) => {
      evt.graphics?.forEach((g: Graphic) => this.removeFromGeoJson(g));
    });

    // ✅ Use MapView hitTest for click — not featureLayer.on('click')
    const clickHandle = (esriMap as any).on('click', async (evt: any) => {
      if (!this.enableUserEdit) return;
      const response = await (esriMap as any).hitTest(evt);
      const hit = response.results?.find(
        (r: any) => r.graphic?.layer === this.featureLayer
      );
      if (!hit) return;
      const graphic = hit.graphic;
      if (evt.native?.ctrlKey && this.enableUserEditRemove) {
        this.removingItem = true;
        this.removeFromGeoJson(graphic);
        this.graphicsEditor.cancel();
        this.removingItem = false;
        return;
      }
      this.activateGraphicsEditor(graphic);
    });

    this.eventHandles.push(clickHandle);
  }

  private enableInfoPopupWindow(enable: boolean) {
    const enablePopup =
      enable && !this.enableUserEdit && !this.inDrawingMode;
    this.ancestorMap.enableInfoWindow(enablePopup);
  }

  private async activateGraphicsEditor(graphic: Graphic) {
    let tool = 0;
    if (this.enableUserEditMove) tool = tool | 1;
    if (this.enableUserEditVertices) tool = tool | 2;
    if (this.enableUserEditScaling) tool = tool | 4;
    if (this.enableUserEditRotating) tool = tool | 8;

    if (tool !== 0) {
      const updateTool = tool & 2 ? 'reshape' : 'transform';
      this.graphicsEditor.update([graphic], {
        tool: updateTool,
        toggleToolOnClick: false,
      });
    } else {
      console.error(
        'Cannot edit. All editing features have been turned off.'
      );
    }
  }

  private static getPopupPoint(geometry: any): Point {
    if (ValidationService.isPoint(geometry)) return geometry as Point;
    else if (ValidationService.isPolyline(geometry)) {
      const polyline = geometry as any;
      const middleIndex = Math.floor(polyline.paths[0].length / 2);
      return polyline.getPoint(0, middleIndex) as Point;
    } else if (ValidationService.isPolygon(geometry)) {
      return (geometry as any).centroid as Point;
    }
    return null as any;
  }

  // ✅ Main createLayer — fully fixed
  private createLayer(geojson: string | FeatureCollection): void {
    if (!geojson) geojson = { type: 'FeatureCollection', features: [] };

    const fsInfo = this._getArcGisJson(geojson);
    if (fsInfo == null) {
      console.error(
        '<arc-geojson-layer> unable to create geojson layer, geojson property contains invalid data'
      );
      return;
    }

    // ✅ Create FeatureLayer with source as real Graphic objects
    const featureLayer = new FeatureLayer({
      source: fsInfo.jsonFS.features,
      geometryType: fsInfo.jsonFS.geometryType as any,
      spatialReference: { wkid: 4326 },
      objectIdField: 'OBJECTID',
      fields: [
        { name: 'OBJECTID', alias: 'OBJECTID', type: 'oid' },
        {
          name: this.uniqueIdPropertyName,
          alias: this.uniqueIdPropertyName,
          type: 'string',
        },
      ],
      title: this.name,
      labelsVisible: true,
    });

    this.featureLayer = featureLayer;

    // ✅ Set renderer AFTER layer creation using class instances
    this.featureLayer.renderer = this._buildRenderer(
      fsInfo.jsonFS.geometryType
    );

    // ✅ Add to map
    this.ancestorMap.addLayer(this.featureLayer, this);

    this.featureLayer.when(async () => {
      console.log('FeatureLayer loaded');

      const result = await this.featureLayer.queryFeatures();
      console.log('Features loaded:', result.features.length);

      // Apply custom renderer if set
      if (this.renderer) {
        this._updateRenderer(this.renderer);
      }

      // Apply labels
      const labelJson = JsonUtils.getLabelJson(
        this.labelJson,
        this.labelColor as any,
        this.labelSize
      );
      JsonUtils.updateLabelJson(labelJson, this.featureLayer);

      // Apply popup template
      PopupUtils.updatePopup(
        this.infoTemplate,
        this.ancestorMap,
        this.featureLayer
      );

      // Wire mouse events
      const esriEventToCustomEvent = new Map<string, string>([
        ['click', 'layerClick'],
        ['dbl-click', 'doubleClick'],
        ['mouse-over', 'layerMouseOver'],
        ['mouse-out', 'layerMouseOut'],
      ]);

      esriEventToCustomEvent.forEach((customEventName, esriEvent) => {
        const handle = (this.featureLayer as any).on(
          esriEvent,
          (evt: any) => {
            import('@arcgis/core/geometry/support/webMercatorUtils').then(
              ({ webMercatorToGeographic }) => {
                const coords = webMercatorToGeographic(evt.mapPoint) as any;
                const detail: LayerMouseEvent = {
                  coordinates: {
                    latitude: coords?.y,
                    longitude: coords?.x,
                  },
                  attributes: evt.graphic?.attributes,
                };
                this.dispatchEvent(
                  new CustomEvent(customEventName, {
                    detail,
                    bubbles: true,
                    composed: true,
                  })
                );
              }
            );
          }
        );
        this.eventHandles.push(handle);
      });

      // Setup editor
      this.createEditor();

      // Sync geojson back
      const geoJson = await this._getCurrentGeoJson();
      this.blockGeoJsonUpdate = true;
      this.geojson = geoJson;
      this.blockGeoJsonUpdate = false;
    });
  }

  // ✅ Convert GeoJSON to ArcGIS feature array with real geometry objects
  private _getArcGisJson(geojson: string | FeatureCollection | object): any {
    const geojsonParseResult = JsonUtils.getJsonFor(geojson);
    if (geojsonParseResult.error) {
      console.error('Unable to parse geojson string', geojsonParseResult.error);
      return null;
    }

    const parsed = geojsonParseResult.parsedJson;
    if (!parsed?.features || !Array.isArray(parsed.features)) {
      console.error(
        'JSON value for geojson attribute could not be converted as geojson'
      );
      return null;
    }

    const features = parsed.features.map((feature: any, index: number) => {
      const geometry = this._geojsonGeometryToArcGIS(feature.geometry);
      return new Graphic({
        geometry,
        attributes: {
          ...feature.properties,
          OBJECTID: index,
          [this.uniqueIdPropertyName]:
            feature.id ??
            feature.properties?.[this.uniqueIdPropertyName] ??
            index,
        },
      });
    });

    let geomType = 'polygon';
    if (parsed.features.length > 0 && parsed.features[0].geometry) {
      switch (parsed.features[0].geometry.type) {
        case 'Point': geomType = 'point'; break;
        case 'MultiPoint': geomType = 'multipoint'; break;
        case 'LineString':
        case 'MultiLineString': geomType = 'polyline'; break;
        case 'Polygon':
        case 'MultiPolygon': geomType = 'polygon'; break;
      }
    }

    return {
      jsonFS: {
        geometryType: geomType,
        spatialReference: { wkid: 4326 },
        fields: [this.objectIdField],
        features,
      },
    };
  }

  private async addToGeoJson(newGraphic: Graphic) {
    await this.featureLayer.applyEdits({ addFeatures: [newGraphic] });
    const convertedGraphic = this._arcGisGraphicToGeoJson(newGraphic);
    const newGeoJson = JsonUtils.getJsonFor(this.geojson);
    if (newGeoJson.parsedJson?.features) {
      newGeoJson.parsedJson.features.push(convertedGraphic);
      this.geojson = newGeoJson.parsedJson;
    }
    this.dispatchEvent(
      new CustomEvent('userDrawItemAdded', {
        detail: convertedGraphic,
        bubbles: true,
        composed: true,
      })
    );
  }

  private async removeFromGeoJson(graphicToRemove: Graphic) {
    await this.featureLayer.applyEdits({ deleteFeatures: [graphicToRemove] });
    const convertedGraphic = this._arcGisGraphicToGeoJson(graphicToRemove);
    const idToRemove =
      graphicToRemove.attributes?.[this.uniqueIdPropertyName];
    const newGeoJson = JsonUtils.getJsonFor(this.geojson);
    if (newGeoJson.parsedJson?.features) {
      const idx = newGeoJson.parsedJson.features.findIndex(
        (f: any) =>
          f.id === idToRemove ||
          f.properties?.[this.uniqueIdPropertyName] === idToRemove
      );
      if (idx > -1) newGeoJson.parsedJson.features.splice(idx, 1);
      this.geojson = newGeoJson.parsedJson;
    }
    this.dispatchEvent(
      new CustomEvent('userEditItemRemoved', {
        detail: convertedGraphic,
        bubbles: true,
        composed: true,
      })
    );
  }

  private async updateGeoJsonWithChanges(graphicToUpdate: Graphic) {
    await this.featureLayer.applyEdits({ updateFeatures: [graphicToUpdate] });
    const convertedGraphic = this._arcGisGraphicToGeoJson(graphicToUpdate);
    const idToUpdate =
      graphicToUpdate.attributes?.[this.uniqueIdPropertyName];
    const newGeoJson = JsonUtils.getJsonFor(this.geojson);
    if (newGeoJson.parsedJson?.features) {
      for (let i = 0; i < newGeoJson.parsedJson.features.length; i++) {
        const f = newGeoJson.parsedJson.features[i];
        if (
          f.id === idToUpdate ||
          f.properties?.[this.uniqueIdPropertyName] === idToUpdate
        ) {
          newGeoJson.parsedJson.features[i] = convertedGraphic;
          break;
        }
      }
      this.geojson = newGeoJson.parsedJson;
    }
    this.dispatchEvent(
      new CustomEvent('userEditItemUpdated', {
        detail: convertedGraphic,
        bubbles: true,
        composed: true,
      })
    );

}



async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {
  const graphicMatch: Graphic = await this.findFeatureByUniqueId(id);
  if (graphicMatch === undefined) {
    console.warn(
      'No feature found with a',
      this.uniqueIdPropertyName,
      'value of',
      id,
      '. Cannot zoom to.'
    );
    return;
  }

  const esriMap = await this.ancestorMap.getEsriMap();
  const view = esriMap as any;

  // ✅ Cast geometry to any to avoid TypeScript narrowing issues
  const geometry = graphicMatch.geometry as any;

  if (!geometry) {
    console.warn('zoomTo: graphic has no geometry');
    return;
  }

  if (geometry.type === 'point') {
    return view.goTo({ target: geometry, zoom: zoomLevel });
  } else if (
    geometry.type === 'polyline' ||
    geometry.type === 'polygon'
  ) {
    return view.goTo(geometry.extent);
  } else {
    console.error(
      'Unrecognized geometry type',
      geometry.type
    );
  }
}
