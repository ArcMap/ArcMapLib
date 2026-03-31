import FeatureLayer from '@arcgis/core/layers/FeatureLayer';
import * as webMercatorUtils from '@arcgis/core/geometry/support/webMercatorUtils';
import type { MouseEvent as LayerMouseEvent } from '../external-api';

export enum MouseEventTypes {
  Click = 'click',
  DoubleClick = 'dbl-click',
  MouseOut = 'mouse-out',
  MouseOver = 'mouse-over',
}

export default class MouseUtils {
  static MouseEventTypes = MouseEventTypes;

  static addMouseEventsToFeatureLayer(
    featureLayer: FeatureLayer,
    esriEventToCustomEvent: Map<string, string>,
    element: HTMLElement,
  ): IHandle[] {
    const handles: IHandle[] = [];
    esriEventToCustomEvent.forEach((customEventName, esriEvent) => {
      handles.push(
        featureLayer.on(esriEvent as any, (event: any) => {
          const usableEvent = event as any;
          const coordinates = webMercatorUtils.webMercatorToGeographic(usableEvent.mapPoint) as any;
          const detail: LayerMouseEvent = {
            coordinates: {
              latitude: coordinates.y,
              longitude: coordinates.x,
            },
            attributes: usableEvent.graphic?.attributes,
          };
          element.dispatchEvent(new CustomEvent(customEventName, {
            detail,
            bubbles: true,
            composed: true,
          }));
        })
      );
    });
    return handles;
  }
}

interface IHandle {
  remove(): void;
}


import type { ArcMapElement } from '../external-api';

export default class MapUtils {
  static findArcMapById(mapId: string): ArcMapElement {
    const mapElement = document.getElementById(mapId) as HTMLElement;
    if (MapUtils.isArcMap(mapElement)) {
      return mapElement as unknown as ArcMapElement;
    }
    console.error('Could not find a arc-map element with id of', mapId);
    return undefined as any;
  }

  static isArcMap(element: HTMLElement): boolean {
    return element && element.tagName && 'ARC-MAP' === element.tagName;
  }

  static findArcMapByIdOrDefault(mapId?: string): ArcMapElement {
    let arcMapElement: ArcMapElement;
    if (mapId) {
      arcMapElement = MapUtils.findArcMapById(mapId);
    } else {
      const arcMapTags = document.querySelectorAll('arc-map');
      if (arcMapTags.length === 0) {
        console.error('Could not find any arc-map on this page.');
      } else if (arcMapTags.length === 1) {
        arcMapElement = arcMapTags[0] as unknown as ArcMapElement;
      } else {
        console.error('More than one arc-map found on this page. Map id is required.');
      }
    }
    return arcMapElement!;
  }

  static getEsriMapPromiseFromArcMapElement(mapElement: ArcMapElement): Promise<any> {
    return (mapElement as any).updateComplete.then(() => {
      return (mapElement as any).getEsriMap();
    });
  }

  static getLayerName(esriLayer: any): string {
    const title = esriLayer.title;
    const name = esriLayer.name;
    return title ? title :
      name ? name :
        esriLayer.layerInfos ? esriLayer.layerInfos[0].title :
          '';
  }
}


import PopupTemplate from '@arcgis/core/PopupTemplate';
import FeatureLayer from '@arcgis/core/layers/FeatureLayer';
import JsonUtils from './json-utils';
import type { ArcMapElement } from '../external-api';

export default class PopupUtils {
  static async updatePopup(
    newInfoTemplate: any,
    mapElement: ArcMapElement,
    featureLayer: FeatureLayer,
  ) {
    if (!featureLayer) return;

    const templateParseResult = JsonUtils.getJsonFor(newInfoTemplate);
    if (templateParseResult.error) {
      console.warn('could not parse infoTemplate value', templateParseResult.error);
      return;
    }

    const parsedInfoTemplate = templateParseResult.parsedJson;
    const esriMap = await (mapElement as any).getEsriMap();
    const popup = (esriMap as any).popup;

    if (parsedInfoTemplate) {
      const template = new PopupTemplate({
        title: parsedInfoTemplate.listItem,
        content: (parsedInfoTemplate.details === null || parsedInfoTemplate.details === undefined)
          ? 'No Details Available'
          : parsedInfoTemplate.details,
      } as any);

      featureLayer.popupTemplate = template;

      if (popup?.visible && popup?.features) {
        const selectedIndex = popup.selectedFeatureIndex;
        popup.features = popup.features;
        popup.selectedFeatureIndex = selectedIndex;
      }

      const layerNode = (featureLayer as any).getNode?.();
      if (layerNode) {
        layerNode.style.setProperty('cursor', 'pointer');
      }
    } else {
      featureLayer.popupTemplate = null as any;
      if (popup?.visible && popup?.features) {
        popup.features = [];
        popup.visible = false;
      }
      const layerNode = (featureLayer as any).getNode?.();
      if (layerNode) {
        layerNode.style.removeProperty('cursor');
      }
    }
  }
}


