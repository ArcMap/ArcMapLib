import { LitElement } from 'lit';
import { customElement, property } from 'lit/decorators.js';

import MapView from '@arcgis/core/views/MapView';
import Graphic from '@arcgis/core/Graphic';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer';
import Point from '@arcgis/core/geometry/Point';
import Polyline from '@arcgis/core/geometry/Polyline';
import Polygon from '@arcgis/core/geometry/Polygon';
import PopupTemplate from '@arcgis/core/PopupTemplate';
import SketchViewModel from '@arcgis/core/widgets/Sketch/SketchViewModel';
import * as webMercatorUtils from '@arcgis/core/support/webMercatorUtils';
import SimpleMarkerSymbol from '@arcgis/core/symbols/SimpleMarkerSymbol';
import SimpleLineSymbol from '@arcgis/core/symbols/SimpleLineSymbol';
import SimpleFillSymbol from '@arcgis/core/symbols/SimpleFillSymbol';
import TextSymbol from '@arcgis/core/symbols/TextSymbol';
import type Geometry from '@arcgis/core/geometry/Geometry';

import type { FeatureCollection, Feature, Geometry as GeoJsonGeometry } from 'geojson';
import JsonUtils from '../common/json-utils';
import { InfoTemplateDetails } from '../external-api';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type LayerMouseEvent = {
  coordinates: {
    latitude: number;
    longitude: number;
  };
  attributes: any;
};

type JsonParseResult<T = any> =
  | { parsedJson: T; error?: never }
  | { error: Error; parsedJson?: never };

enum DrawGeometryTypes {
  FREEHAND_POLYLINE = 'FREEHAND_POLYLINE',
  LINE = 'LINE',
  POLYLINE = 'POLYLINE',
  MULTI_POINT = 'MULTI_POINT',
  POINT = 'POINT',
  ARROW = 'ARROW',
  CIRCLE = 'CIRCLE',
  DOWN_ARROW = 'DOWN_ARROW',
  ELLIPSE = 'ELLIPSE',
  EXTENT = 'EXTENT',
  FREEHAND_POLYGON = 'FREEHAND_POLYGON',
  LEFT_ARROW = 'LEFT_ARROW',
  POLYGON = 'POLYGON',
  RECTANGLE = 'RECTANGLE',
  RIGHT_ARROW = 'RIGHT_ARROW',
  TRIANGLE = 'TRIANGLE',
  UP_ARROW = 'UP_ARROW'
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

@customElement('arc-geojson-layer')
export class ArcGeojsonLayer extends LitElement {

  // Ready promise — mirrors Stencil's componentOnReady() pattern
  private _resolveReady!: () => void;
  private _readyPromise: Promise<void> = new Promise(
    resolve => (this._resolveReady = resolve)
  );

  async componentOnReady(): Promise<void> {
    return this._readyPromise;
  }

  private graphicsEditor!: SketchViewModel;
  private ancestorMap!: any;
  private readonly DEFAULT_SYMBOL_COLOR: number[] =
    ArcGeojsonLayer.getRandomColor();

  private static readonly DEFAULT_SYMBOL_LINE_WIDTH = 1;
  private static readonly DEFAULT_SYMBOL_MARKER_SIZE = 10;

  private featureLayer!: GraphicsLayer;
  private labelLayer!: GraphicsLayer;
  private view!: MapView;

  private inDrawingMode = false;
  private removingItem = false;
  private blockGeoJsonUpdate = false;
  private graphicMoved = false;
  private hoveredGraphicUid: string | number | undefined;
  private eventHandles: Array<{ remove: () => void }> = [];

  // Track internal updates to prevent Angular NgRx echo
  private _internalUpdateId: number = 0;

  @property({ type: Boolean, attribute: 'enable-user-edit' })
  enableUserEdit = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-add-vertices' })
  enableUserEditAddVertices = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-delete-vertices' })
  enableUserEditDeleteVertices = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-move' })
  enableUserEditMove = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-remove' })
  enableUserEditRemove = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-rotating' })
  enableUserEditRotating = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-scaling' })
  enableUserEditScaling = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-uniform-scaling' })
  enableUserEditUniformScaling = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-vertices' })
  enableUserEditVertices = true;

  @property({ type: Object }) geojson: string | FeatureCollection = {
    type: 'FeatureCollection',
    features: []
  };

  @property({ attribute: 'info-template' })
  infoTemplate!: string | InfoTemplateDetails;

  @property({ attribute: 'label-color' })
  labelColor: number[] | string = this.DEFAULT_SYMBOL_COLOR;

  @property({ type: Number, attribute: 'label-size' })
  labelSize = JsonUtils.DEFAULT_LABEL_SIZE;

  @property({ type: String, attribute: 'label-json' })
  labelJson: string | object | object[] = '';

  @property({ attribute: 'layer-class' })
  layerClass: string = '';

  @property({ attribute: 'name' })
  name?: string = undefined;

  @property({ attribute: 'renderer' })
  renderer: any = undefined;

  @property({ attribute: 'unique-id-property-name' })
  uniqueIdPropertyName = 'id';

  protected createRenderRoot(): this {
    return this;
  }