import { LitElement, PropertyValues } from 'lit';
import { customElement, property } from 'lit/decorators.js';
import { FeatureCollection } from 'geojson';
import { isEqual } from 'lodash-es';
import { arcgisToGeoJSON, geojsonToArcGIS } from '@terraformer/arcgis';

import FeatureLayer from '@arcgis/core/layers/FeatureLayer';
import Graphic from '@arcgis/core/Graphic';
import Point from '@arcgis/core/geometry/Point';
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
import type { ArcMapElement, InfoTemplateDetails, MouseEvent as LayerMouseEvent } from '../../external-api';

interface IHandle { remove(): void; }

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
  private objectIdField = { name: 'OBJECTID', type: 'oid' as const, alias: 'OBJECTID' };

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

  // ─── Lifecycle ────────────────────────────────────────────────────────────
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
      PopupUtils.updatePopup(this.infoTemplate, this.ancestorMap, this.featureLayer);
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
      console.error('<arc-geojson-layer> must be a descendent of a <arc-map> element');
      return;
    }
    this.createLayer(this.geojson);
  }

  private async _cleanup() {
    if (this.ancestorMap && this.featureLayer) {
      await this.ancestorMap.removeLayer(this.featureLayer);
    }
    this.eventHandles.forEach(h => h.remove());
    this.eventHandles = [];
    this.blockGeoJsonUpdate = false;
    this.featureLayer = null as any;
  }

  // ─── Geojson watcher ──────────────────────────────────────────────────────
  private async _onGeojsonChanged(newGeojson: string | FeatureCollection) {
    if (this.enableUserEdit || this.inDrawingMode) {
      console.warn('Cannot update GeoJson while user is editing or drawing new features.');
      return;
    }
    if (this.removingItem || this.blockGeoJsonUpdate) return;

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

    const newUniqueIds = fsInfo.jsonFS.features.map((g: any) => g.attributes[this.uniqueIdPropertyName]);
    const featuresToRemove = this.featureLayer.graphics.filter((graphic: any) => {
      const existingId = graphic.attributes[this.uniqueIdPropertyName];
      return existingId === undefined || !newUniqueIds.includes(existingId);
    });

    await this.featureLayer.applyEdits({
      addFeatures: featuresToAdd,
      updateFeatures: featuresToUpdate,
      deleteFeatures: featuresToRemove.toArray(),
    });
    this.featureLayer.refresh();

    const convertedGeoJson = arcgisToGeoJSON((this.featureLayer as any).toJSON().featureSet);
    this.blockGeoJsonUpdate = true;
    this.geojson = convertedGeoJson as any;
    this.blockGeoJsonUpdate = false;

    // Update popup if visible
    const esriMap = await this.ancestorMap.getEsriMap();
    const popup = (esriMap as any).popup;
    if (popup?.visible && popup?.features) {
      if (popup.features.length === 1) {
        const detailsFeature = popup.features[0];
        if (detailsFeature.getLayer() !== this.featureLayer) return;
        if (
          detailsFeature.attributes[this.uniqueIdPropertyName] === undefined ||
          !this.featureLayer.graphics.includes(detailsFeature)
        ) {
          popup.visible = false;
        } else if (!isEqual(popup.features[0]?.geometry, detailsFeature.geometry)) {
          popup.features = [detailsFeature];
          popup.location = ArcGeoJsonLayer.getPopupPoint(detailsFeature.geometry);
          popup.visible = true;
        }
      } else {
        const featuresToKeep = popup.features.filter((f: any, i: number) =>
          !featuresToRemove.includes(f) && isEqual(popup.features[i]?.geometry, f.geometry)
        );
        popup.features = featuresToKeep;
        if (featuresToKeep.length === 0) popup.visible = false;
      }
    }
  }

  // ─── Prop watchers ────────────────────────────────────────────────────────
  private updateEditing(newUserEnableEdit: boolean) {
    this.enableInfoPopupWindow(!newUserEnableEdit);
    if (!newUserEnableEdit) this.graphicsEditor?.cancel();
  }

  private _updateRenderer(newRenderer: any) {
    if (!this.featureLayer) return;
    const symbolJson = this.getSymbolJson(this.featureLayer.geometryType);
    const rendererTypeToModule = {
      simple: 'simple',
      uniqueValue: 'unique-value',
      classBreaks: 'class-breaks',
    };
    JsonUtils.updateRenderer(newRenderer, this.featureLayer, rendererTypeToModule, symbolJson);
  }

  // ─── Public methods ───────────────────────────────────────────────────────
  async startDrawing(drawGeometryType: string) {
    if (this.featureLayer.graphics.length === 0) {
      this.featureLayer.geometryType =
        DrawEditUtils.determineFeatureLayerGeometryType(drawGeometryType) as any;
    }
    if (!DrawEditUtils.validGeometryType(drawGeometryType, this.featureLayer.geometryType)) return;
    if (!(drawGeometryType.toUpperCase() in DrawEditUtils.DrawGeometryTypes)) {
      console.error('The geometry type ' + drawGeometryType + ' is invalid. Drawing cancelled.');
      return;
    }
    this.inDrawingMode = true;
    this.enableInfoPopupWindow(false);
    const esriMap = await this.ancestorMap.getEsriMap();
    if (!this.esriDraw) this.esriDraw = new Draw({ view: esriMap as any });
    this.esriDraw.create(drawGeometryType as any);
    await this.ancestorMap.hideZoomSlider();
    await this.ancestorMap.hideScaleBar();
  }

  async cancelDrawing() {
    this.inDrawingMode = false;
    this.esriDraw?.destroy();
    this.esriDraw = null as any;
    await this.ancestorMap.showZoomSlider();
    await this.ancestorMap.showScaleBar();
    this.enableInfoPopupWindow(true);
  }

  async findFeatureByUniqueId(uniqueId: string | number): Promise<any> {
    return this.featureLayer.graphics.find((graphic: any) =>
      graphic.attributes[this.uniqueIdPropertyName] !== undefined &&
      graphic.attributes[this.uniqueIdPropertyName] === uniqueId
    );
  }

  async getLayerId(): Promise<string> {
    return this.featureLayer?.id ?? '';
  }

  async openPopup(id: string | number) {
    const graphicMatch: Graphic = await this.findFeatureByUniqueId(id);
    if (graphicMatch === undefined) {
      console.warn('No feature found with a', this.uniqueIdPropertyName, 'value of', id, '. Cannot open popup.');
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
      console.warn('No feature found with a', this.uniqueIdPropertyName, 'value of', id, '. Cannot zoom to.');
      return;
    }
    const esriMap = await this.ancestorMap.getEsriMap();
    const view = esriMap as any;
    const geometry = graphicMatch.geometry;
    if (ValidationService.isPoint(geometry)) {
      return view.goTo({ target: geometry, zoom: zoomLevel });
    } else if (ValidationService.isPolyline(geometry) || ValidationService.isPolygon(geometry)) {
      return view.goTo(geometry.extent);
    } else {
      console.error('Unrecognized geometry type', (geometry as any).type);
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────────────
  private async createDrawing() {
    const esriMap = await this.ancestorMap.getEsriMap();
    this.esriDraw = new Draw({ view: esriMap as any });

    this.esriDraw.on('draw-complete', async (evt: any) => {
      await this.ancestorMap.showZoomSlider();
      await this.ancestorMap.showScaleBar();
      this.esriDraw.destroy();
      this.esriDraw = null as any;

      const newGeometry = evt.geometry;
      let graphic: Graphic;

      if (this.renderer) {
        graphic = new Graphic({ geometry: newGeometry });
      } else {
        let symbol: any;
        switch (newGeometry.type) {
          case 'point':
          case 'multipoint':
            symbol = new SimpleMarkerSymbol(); break;
          case 'polyline':
            symbol = new SimpleLineSymbol(); break;
          default:
            symbol = new SimpleFillSymbol();
        }
        graphic = new Graphic({ geometry: newGeometry, symbol });
      }

      const addingFirstGeometry = this.featureLayer.graphics.length === 0;
      this.addToGeoJson(graphic);
      if (this.renderer && addingFirstGeometry) this._updateRenderer(this.renderer);

      this.inDrawingMode = false;
      this.enableInfoPopupWindow(true);
    });
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
      if (evt.state === 'complete' || evt.state === 'cancel') {
        evt.graphics?.forEach((g: Graphic) => this.updateGeoJsonWithChanges(g));
      }
    });

    this.graphicsEditor.on('rotate', (evt: any) => {
      if (evt.state === 'complete') evt.graphics?.forEach((g: Graphic) => this.updateGeoJsonWithChanges(g));
    });

    this.graphicsEditor.on('scale', (evt: any) => {
      if (evt.state === 'complete') evt.graphics?.forEach((g: Graphic) => this.updateGeoJsonWithChanges(g));
    });

    this.featureLayer.on('click', (evt: any) => {
      if (this.enableUserEdit) {
        if (evt.ctrlKey && this.enableUserEditRemove) {
          this.removingItem = true;
          this.removeFromGeoJson(evt.graphic);
          this.graphicsEditor.cancel();
          this.removingItem = false;
          return;
        }
        this.activateGraphicsEditor(evt.graphic);
      }
    });
  }

  private enableInfoPopupWindow(enable: boolean) {
    const enablePopup = enable && !this.enableUserEdit && !this.inDrawingMode;
    this.ancestorMap.enableInfoWindow(enablePopup);
  }

  private async activateGraphicsEditor(graphic: Graphic) {
    let tool = 0;
    if (this.enableUserEditMove) tool = tool | 1;
    if (this.enableUserEditVertices) tool = tool | 2;
    if (this.enableUserEditScaling) tool = tool | 4;
    if (this.enableUserEditRotating) tool = tool | 8;

    const options: any = {
      allowAddVertices: this.enableUserEditAddVertices,
      allowDeleteVertices: this.enableUserEditDeleteVertices,
      uniformScaling: this.enableUserEditUniformScaling,
    };

    if (tool !== 0) {
      this.graphicsEditor.update([graphic], { tool: 'transform', ...options });
    } else {
      console.error('Cannot edit. All editing features have been turned off.');
    }
  }

  private static getPopupPoint(geometry: any): Point {
    if (ValidationService.isPoint(geometry)) return geometry;
    else if (ValidationService.isPolyline(geometry)) {
      const middleIndex = Math.floor(geometry.paths[0].length / 2);
      return geometry.getPoint(0, middleIndex);
    } else if (ValidationService.isPolygon(geometry)) return geometry.centroid;
    return null as any;
  }

  private createLayer(geojson: string | FeatureCollection): void {
    if (!geojson) geojson = { type: 'FeatureCollection', features: [] };

    const fsInfo = this._getArcGisJson(geojson);
    if (fsInfo == null) {
      console.error('<arc-geojson-layer> unable to create geojson layer, geojson property contains invalid data: \n' + geojson);
      return;
    }

    this.createDrawing();

    fsInfo.jsonFS.features.forEach((feature: any, index: number) => {
      feature.attributes.OBJECTID = index;
    });

    const featureLayer = new FeatureLayer({
      id: this.id || undefined,
      source: fsInfo.jsonFS.features,
      geometryType: fsInfo.jsonFS.geometryType as any,
      spatialReference: { wkid: 4326 },
      fields: [this.objectIdField as any],
      objectIdField: 'OBJECTID',
      className: this.layerClass,
    });

    this.featureLayer = featureLayer;
    this.ancestorMap.addLayer(this.featureLayer, this);

    if (this.featureLayer) {
      if (this.renderer && this.featureLayer.graphics.length !== 0) {
        this._updateRenderer(this.renderer);
      } else {
        const symbolJson = this.getSymbolJson(fsInfo.jsonFS.geometryType);
        this.featureLayer.renderer = new SimpleRenderer(symbolJson as any);
      }

      this.featureLayer.title = this.name;

      const labelJson = JsonUtils.getLabelJson(this.labelJson, this.labelColor, this.labelSize);
      JsonUtils.updateLabelJson(labelJson, this.featureLayer);
      this.featureLayer.labelsVisible = true;

      PopupUtils.updatePopup(this.infoTemplate, this.ancestorMap, this.featureLayer);

      // Wire mouse events
      const esriEventToCustomEvent = new Map<string, string>([
        ['click', 'layerClick'],
        ['dbl-click', 'doubleClick'],
        ['mouse-over', 'layerMouseOver'],
        ['mouse-out', 'layerMouseOut'],
      ]);

      esriEventToCustomEvent.forEach((customEventName, esriEvent) => {
        const handle = this.featureLayer.on(esriEvent as any, (evt: any) => {
          import('@arcgis/core/geometry/support/webMercatorUtils').then(({ webMercatorToGeographic }) => {
            const coords = webMercatorToGeographic(evt.mapPoint) as any;
            const detail: LayerMouseEvent = {
              coordinates: { latitude: coords?.y, longitude: coords?.x },
              attributes: evt.graphic?.attributes,
            };
            this.dispatchEvent(new CustomEvent(customEventName, { detail, bubbles: true, composed: true }));
          });
        });
        this.eventHandles.push(handle);
      });

      this.createEditor();

      const convertedGeoJson = arcgisToGeoJSON((this.featureLayer as any).toJSON().featureSet);
      this.blockGeoJsonUpdate = true;
      this.geojson = convertedGeoJson as any;
      this.blockGeoJsonUpdate = false;
    }
  }

  private _getArcGisJson(geojson: string | FeatureCollection | object): any {
    const geojsonParseResult = JsonUtils.getJsonFor(geojson);
    if (geojsonParseResult.error) {
      console.error('Unable to parse geojson string', geojsonParseResult.error);
      return null;
    }
    const features = geojsonToArcGIS(geojsonParseResult.parsedJson);
    if (!Array.isArray(features)) {
      console.error('JSON value for geojson attribute could not be converted as geojson');
      return null;
    }
    let esriGeomType = 'esriGeometryPolygon';
    if (features.length !== 0) {
      esriGeomType = JsonUtils.getEsriGeomTypeFor(features[0].geometry);
    }
    return {
      jsonFS: {
        displayFieldName: 'LABEL',
        geometryType: esriGeomType,
        spatialReference: { wkid: 4326 },
        fields: [this.objectIdField],
        features,
      },
    };
  }

  private addToGeoJson(newGraphic: Graphic) {
    this.featureLayer.applyEdits({ addFeatures: [newGraphic] });
    const convertedGraphic = arcgisToGeoJSON(newGraphic.toJSON());
    const newGeoJson = JsonUtils.getJsonFor(this.geojson);
    (newGeoJson.parsedJson as any).features.push(convertedGraphic);
    this.geojson = newGeoJson.parsedJson;
    this.dispatchEvent(new CustomEvent('userDrawItemAdded', { detail: convertedGraphic, bubbles: true, composed: true }));
  }

  private removeFromGeoJson(graphicToRemove: Graphic) {
    this.featureLayer.applyEdits({ deleteFeatures: [graphicToRemove] });
    const convertedGraphic = arcgisToGeoJSON(graphicToRemove.toJSON());
    const idToRemove = (convertedGraphic as any).id;
    const newGeoJson = JsonUtils.getJsonFor(this.geojson);
    const newFeatures: any[] = newGeoJson.parsedJson.features;
    const indexToRemove = newFeatures.findIndex((f) => f.id === idToRemove);
    newFeatures.splice(indexToRemove, 1);
    this.geojson = newGeoJson.parsedJson;
    this.dispatchEvent(new CustomEvent('userEditItemRemoved', { detail: convertedGraphic, bubbles: true, composed: true }));
  }

  private updateGeoJsonWithChanges(graphicToUpdate: Graphic) {
    this.featureLayer.applyEdits({ updateFeatures: [graphicToUpdate] });
    const convertedGraphic = arcgisToGeoJSON(graphicToUpdate.toJSON());
    const idToUpdate = (convertedGraphic as any).id;
    const newGeoJson = JsonUtils.getJsonFor(this.geojson);
    for (let i = 0; i < newGeoJson.parsedJson.features.length; i++) {
      if (newGeoJson.parsedJson.features[i].id === idToUpdate) {
        newGeoJson.parsedJson.features[i] = convertedGraphic;
        break;
      }
    }
    this.geojson = newGeoJson.parsedJson;
    this.dispatchEvent(new CustomEvent('userEditItemUpdated', { detail: convertedGraphic, bubbles: true, composed: true }));
  }

  private getSymbolJson(geomType: string): object {
    return JsonUtils.getSymbolJson(
      geomType,
      this.DEFAULT_SYMBOL_COLOR,
      ArcGeoJsonLayer.DEFAULT_SYMBOL_MARKER_SIZE,
      ArcGeoJsonLayer.DEFAULT_SYMBOL_LINE_WIDTH,
      ArcGeoJsonLayer.DEFAULT_SYMBOL_LINE_WIDTH,
    );
  }
}


export enum DrawGeometryTypes {
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
  UP_ARROW = 'UP_ARROW',
}

export default class DrawEditUtils {
  static DrawGeometryTypes = DrawGeometryTypes;

  static validGeometryType(drawGeometryType: string, featureLayerGeometryType: string): boolean {
    const requiredEsriGeometryType = this.determineFeatureLayerGeometryType(drawGeometryType);
    if (requiredEsriGeometryType !== featureLayerGeometryType) {
      console.error(
        'The geojson geometry type needs to be a ' +
        this.convertEsriGeometryTypeToHumanReadable(requiredEsriGeometryType) +
        ' to draw the geometry ' + drawGeometryType + '.'
      );
      return false;
    }
    return true;
  }

  static determineFeatureLayerGeometryType(drawGeometryType: string): string {
    switch (drawGeometryType.toUpperCase()) {
      case DrawEditUtils.DrawGeometryTypes.FREEHAND_POLYLINE:
      case DrawEditUtils.DrawGeometryTypes.LINE:
      case DrawEditUtils.DrawGeometryTypes.POLYLINE:
        return 'esriGeometryPolyline';
      case DrawEditUtils.DrawGeometryTypes.MULTI_POINT:
        return 'esriGeometryMultipoint';
      case DrawEditUtils.DrawGeometryTypes.POINT:
        return 'esriGeometryPoint';
      case DrawEditUtils.DrawGeometryTypes.ARROW:
      case DrawEditUtils.DrawGeometryTypes.CIRCLE:
      case DrawEditUtils.DrawGeometryTypes.DOWN_ARROW:
      case DrawEditUtils.DrawGeometryTypes.ELLIPSE:
      case DrawEditUtils.DrawGeometryTypes.EXTENT:
      case DrawEditUtils.DrawGeometryTypes.FREEHAND_POLYGON:
      case DrawEditUtils.DrawGeometryTypes.LEFT_ARROW:
      case DrawEditUtils.DrawGeometryTypes.POLYGON:
      case DrawEditUtils.DrawGeometryTypes.RECTANGLE:
      case DrawEditUtils.DrawGeometryTypes.RIGHT_ARROW:
      case DrawEditUtils.DrawGeometryTypes.TRIANGLE:
      case DrawEditUtils.DrawGeometryTypes.UP_ARROW:
        return 'esriGeometryPolygon';
      default:
        console.error('The geometry type to be drawn is invalid: ' + drawGeometryType + '. Setting FeatureLayer geometry to polygon.');
        return 'esriGeometryPolygon';
    }
  }