  render() {
    return null;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  async connectedCallback(): Promise<void> {
    super.connectedCallback();
    try {
      await this.resolveAncestorMapAndView();
      await this.createLayer(this.geojson);
      this.bindViewEvents();
      // Signal ready — Angular can now safely call startDrawing etc.
      this._resolveReady();
    } catch (e) {
      console.error('arc-geojson-layer connectedCallback error:', e);
      // Still resolve so Angular does not hang forever
      this._resolveReady();
    }
  }

  disconnectedCallback(): void {
    super.disconnectedCallback();

    for (const handle of this.eventHandles) {
      if (handle) handle.remove();
    }
    this.eventHandles = [];

    if (this.graphicsEditor) {
      try { this.graphicsEditor.cancel(); } catch { }
    }

    if (this.view?.map) {
      if (this.featureLayer) this.view.map.remove(this.featureLayer);
      if (this.labelLayer) this.view.map.remove(this.labelLayer);
    }

    // Reset ready promise for reconnection
    this._readyPromise = new Promise(
      resolve => (this._resolveReady = resolve)
    );
  }

  protected updated(changedProps: Map<string, unknown>): void {
    if (changedProps.has('geojson') && !this.blockGeoJsonUpdate) {
      this.updateGeojson(this.geojson);
    }
    if (changedProps.has('infoTemplate')) {
      this.updateInfoTemplate(this.infoTemplate);
    }
    if (changedProps.has('renderer')) {
      this.updateRenderer(this.renderer);
    }
    if (changedProps.has('labelJson')) {
      this.updateLabelJson(this.labelJson);
    }
    if (changedProps.has('labelColor') || changedProps.has('labelSize')) {
      this.refreshLabels();
    }
    if (changedProps.has('layerClass')) {
      this.updateLayerClass(this.layerClass);
    }
    if (
      changedProps.has('enableUserEdit') ||
      changedProps.has('enableUserEditMove') ||
      changedProps.has('enableUserEditVertices') ||
      changedProps.has('enableUserEditScaling') ||
      changedProps.has('enableUserEditRotating') ||
      changedProps.has('enableUserEditUniformScaling') ||
      changedProps.has('enableUserEditAddVertices') ||
      changedProps.has('enableUserEditDeleteVertices')
    ) {
      this.updateEditing(this.enableUserEdit);
    }
  }

  // ---------------------------------------------------------------------------
  // Map / view resolution
  // ---------------------------------------------------------------------------

  private async resolveAncestorMapAndView(): Promise<void> {
    this.ancestorMap = this.closest('arc-map') as any;

    if (!this.ancestorMap) {
      throw new Error(
        'arc-geojson-layer must be a descendant of an <arc-map> element'
      );
    }

    if (typeof this.ancestorMap.componentOnReady === 'function') {
      await this.ancestorMap.componentOnReady();
    }

    if (typeof this.ancestorMap.getViewInstance !== 'function') {
      throw new Error(
        'ancestor arc-map must expose getViewInstance()'
      );
    }

    this.view = await this.ancestorMap.getViewInstance();

    if (!this.view) {
      throw new Error(
        'ancestor arc-map getViewInstance() returned undefined'
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Layer creation — async so createEditor is properly awaited
  // ---------------------------------------------------------------------------

  private async createLayer(
    geojson: string | FeatureCollection
  ): Promise<void> {
    const parsedGeojson = geojson ?? {
      type: 'FeatureCollection',
      features: []
    };

    this.featureLayer = new GraphicsLayer({
      id: `${this.id || 'arc-geojson-layer'}-graphics`,
      title: this.name || this.id || 'Arc GeoJSON Layer'
    });

    this.labelLayer = new GraphicsLayer({
      id: `${this.id || 'arc-geojson-layer'}-labels`,
      title: `${this.name || this.id || 'Arc GeoJSON Layer'} Labels`
    });

    if (this.view?.map) {
      this.view.map.add(this.featureLayer);
      this.view.map.add(this.labelLayer);
    }

    const fsInfo = this.getUpGISJson(parsedGeojson);
    if (fsInfo) {
      for (const graphic of fsInfo.graphics) {
        this.featureLayer.add(graphic);
      }
    }

    this.updateRenderer(this.renderer);
    this.refreshLabels();
    this.updateInfoTemplate(this.infoTemplate);
    this.updateLayerClass(this.layerClass);

    // Must await so graphicsEditor exists before componentOnReady resolves
    await this.createEditor();

    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();
    this.blockGeoJsonUpdate = false;
  }

  // ---------------------------------------------------------------------------
  // Editor (SketchViewModel)
  // ---------------------------------------------------------------------------

  private async createEditor(): Promise<void> {
    this.graphicsEditor = new SketchViewModel({
      view: this.view,
      layer: this.featureLayer,
      defaultUpdateOptions: {
        enableRotation: this.enableUserEditRotating,
        enableScaling: this.enableUserEditScaling,
        multipleSelectionEnabled: false,
        preserveAspectRatio: this.enableUserEditUniformScaling,
        toggleToolOnClick: false
      },
      updateOnGraphicClick: false
    });

    this.graphicsEditor.on('create', (evt: any) => {
      console.log('create event state:', evt.state);

      if (evt.state === 'complete' && evt.graphic) {
        console.log('DRAWING COMPLETE - calling addToGeojson');
        // Unblock first so addToGeojson can set its own block
        this.inDrawingMode = false;
        this.blockGeoJsonUpdate = false;
        this.addToGeojson(evt.graphic);
        this.enableInfoPopupWindow(false);
      }

      if (evt.state === 'cancel') {
        console.log('DRAWING CANCELLED');
        this.inDrawingMode = false;
        this.blockGeoJsonUpdate = false;
      }
    });

    this.graphicsEditor.on('update', (evt: any) => {
      if (evt.state === 'start') {
        this.graphicMoved = false;
      }
      if (evt.toolEventInfo?.type === 'move-start') this.graphicMoved = true;
      if (evt.toolEventInfo?.type === 'reshape-start') this.graphicMoved = true;
      if (evt.toolEventInfo?.type === 'scale-start') this.graphicMoved = true;
      if (evt.toolEventInfo?.type === 'rotate-start') this.graphicMoved = true;

      if (evt.state === 'complete' && evt.graphics?.length) {
        for (const graphic of evt.graphics) {
          this.updateGeojsonWithChanges(graphic);
        }
        this.enableInfoPopupWindow(true);
      }

      if (evt.state === 'cancel') {
        this.enableInfoPopupWindow(true);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // View events
  // ---------------------------------------------------------------------------

  private bindViewEvents(): void {
    const clickHandle = this.view.on('click', async (evt: any) => {
      const hit = await this.view.hitTest(evt);
      const graphic = this.getLayerGraphicFromHit(hit);
      if (!graphic) return;

      if (this.enableUserEdit) {
        if (
          (evt.native?.ctrlKey || evt.native?.metaKey) &&
          this.enableUserEditRemove
        ) {
          this.removingItem = true;
          this.removeFromGeojson(graphic);
          this.graphicsEditor.cancel();
          this.removingItem = false;
          return;
        }
        await this.activateGraphicsEditor(graphic);
        return;
      }

      const mouseEvent = this.buildMouseEvent(graphic, evt.mapPoint);
      this.emitLayerEvent('layerClick', mouseEvent);

      if (!this.inDrawingMode) {
        this.showGraphicPopup(graphic, evt.mapPoint);
      }
    });

    const dblClickHandle = this.view.on(
      'double-click',
      async (evt: any) => {
        const hit = await this.view.hitTest(evt);
        const graphic = this.getLayerGraphicFromHit(hit);
        if (!graphic) return;

        const mouseEvent = this.buildMouseEvent(graphic, evt.mapPoint);
        this.emitLayerEvent('doubleClick', mouseEvent);

        if (this.enableUserEdit) {
          await this.activateGraphicsEditor(graphic);
          return;
        }

        if (!this.inDrawingMode) {
          this.showGraphicPopup(graphic, evt.mapPoint);
        }
      }
    );

    const pointerMoveHandle = this.view.on(
      'pointer-move',
      async (evt: any) => {
        const hit = await this.view.hitTest(evt);
        const graphic = this.getLayerGraphicFromHit(hit);

        if (!graphic) {
          if (this.hoveredGraphicUid !== undefined) {
            this.hoveredGraphicUid = undefined;
            this.emitLayerEvent('layerMouseOut', {
              coordinates: { latitude: 0, longitude: 0 },
              attributes: {}
            });
          }
          return;
        }

        const graphicUid = this.getGraphicUniqueId(graphic);
        if (this.hoveredGraphicUid !== graphicUid) {
          if (this.hoveredGraphicUid !== undefined) {
            this.emitLayerEvent(
              'layerMouseOut',
              this.buildMouseEvent(graphic, evt.mapPoint)
            );
          }
          this.hoveredGraphicUid = graphicUid;
          this.emitLayerEvent(
            'layerMouseOver',
            this.buildMouseEvent(graphic, evt.mapPoint)
          );
        }
      }
    );

    this.eventHandles.push(
      clickHandle,
      dblClickHandle,
      pointerMoveHandle
    );
  }

  // ---------------------------------------------------------------------------
  // Editing
  // ---------------------------------------------------------------------------

  async updateEditing(_newUserEnableEdit: boolean): Promise<void> {
    if (this.graphicsEditor?.state === 'active') {
      try { this.graphicsEditor.cancel(); } catch { }
    }

    if (_newUserEnableEdit) {
      this.featureLayer.graphics.forEach((graphic: Graphic) => {
        graphic.popupTemplate = null as unknown as never;
      });
    } else {
      this.featureLayer.graphics.forEach((graphic: Graphic) => {
        graphic.popupTemplate =
          this.buildPopupTemplateFromCurrent(graphic);
      });
    }

    this.enableInfoPopupWindow(
      !_newUserEnableEdit && !this.inDrawingMode
    );
  }

  // ---------------------------------------------------------------------------
  // GeoJSON update
  // ---------------------------------------------------------------------------

  async updateGeojson(
    newGeojson: string | FeatureCollection
  ): Promise<void> {
    if (this.blockGeoJsonUpdate) return;
    if (this.enableUserEdit || this.inDrawingMode || this.removingItem)
      return;

    if (!this.featureLayer) {
      await this.createLayer(newGeojson);
      return;
    }

    this.featureLayer.removeAll();
    this.labelLayer?.removeAll();

    const fsInfo = this.getUpGISJson(newGeojson);
    if (!fsInfo) return;

    for (const graphic of fsInfo.graphics) {
      this.featureLayer.add(graphic);
    }

    this.updateRenderer(this.renderer);
    this.refreshLabels();
    this.updateInfoTemplate(this.infoTemplate);
  }

  // ---------------------------------------------------------------------------
  // Info template
  // ---------------------------------------------------------------------------

  updateInfoTemplate(newInfoTemplate: any): void {
    this.infoTemplate = newInfoTemplate;
    if (!this.featureLayer) return;

    const parsed =
      ArcGeojsonLayer.parseJson<InfoTemplateDetails>(newInfoTemplate);
    if (!parsed.parsedJson) return;

    const info = parsed.parsedJson;
    this.featureLayer.graphics.forEach((graphic: Graphic) => {
      graphic.popupTemplate = this.buildPopupTemplate(info);
    });
  }

  // ---------------------------------------------------------------------------
  // Label JSON
  // ---------------------------------------------------------------------------

  updateLabelJson(newLabelJsonArg: string | object | object[]): void {
    this.labelJson = newLabelJsonArg;
    this.refreshLabels();
  }

  // ---------------------------------------------------------------------------
  // Layer class
  // ---------------------------------------------------------------------------

  updateLayerClass(newLayerClass: string): void {
    this.layerClass = newLayerClass;
    if (this.featureLayer)
      (this.featureLayer as any).className = newLayerClass;
    if (this.labelLayer)
      (this.labelLayer as any).className = `${newLayerClass}-labels`;
  }

  // ---------------------------------------------------------------------------
  // Renderer
  // ---------------------------------------------------------------------------

  updateRenderer(newRenderer: any): void {
    if (newRenderer !== undefined && newRenderer !== null) {
      this.renderer = newRenderer;
    }

    if (!this.featureLayer) return;

    const rendererToUse = this.renderer;
    if (!rendererToUse) {
      this.featureLayer.graphics.forEach((graphic: Graphic) => {
        if (graphic.geometry) {
          graphic.symbol = this.getDefaultSymbolForGeometry(
            graphic.geometry
          );
        }
      });
      return;
    }

    const parsed = ArcGeojsonLayer.parseJson(rendererToUse);
    if (!parsed.parsedJson) {
      this.featureLayer.graphics.forEach((graphic: Graphic) => {
        if (graphic.geometry) {
          graphic.symbol = this.getDefaultSymbolForGeometry(
            graphic.geometry
          );
        }
      });
      return;
    }

    this.featureLayer.graphics.forEach((graphic: Graphic) => {
      if (!graphic.geometry) return;
      graphic.symbol = this.getSymbolForGraphic(graphic);
    });
  }

  // ---------------------------------------------------------------------------
  // Drawing — public methods Angular calls
  // ---------------------------------------------------------------------------

  async startDrawing(drawGeometryType: string): Promise<void> {
    if (!this.featureLayer || !this.view) return;
    if (!this.graphicsEditor) {
      console.error('arc-geojson-layer: graphicsEditor not ready');
      return;
    }

    const existingType = this.determineExistingGeometryType();
    if (
      existingType &&
      !this.validGeometryType(drawGeometryType, existingType)
    )
      return;

    // Set BOTH flags before creating sketch tool
    // This blocks Angular NgRx from clearing the layer during drawing
    this.inDrawingMode = true;
    this.blockGeoJsonUpdate = true;

    this.enableInfoPopupWindow(false);
    this.graphicsEditor.create(
      this.toSketchCreateTool(drawGeometryType)
    );
  }

  async cancelDrawing(): Promise<void> {
    if (!this.graphicsEditor) return;
    this.inDrawingMode = false;
    this.blockGeoJsonUpdate = false;
    this.graphicsEditor.cancel();
    this.enableInfoPopupWindow(true);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  async findFeatureByUniqueId(
    uniqueId: string | number
  ): Promise<Graphic | undefined> {
    return this.featureLayer?.graphics.find(
      (graphic: Graphic) =>
        graphic.attributes?.[this.uniqueIdPropertyName] === uniqueId
    );
  }

  async getLayerId(): Promise<string> {
    return this.featureLayer?.id ?? 'arc-geojson-layer';
  }

  async openPopup(id: string | number): Promise<void> {
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic) return;
    if (!graphic.geometry) return;
    const popupPoint = ArcGeojsonLayer.getPopupPoint(graphic.geometry);
    this.showGraphicPopup(graphic, popupPoint);
  }

  async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic) return;

    const { geometry } = graphic;
    if (!geometry) return;

    if (ArcGeojsonLayer.isPoint(geometry)) {
      await this.view.goTo({ center: geometry, zoom: zoomLevel });
      return;
    }

    if (
      ArcGeojsonLayer.isPolyline(geometry) ||
      ArcGeojsonLayer.isPolygon(geometry)
    ) {
      const extent = geometry.extent;
      if (extent) {
        await this.view.goTo(extent.expand(1.5));
      }
    }
  }

  enableInfoPopupWindow(enable: boolean): void {
    const enablePopup =
      enable && !this.enableUserEdit && !this.inDrawingMode;
    if (!enablePopup && this.view?.popup?.visible) {
      this.view.popup.close();
    }
  }

  async activateGraphicsEditor(graphic: Graphic): Promise<void> {
    if (!this.enableUserEdit) return;
    if (!this.graphicsEditor) return;

    this.enableInfoPopupWindow(false);

    const updateOptions: any = {
      tool: this.resolveUpdateTool(),
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      multipleSelectionEnabled: false,
      toggleToolOnClick: false
    };

    this.graphicsEditor.update([graphic], updateOptions);
  }

  // ---------------------------------------------------------------------------
  // Symbol for graphic — uses renderer if set, else default
  // ---------------------------------------------------------------------------

  private getSymbolForGraphic(graphic: Graphic): any {
    if (!graphic.geometry) return null;

    if (this.renderer) {
      const parsed = ArcGeojsonLayer.parseJson(this.renderer);
      if (parsed.parsedJson) {
        const config = parsed.parsedJson;

        // Simple renderer
        if (config.type === 'simple' && config.symbol) {
          return JsonUtils.normalizePlainSymbol(config.symbol);
        }

        // UniqueValue renderer
        if (
          Array.isArray(config.uniqueValueInfos) &&
          config.uniqueValueInfos.length
        ) {
          const geomType = graphic.geometry.type;

          const match = config.uniqueValueInfos.find((info: any) => {
            const val = (info.value ?? '').toString().toLowerCase();
            const symType = (info.symbol?.type ?? '')
              .toLowerCase()
              .replace(/[\s-_]/g, '');

            if (geomType === 'polygon') {
              return (
                val.endsWith('polygon') ||
                symType === 'esrisfs' ||
                symType === 'simplefill' ||
                symType === 'simplefillsymbol'
              );
            }
            if (geomType === 'polyline') {
              return (
                val.endsWith('polyline') ||
                val.endsWith('line') ||
                symType === 'esrisls' ||
                symType === 'simpleline' ||
                symType === 'simplelinesymbol'
              );
            }
            return (
              symType === 'esrisms' ||
              symType === 'esrismscirlce' ||
              symType === 'esrismscircle' ||
              symType === 'simplemarker' ||
              symType === 'simplemarkersymbol' ||
              (!val.endsWith('polygon') && !val.endsWith('polyline'))
            );
          });

          if (match?.symbol) {
            return JsonUtils.normalizePlainSymbol(match.symbol);
          }
        }

        if (config.defaultSymbol) {
          return JsonUtils.normalizePlainSymbol(config.defaultSymbol);
        }
      }
    }

    return this.getDefaultSymbolForGeometry(graphic.geometry);
  }

  // ---------------------------------------------------------------------------
  // Internal GeoJSON helpers
  // ---------------------------------------------------------------------------

  private getUpGISJson(
    geojson: string | object
  ): { graphics: Graphic[]; geometryType?: string } | null {
    const result =
      ArcGeojsonLayer.parseJson<FeatureCollection>(geojson);
    if (
      !result.parsedJson ||
      result.parsedJson.type !== 'FeatureCollection'
    )
      return null;

    const graphics: Graphic[] = [];
    let geometryType: string | undefined;

    result.parsedJson.features.forEach(
      (feature: Feature, index: number) => {
        const graphic = this.geojsonFeatureToGraphic(feature, index);
        if (graphic) {
          if (!graphic.geometry) return;
          if (geometryType === undefined)
            geometryType = graphic.geometry.type;
          graphics.push(graphic);
        }
      }
    );

    return { graphics, geometryType };
  }

  private geojsonFeatureToGraphic(
    feature: Feature,
    index: number
  ): Graphic | null {
    const geometry = this.geojsonGeometryToArcGeometry(
      feature.geometry
    );
    if (!geometry) return null;

    const properties = { ...(feature.properties ?? {}) } as any;
    if (properties[this.uniqueIdPropertyName] === undefined)
      properties[this.uniqueIdPropertyName] = index;
    if (properties.OBJECTID === undefined) properties.OBJECTID = index;

    const graphic = new Graphic({
      geometry,
      attributes: properties,
      symbol: this.getDefaultSymbolForGeometry(geometry)
    });

    graphic.symbol = this.getSymbolForGraphic(graphic);

    graphic.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic,
      infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName,
      fallbackTitle: this.name || 'Details'
    });

    return graphic;
  }

  private geojsonGeometryToArcGeometry(
    geometry: GeoJsonGeometry | null
  ): Geometry | null {
    if (!geometry) return null;

    switch (geometry.type) {
      case 'Point': {
        const [x, y] = geometry.coordinates as number[];
        return new Point({ x, y, spatialReference: { wkid: 4326 } });
      }
      case 'MultiPoint': {
        const points = geometry.coordinates as number[][];
        if (!points.length) return null;
        return new Point({
          x: points[0][0],
          y: points[0][1],
          spatialReference: { wkid: 4326 }
        });
      }
      case 'LineString': {
        return new Polyline({
          paths: [geometry.coordinates as number[][]],
          spatialReference: { wkid: 4326 }
        });
      }
      case 'MultiLineString': {
        return new Polyline({
          paths: geometry.coordinates as number[][][],
          spatialReference: { wkid: 4326 }
        });
      }
      case 'Polygon': {
        return new Polygon({
          rings: geometry.coordinates as number[][][],
          spatialReference: { wkid: 4326 }
        });
      }
      case 'MultiPolygon': {
        const firstPolygon = (
          geometry.coordinates as number[][][][]
        )[0];
        if (!firstPolygon) return null;
        return new Polygon({
          rings: firstPolygon,
          spatialReference: { wkid: 4326 }
        });
      }
      default:
        return null;
    }
  }

  private arcGeometryToGeoJsonGeometry(
    geometry: Geometry
  ): GeoJsonGeometry {
    if (ArcGeojsonLayer.isPoint(geometry)) {
      const pt = this.toGeographicPoint(geometry as Point);
      return { type: 'Point', coordinates: [pt.x, pt.y] };
    }

    if (ArcGeojsonLayer.isPolyline(geometry)) {
      const pl = this.toGeographicPolyline(geometry as Polyline);
      const paths = pl.paths ?? [];
      return paths.length <= 1
        ? { type: 'LineString', coordinates: paths[0] ?? [] }
        : { type: 'MultiLineString', coordinates: paths };
    }

    const poly = this.toGeographicPolygon(geometry as Polygon);
    return { type: 'Polygon', coordinates: poly.rings as any };
  }

  private graphicToGeoJsonFeature(graphic: Graphic): Feature | null {
    if (!graphic.geometry) return null;
    return {
      type: 'Feature',
      geometry: this.arcGeometryToGeoJsonGeometry(graphic.geometry),
      properties: { ...(graphic.attributes ?? {}) }
    };
  }

  private toFeatureCollectionFromLayer(): FeatureCollection {
    return {
      type: 'FeatureCollection',
      features: this.featureLayer.graphics
        .toArray()
        .map((g: Graphic) => this.graphicToGeoJsonFeature(g))
        .filter((f: Feature | null): f is Feature => f !== null)
    };
  }

  // ---------------------------------------------------------------------------
  // addToGeojson — setTimeout blocks NgRx echo
  // ---------------------------------------------------------------------------

  private addToGeojson(newGraphic: Graphic): void {
    if (!newGraphic.attributes) newGraphic.attributes = {};

    if (newGraphic.attributes[this.uniqueIdPropertyName] === undefined) {
      newGraphic.attributes[this.uniqueIdPropertyName] = Date.now();
    }
    if (newGraphic.attributes.OBJECTID === undefined) {
      newGraphic.attributes.OBJECTID = Date.now();
    }

    newGraphic.symbol = this.getSymbolForGraphic(newGraphic);

    newGraphic.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic: newGraphic,
      infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName,
      fallbackTitle: this.name || 'Details'
    });

    if (!this.featureLayer.graphics.includes(newGraphic)) {
      this.featureLayer.add(newGraphic);
    }

    this._internalUpdateId++;
    const currentId = this._internalUpdateId;

    // Block geojson updates while we emit and wait for NgRx echo
    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();

    // Keep blocked long enough for Angular NgRx echo to arrive
    setTimeout(() => {
      if (this._internalUpdateId === currentId) {
        this.blockGeoJsonUpdate = false;
      }
    }, 500);

    this.refreshLabels();
    this.emitLayerEvent(
      'userDrawItemAdded',
      this.graphicToGeoJsonFeature(newGraphic)
    );
  }

  // ---------------------------------------------------------------------------
  // removeFromGeojson — setTimeout blocks NgRx echo
  // ---------------------------------------------------------------------------

  private removeFromGeojson(graphicToRemove: Graphic): void {
    this.featureLayer.remove(graphicToRemove);

    this._internalUpdateId++;
    const currentId = this._internalUpdateId;

    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();

    setTimeout(() => {
      if (this._internalUpdateId === currentId) {
        this.blockGeoJsonUpdate = false;
      }
    }, 500);

    this.refreshLabels();
    this.emitLayerEvent(
      'userEditItemRemoved',
      this.graphicToGeoJsonFeature(graphicToRemove)
    );
  }

  // ---------------------------------------------------------------------------
  // updateGeojsonWithChanges — setTimeout blocks NgRx echo
  // ---------------------------------------------------------------------------

  private updateGeojsonWithChanges(graphicToUpdate: Graphic): void {
    graphicToUpdate.popupTemplate =
      JsonUtils.buildPopupTemplateFromCurrent({
        graphic: graphicToUpdate,
        infoTemplate: this.infoTemplate,
        uniqueIdPropertyName: this.uniqueIdPropertyName,
        fallbackTitle: this.name || 'Details'
      });

    this._internalUpdateId++;
    const currentId = this._internalUpdateId;

    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();

    setTimeout(() => {
      if (this._internalUpdateId === currentId) {
        this.blockGeoJsonUpdate = false;
      }
    }, 500);

    this.refreshLabels();
    this.emitLayerEvent(
      'userEditItemUpdated',
      this.graphicToGeoJsonFeature(graphicToUpdate)
    );
  }

  // ---------------------------------------------------------------------------
  // Popup
  // ---------------------------------------------------------------------------

  private buildPopupTemplate(info: InfoTemplateDetails): PopupTemplate {
    return new PopupTemplate({
      title: (event: any) => {
        const graphic = event?.graphic ?? event;
        return typeof info.listItem === 'function'
          ? info.listItem(graphic)
          : info.listItem;
      },
      content: (event: any) => {
        const graphic = event?.graphic ?? event;
        return typeof info.details === 'function'
          ? info.details(graphic)
          : info.details;
      }
    });
  }

  private buildPopupTemplateFromCurrent(
    graphic: Graphic
  ): PopupTemplate | null {
    const parsed =
      ArcGeojsonLayer.parseJson<InfoTemplateDetails>(this.infoTemplate);
    if (!parsed.parsedJson) return null;

    const info = parsed.parsedJson;
    const title =
      typeof info.listItem === 'function'
        ? info.listItem(graphic)
        : info.listItem;
    const content =
      typeof info.details === 'function'
        ? info.details(graphic)
        : info.details;

    return new PopupTemplate({ title, content });
  }

  private showGraphicPopup(graphic: Graphic, mapPoint?: Point): void {
    if (this.enableUserEdit || this.inDrawingMode) return;
    if (!graphic.geometry) return;
    const location =
      mapPoint ?? ArcGeojsonLayer.getPopupPoint(graphic.geometry);
    graphic.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic,
      infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName,
      fallbackTitle: this.name || 'Details'
    });
    if (this.view?.popup) {
      this.view.openPopup({ location, features: [graphic] });
    }
  }