  private static convertEsriGeometryTypeToHumanReadable(featureLayerGeometryType: string): string {
    switch (featureLayerGeometryType) {
      case 'esriGeometryPolyline': return 'Polyline';
      case 'esriGeometryMultipoint': return 'MultiPoint';
      case 'esriGeometryPoint': return 'Point';
      case 'esriGeometryPolygon': return 'Polygon';
      default: return 'Polygon';
    }
  }
}


import { Geometry } from '@arcgis/core/geometry/Geometry';
import Point from '@arcgis/core/geometry/Point';
import Polyline from '@arcgis/core/geometry/Polyline';
import Polygon from '@arcgis/core/geometry/Polygon';

import type {
  InfoTemplateDetails,
  LatLongPoint,
  RoutingCirc7,
  RoutingLatlon,
  RoutingLocation,
  RoutingSsid,
  UpMapExtent,
} from '../external-api';

export default class ValidationService {
  static constrainLongitude(desiredLongitude: number): number {
    if (desiredLongitude < -180) {
      console.warn('Longitude value of', desiredLongitude, 'is too small. Longitude value must be >= -180. Setting longitude to -180');
      return -180;
    }
    if (desiredLongitude > 180) {
      console.warn('Longitude value of', desiredLongitude, 'is too large. Longitude value must be <= 180. Setting longitude to 180');
      return 180;
    }
    return desiredLongitude;
  }

  private static isValidLongitude(possiblyValidLongitude: any): boolean {
    if (!Number.isFinite(possiblyValidLongitude)) return false;
    if (possiblyValidLongitude < -180) return false;
    if (possiblyValidLongitude > 180) return false;
    return true;
  }

  static validateLongitude(desiredLongitude: any, backupLongitude?: number): number {
    if (!Number.isFinite(desiredLongitude)) {
      console.warn('Longitude value of', desiredLongitude, 'is not a valid finite number. Staying on the current value.');
      return backupLongitude ? backupLongitude : 180;
    }
    return ValidationService.constrainLongitude(desiredLongitude);
  }

  static constrainLatitude(desiredLatitude: number): number {
    if (desiredLatitude < -85) {
      console.warn('Latitude value of', desiredLatitude, 'is too small. Latitude value must be >= -85. Setting latitude to -85');
      return -85;
    }
    if (desiredLatitude > 85) {
      console.warn('Latitude value of', desiredLatitude, 'is too large. Latitude value must be <= 85. Setting latitude to 85');
      return 85;
    }
    return desiredLatitude;
  }

  private static isValidLatitude(possiblyValidLatitude: any): boolean {
    if (!Number.isFinite(possiblyValidLatitude)) return false;
    if (possiblyValidLatitude < -85) return false;
    if (possiblyValidLatitude > 85) return false;
    return true;
  }