  // ---------------------------------------------------------------------------
  // Labels
  // ---------------------------------------------------------------------------

  private refreshLabels(): void {
    if (!this.labelLayer) return;
    this.labelLayer.removeAll();

    const labelColor = JsonUtils.resolveLabelColor(this.labelColor);
    const labelSize = JsonUtils.resolveLabelSize(this.labelSize);

    this.featureLayer.graphics.forEach((graphic: Graphic) => {
      const label = graphic.attributes?.LABEL;
      if (!label) return;
      if (!graphic.geometry) return;
      const labelPoint = ArcGeojsonLayer.getPopupPoint(
        graphic.geometry
      );

      this.labelLayer.add(
        new Graphic({
          geometry: labelPoint,
          attributes: {
            __labelFor:
              graphic.attributes?.[this.uniqueIdPropertyName]
          },
          symbol: new TextSymbol({
            text: String(label),
            color: labelColor as any,
            haloColor: 'black',
            haloSize: 1,
            xoffset: 3,
            yoffset: 3,
            font: {
              size: labelSize,
              family: 'sans-serif',
              weight: 'bold'
            }
          })
        })
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Default symbol for geometry
  // ---------------------------------------------------------------------------

  private getDefaultSymbolForGeometry(
    geometry: Geometry | null | undefined
  ): any {
    if (!geometry) return null;

    if (ArcGeojsonLayer.isPoint(geometry)) {
      return new SimpleMarkerSymbol({
        style: 'circle',
        color: this.DEFAULT_SYMBOL_COLOR as any,
        size: ArcGeojsonLayer.DEFAULT_SYMBOL_MARKER_SIZE,
        outline: {
          color: [0, 0, 0, 200],
          width: 1,
          style: 'solid'
        } as any
      });
    }

    if (ArcGeojsonLayer.isPolyline(geometry)) {
      return new SimpleLineSymbol({
        style: 'solid',
        color: this.DEFAULT_SYMBOL_COLOR as any,
        width: ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH
      });
    }

    return new SimpleFillSymbol({
      style: 'solid',
      color: [
        this.DEFAULT_SYMBOL_COLOR[0],
        this.DEFAULT_SYMBOL_COLOR[1],
        this.DEFAULT_SYMBOL_COLOR[2],
        100
      ] as any,
      outline: {
        color: [110, 110, 110, 255],
        width: ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH,
        style: 'solid'
      } as any
    });
  }

  // ---------------------------------------------------------------------------
  // Geometry type helpers
  // ---------------------------------------------------------------------------

  private determineExistingGeometryType(): string | undefined {
    return this.featureLayer?.graphics?.getItemAt(0)?.geometry?.type;
  }

  private validGeometryType(
    drawGeometryType: string,
    featureLayerGeometryType: string
  ): boolean {
    return (
      this.determineFeatureLayerGeometryType(drawGeometryType) ===
      featureLayerGeometryType
    );
  }

  private determineFeatureLayerGeometryType(
    drawGeometryType: string
  ): string {
    switch ((drawGeometryType || '').toUpperCase()) {
      case DrawGeometryTypes.FREEHAND_POLYLINE:
      case DrawGeometryTypes.LINE:
      case DrawGeometryTypes.POLYLINE:
        return 'polyline';
      case DrawGeometryTypes.MULTI_POINT:
        return 'multipoint';
      case DrawGeometryTypes.POINT:
        return 'point';
      default:
        return 'polygon';
    }
  }

  private toSketchCreateTool(
    drawGeometryType: string
  ): 'point' | 'polyline' | 'polygon' | 'rectangle' | 'circle' {
    switch ((drawGeometryType || '').toUpperCase()) {
      case DrawGeometryTypes.POINT:
        return 'point';
      case DrawGeometryTypes.LINE:
      case DrawGeometryTypes.POLYLINE:
      case DrawGeometryTypes.FREEHAND_POLYLINE:
        return 'polyline';
      case DrawGeometryTypes.RECTANGLE:
      case DrawGeometryTypes.EXTENT:
        return 'rectangle';
      case DrawGeometryTypes.CIRCLE:
      case DrawGeometryTypes.ELLIPSE:
        return 'circle';
      default:
        return 'polygon';
    }
  }

  private resolveUpdateTool(): 'move' | 'reshape' | 'transform' {
    if (
      this.enableUserEditVertices ||
      this.enableUserEditAddVertices ||
      this.enableUserEditDeleteVertices
    ) {
      return 'reshape';
    }
    if (this.enableUserEditScaling || this.enableUserEditRotating) {
      return 'transform';
    }
    return 'move';
  }

  // ---------------------------------------------------------------------------
  // Geographic projection helpers
  // ---------------------------------------------------------------------------

  private toGeographicPoint(point: Point): Point {
    return point.spatialReference?.isWGS84
      ? point
      : (webMercatorUtils.webMercatorToGeographic(point) as Point);
  }

  private toGeographicPolyline(polyline: Polyline): Polyline {
    return polyline.spatialReference?.isWGS84
      ? polyline
      : (webMercatorUtils.webMercatorToGeographic(
          polyline
        ) as Polyline);
  }

  private toGeographicPolygon(polygon: Polygon): Polygon {
    return polygon.spatialReference?.isWGS84
      ? polygon
      : (webMercatorUtils.webMercatorToGeographic(polygon) as Polygon);
  }

  // ---------------------------------------------------------------------------
  // Mouse events
  // ---------------------------------------------------------------------------

  private buildMouseEvent(
    graphic: Graphic,
    mapPoint: Point | null
  ): LayerMouseEvent {
    const geographicPoint = mapPoint
      ? (webMercatorUtils.webMercatorToGeographic(mapPoint) as Point)
      : null;

    return {
      coordinates: {
        latitude: geographicPoint?.y ?? 0,
        longitude: geographicPoint?.x ?? 0
      },
      attributes: graphic?.attributes ?? {}
    };
  }

  private emitLayerEvent(name: string, detail: any): void {
    this.dispatchEvent(
      new CustomEvent(name, {
        detail,
        bubbles: true,
        composed: true
      })
    );
  }

  private getLayerGraphicFromHit(hit: any): Graphic | undefined {
    const result = hit?.results?.find(
      (r: any) => r.graphic?.layer === this.featureLayer
    );
    return result?.graphic as Graphic | undefined;
  }

  private getGraphicUniqueId(
    graphic: Graphic
  ): string | number | undefined {
    return (
      graphic.attributes?.[this.uniqueIdPropertyName] ??
      graphic.attributes?.OBJECTID
    );
  }

  // ---------------------------------------------------------------------------
  // Static helpers
  // ---------------------------------------------------------------------------

  static parseJson<T = any>(value: any): JsonParseResult<T> {
    if (value === null || value === undefined) {
      return { error: new Error('Value is null or undefined') };
    }
    if (typeof value === 'string') {
      try {
        return { parsedJson: JSON.parse(value) as T };
      } catch (e: any) {
        return {
          error: e instanceof Error ? e : new Error(String(e))
        };
      }
    }
    return { parsedJson: value as T };
  }

  private static getPopupPoint(geometry: Geometry): Point {
    if (!geometry) return new Point({ x: 0, y: 0 });
    if (ArcGeojsonLayer.isPoint(geometry)) {
      return geometry as Point;
    }
    if (ArcGeojsonLayer.isPolyline(geometry)) {
      const polyline = geometry as Polyline;
      const path = polyline.paths?.[0] ?? [];
      const mid = Math.floor(path.length / 2);
      return new Point({
        x: path[mid]?.[0] ?? 0,
        y: path[mid]?.[1] ?? 0,
        spatialReference: polyline.spatialReference
      });
    }
    if (ArcGeojsonLayer.isPolygon(geometry)) {
      return (
        (geometry as Polygon).centroid ?? new Point({ x: 0, y: 0 })
      );
    }
    return new Point({ x: 0, y: 0 });
  }

  static getRandomColor(): number[] {
    return [
      Math.floor(Math.random() * 200),
      Math.floor(Math.random() * 200),
      Math.floor(Math.random() * 200),
      200
    ];
  }

  static isPoint(geometry: Geometry): geometry is Point {
    return geometry?.type === 'point';
  }

  static isPolyline(geometry: Geometry): geometry is Polyline {
    return geometry?.type === 'polyline';
  }

  static isPolygon(geometry: Geometry): geometry is Polygon {
    return geometry?.type === 'polygon';
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'arc-geojson-layer': ArcGeojsonLayer;
  }
}