  static validateLatitude(desiredLatitude: any, backupLatitude?: number): number {
    if (!Number.isFinite(desiredLatitude)) {
      console.warn('Latitude value of', desiredLatitude, 'is not a valid finite number. Staying on the current value.');
      return backupLatitude ? backupLatitude : -85;
    }
    return ValidationService.constrainLatitude(desiredLatitude);
  }

  private static isUpMapExtent(possibleExtent: any): possibleExtent is UpMapExtent {
    return possibleExtent
      && typeof possibleExtent.leftLongitude === 'number'
      && typeof possibleExtent.rightLongitude === 'number'
      && typeof possibleExtent.bottomLatitude === 'number'
      && typeof possibleExtent.topLatitude === 'number';
  }

  static isValidUpMapExtent(extent: any): boolean {
    return ValidationService.isUpMapExtent(extent);
  }

  static isPoint(geometry: Geometry): geometry is Point {
    return geometry.type === 'point';
  }

  static isPolyline(geometry: Geometry): geometry is Polyline {
    return geometry.type === 'polyline';
  }

  static isPolygon(geometry: Geometry): geometry is Polygon {
    return geometry.type === 'polygon';
  }

  static isRoutingCirc7(loc: any): loc is RoutingCirc7 {
    return loc && loc.type === 'circ7' && typeof loc.circ7 === 'string';
  }

  static isRoutingSsid(loc: any): loc is RoutingSsid {
    return loc && loc.type === 'ssid' && typeof loc.ssid === 'number';
  }

  static isRoutingLatlon(loc: any): loc is RoutingLatlon {
    return loc
      && loc.type === 'latlon'
      && loc.location
      && typeof loc.location.lat === 'number'
      && typeof loc.location.lon === 'number'
      && (loc.distance === undefined || typeof loc.distance === 'number');
  }

  static isValidRoutingLatlon(loc: RoutingLatlon): boolean {
    return ValidationService.isValidLatitude(loc.location.lat)
      && ValidationService.isValidLongitude(loc.location.lon)
      && (loc.distance === undefined || loc.distance >= 0);
  }

  static isValidRoutingLocationArray(possibleRoute: any): possibleRoute is RoutingLocation[] {
    return Array.isArray(possibleRoute) && possibleRoute.length > 1
      && possibleRoute.every((possibleRoutingLocation) => {
        return ValidationService.isRoutingCirc7(possibleRoutingLocation)
          || ValidationService.isRoutingSsid(possibleRoutingLocation)
          || (ValidationService.isRoutingLatlon(possibleRoutingLocation)
            && ValidationService.isValidRoutingLatlon(possibleRoutingLocation));
      });
  }

  static isValidInfoTemplateDetails(possibleInfoTemplateDetails: any): possibleInfoTemplateDetails is InfoTemplateDetails {
    return possibleInfoTemplateDetails.listItem
      && possibleInfoTemplateDetails.details
      && (typeof possibleInfoTemplateDetails.listItem === 'string' || typeof possibleInfoTemplateDetails.listItem === 'function')
      && (typeof possibleInfoTemplateDetails.details === 'string' || typeof possibleInfoTemplateDetails.details === 'function');
  }

  private static isValidCoordinateArray(coordinates: any): boolean {
    if (Array.isArray(coordinates) && coordinates.length === 2) {
      return ValidationService.isValidLongitude(coordinates[0]) && ValidationService.isValidLatitude(coordinates[1]);
    }
    return false;
  }

  private static isValidCoordinateArrayWithM(coordinates: any): boolean {
    if (Array.isArray(coordinates) && coordinates.length === 3) {
      return ValidationService.isValidLongitude(coordinates[0])
        && ValidationService.isValidLatitude(coordinates[1])
        && typeof coordinates[2] === 'number';
    }
    return false;
  }

  private static isValidSinglePathArray(path: any): boolean {
    return Array.isArray(path)
      && path.length >= 2
      && path.every((c) => ValidationService.isValidCoordinateArray(c));
  }

  static isValidSingleOrMultiPathArray(paths: any): boolean {
    return ValidationService.isValidSinglePathArray(paths) ||
      (Array.isArray(paths) && paths.length >= 1
        && paths.every((p) => ValidationService.isValidSinglePathArray(p)));
  }

  static isValidSinglePathArrayWithM(path: any): boolean {
    return Array.isArray(path)
      && path.length >= 2
      && path.every((c) => ValidationService.isValidCoordinateArrayWithM(c));
  }

  static isValidLatLongPoint(point: any): boolean {
    return ValidationService.isLatLongPoint(point)
      && ValidationService.isValidLatitude(point.latitude)
      && ValidationService.isValidLongitude(point.longitude);
  }

  private static isLatLongPoint(possiblePoint: any): possiblePoint is LatLongPoint {
    return possiblePoint
      && typeof possiblePoint.latitude === 'number'
      && typeof possiblePoint.longitude === 'number';
  }
}


export interface MouseEvent {
  coordinates: {
    latitude: number;
    longitude: number;
  };
  attributes?: Record<string, any>;
}

export interface InfoTemplateDetails {
  listItem: string | ((graphic: any) => string);
  details: string | ((graphic: any) => string);
}

export interface LatLongPoint {
  latitude: number;
  longitude: number;
}

export interface RoutingLatlon {
  type: 'latlon';
  location: {
    lat: number;
    lon: number;
  };
  distance?: number;
}

export interface RoutingCirc7 {
  type: 'circ7';
  circ7: string;
}

export interface RoutingSsid {
  type: 'ssid';
  ssid: number;
}

export type RoutingLocation = RoutingLatlon | RoutingCirc7 | RoutingSsid;

export interface UpMapExtent {
  leftLongitude: number;
  rightLongitude: number;
  bottomLatitude: number;
  topLatitude: number;
}

export type ArcMapElement = HTMLElement & {
  getEsriMap(): Promise<__esri.MapView>;
  addLayer(layer: __esri.Layer, element?: HTMLElement): Promise<void>;
  removeLayer(layer: __esri.Layer): Promise<void>;
  hideZoomSlider(): Promise<void>;
  showZoomSlider(): Promise<void>;
  hideScaleBar(): Promise<void>;
  showScaleBar(): Promise<void>;
  enableInfoWindow(enable: boolean): void;
  updateComplete: Promise<boolean>;
};

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

  // ✅ Listen on MapView, not FeatureLayer
  const clickHandle = (esriMap as any).on('click', async (evt: any) => {
    if (!this.enableUserEdit) return;

    // Hit test to find if click is on our featureLayer
    const response = await (esriMap as any).hitTest(evt);
    const hit = response.results?.find(
      (r: any) => r.graphic?.layer === this.featureLayer
    );

    if (!hit) return;

    const graphic = hit.graphic;

    // ✅ Ctrl+Click to delete
    if (evt.native?.ctrlKey && this.enableUserEditRemove) {
      this.removingItem = true;
      this.removeFromGeoJson(graphic);
      this.graphicsEditor.cancel();
      this.removingItem = false;
      return;
    }

    // Activate editor on the clicked graphic
    this.activateGraphicsEditor(graphic);
  });

  this.eventHandles.push(clickHandle);
}
