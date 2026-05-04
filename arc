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

import type {
  FeatureCollection,
  Feature,
  Geometry as GeoJsonGeometry
} from 'geojson';
import JsonUtils from '../common/json-utils';
import { InfoTemplateDetails } from '../external-api';

// ---------------------------------------------------------------------------
// Private Symbol used to tag FeatureCollection objects we set internally.
// The tag is non-enumerable so JSON.stringify / NgRx serialization strips it.
// When Angular echoes the value back through NgRx, the tag is gone.
// This lets us distinguish our own updates from external Angular updates
// with zero timeouts and zero race conditions.
// ---------------------------------------------------------------------------
const INTERNAL_GEOJSON_TAG = Symbol('arc-geojson-internal');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type LayerMouseEvent = {
  coordinates: { latitude: number; longitude: number };
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

  // -------------------------------------------------------------------------
  // componentOnReady — mirrors Stencil pattern so Angular can await it
  // -------------------------------------------------------------------------
  private _resolveReady!: () => void;
  private _readyPromise: Promise<void> = new Promise(
    resolve => (this._resolveReady = resolve)
  );
  async componentOnReady(): Promise<void> {
    return this._readyPromise;
  }

  // -------------------------------------------------------------------------
  // Private fields
  // -------------------------------------------------------------------------
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
  private graphicMoved = false;
  private hoveredGraphicUid: string | number | undefined;
  private eventHandles: Array<{ remove: () => void }> = [];

  // -------------------------------------------------------------------------
  // Properties
  // -------------------------------------------------------------------------

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

  @property({ type: Object })
  geojson: string | FeatureCollection = {
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
  layerClass = '';

  @property({ attribute: 'name' })
  name?: string = undefined;

  @property({ attribute: 'renderer' })
  renderer: any = undefined;

  @property({ attribute: 'unique-id-property-name' })
  uniqueIdPropertyName = 'id';

  // -------------------------------------------------------------------------
  // LitElement
  // -------------------------------------------------------------------------

  protected createRenderRoot(): this { return this; }
  render() { return null; }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  async connectedCallback(): Promise<void> {
    super.connectedCallback();
    try {
      await this.resolveAncestorMapAndView();
      await this.createLayer(this.geojson);
      this.bindViewEvents();
      this._resolveReady();
    } catch (e) {
      console.error('arc-geojson-layer connectedCallback error:', e);
      this._resolveReady();
    }
  }

  disconnectedCallback(): void {
    super.disconnectedCallback();
    for (const h of this.eventHandles) { if (h) h.remove(); }
    this.eventHandles = [];
    if (this.graphicsEditor) {
      try { this.graphicsEditor.destroy(); } catch { }
    }
    if (this.view?.map) {
      if (this.featureLayer) this.view.map.remove(this.featureLayer);
      if (this.labelLayer) this.view.map.remove(this.labelLayer);
    }
    this._readyPromise = new Promise(
      resolve => (this._resolveReady = resolve)
    );
  }

  protected updated(changedProps: Map<string, unknown>): void {
    if (changedProps.has('geojson')) {
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

  // -------------------------------------------------------------------------
  // Internal geojson tagging
  // -------------------------------------------------------------------------

  private tagAsInternal(fc: FeatureCollection): FeatureCollection {
    Object.defineProperty(fc, INTERNAL_GEOJSON_TAG, {
      value: true,
      enumerable: false,
      configurable: true,
      writable: false
    });
    return fc;
  }

  private isInternalGeojson(value: any): boolean {
    return (
      value != null &&
      typeof value === 'object' &&
      (value as any)[INTERNAL_GEOJSON_TAG] === true
    );
  }

  // -------------------------------------------------------------------------
  // Map / view resolution
  // -------------------------------------------------------------------------

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
      throw new Error('ancestor arc-map must expose getViewInstance()');
    }
    this.view = await this.ancestorMap.getViewInstance();
    if (!this.view) {
      throw new Error('ancestor arc-map getViewInstance() returned undefined');
    }
  }

  // -------------------------------------------------------------------------
  // Layer creation
  // -------------------------------------------------------------------------

  private async createLayer(
    geojson: string | FeatureCollection
  ): Promise<void> {
    const parsedGeojson = geojson ?? {
      type: 'FeatureCollection', features: []
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

    await this.createEditor();

    this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
  }

  // -------------------------------------------------------------------------
  // Editor
  // -------------------------------------------------------------------------

  private async createEditor(): Promise<void> {
    if (this.graphicsEditor) {
      try { this.graphicsEditor.destroy(); } catch { }
    }

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
      if (evt.state === 'complete' && evt.graphic) {
        this.inDrawingMode = false;
        this.addToGeojson(evt.graphic);
        this.enableInfoPopupWindow(false);
        return;
      }
      if (evt.state === 'cancel') {
        this.inDrawingMode = false;
        return;
      }
      if (evt.state === 'active' || evt.state === 'start') {
        this.inDrawingMode = true;
      }
    });

    this.graphicsEditor.on('update', (evt: any) => {
      if (evt.state === 'start') this.graphicMoved = false;
      if (evt.toolEventInfo?.type === 'move-start') this.graphicMoved = true;
      if (evt.toolEventInfo?.type === 'reshape-start') this.graphicMoved = true;
      if (evt.toolEventInfo?.type === 'scale-start') this.graphicMoved = true;
      if (evt.toolEventInfo?.type === 'rotate-start') this.graphicMoved = true;

      if (evt.state === 'complete' && evt.graphics?.length) {
        for (const g of evt.graphics) this.updateGeojsonWithChanges(g);
        this.enableInfoPopupWindow(true);
      }
      if (evt.state === 'cancel') {
        this.enableInfoPopupWindow(true);
      }
    });
  }

  // -------------------------------------------------------------------------
  // View events
  // -------------------------------------------------------------------------

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

      this.emitLayerEvent('layerClick', this.buildMouseEvent(graphic, evt.mapPoint));
      if (!this.inDrawingMode) {
        this.showGraphicPopup(graphic, evt.mapPoint);
      }
    });

    const dblClickHandle = this.view.on('double-click', async (evt: any) => {
      const hit = await this.view.hitTest(evt);
      const graphic = this.getLayerGraphicFromHit(hit);
      if (!graphic) return;

      this.emitLayerEvent('doubleClick', this.buildMouseEvent(graphic, evt.mapPoint));
      if (this.enableUserEdit) {
        await this.activateGraphicsEditor(graphic);
        return;
      }
      if (!this.inDrawingMode) {
        this.showGraphicPopup(graphic, evt.mapPoint);
      }
    });

    const pointerMoveHandle = this.view.on('pointer-move', async (evt: any) => {
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

      const uid = this.getGraphicUniqueId(graphic);
      if (this.hoveredGraphicUid !== uid) {
        if (this.hoveredGraphicUid !== undefined) {
          this.emitLayerEvent('layerMouseOut', this.buildMouseEvent(graphic, evt.mapPoint));
        }
        this.hoveredGraphicUid = uid;
        this.emitLayerEvent('layerMouseOver', this.buildMouseEvent(graphic, evt.mapPoint));
      }
    });

    this.eventHandles.push(clickHandle, dblClickHandle, pointerMoveHandle);
  }

  // -------------------------------------------------------------------------
  // Editing
  // -------------------------------------------------------------------------

  async updateEditing(_newUserEnableEdit: boolean): Promise<void> {
    if (this.graphicsEditor?.state === 'active') {
      try { this.graphicsEditor.cancel(); } catch { }
    }
    if (_newUserEnableEdit) {
      this.featureLayer.graphics.forEach((g: Graphic) => {
        g.popupTemplate = null as unknown as never;
      });
    } else {
      this.featureLayer.graphics.forEach((g: Graphic) => {
        g.popupTemplate = this.buildPopupTemplateFromCurrent(g);
      });
    }
    this.enableInfoPopupWindow(!_newUserEnableEdit && !this.inDrawingMode);
  }

  // -------------------------------------------------------------------------
  // updateGeojson — four guards, no timeouts
  // -------------------------------------------------------------------------

  async updateGeojson(
    newGeojson: string | FeatureCollection
  ): Promise<void> {
    // Guard 1: Skip our own internal update
    if (this.isInternalGeojson(newGeojson)) return;

    // Guard 2: Skip during drawing or removing
    if (this.inDrawingMode || this.removingItem) return;

    // Guard 3: Skip during editing
    if (this.enableUserEdit) return;

    if (!this.featureLayer) {
      await this.createLayer(newGeojson);
      return;
    }

    // Guard 4: Skip stale NgRx echo
    const parsed = ArcGeojsonLayer.parseJson<FeatureCollection>(newGeojson);
    if (!parsed.parsedJson) return;

    const incomingCount = parsed.parsedJson.features?.length ?? 0;
    const currentCount = this.featureLayer.graphics.length;

    if (currentCount > 0 && incomingCount < currentCount) return;

    // Process
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

  // -------------------------------------------------------------------------
  // Info template
  // -------------------------------------------------------------------------

  updateInfoTemplate(newInfoTemplate: any): void {
    this.infoTemplate = newInfoTemplate;
    if (!this.featureLayer) return;
    const parsed = ArcGeojsonLayer.parseJson<InfoTemplateDetails>(newInfoTemplate);
    if (!parsed.parsedJson) return;
    const info = parsed.parsedJson;
    this.featureLayer.graphics.forEach((g: Graphic) => {
      g.popupTemplate = this.buildPopupTemplate(info);
    });
  }

  // -------------------------------------------------------------------------
  // Label JSON
  // -------------------------------------------------------------------------

  updateLabelJson(arg: string | object | object[]): void {
    this.labelJson = arg;
    this.refreshLabels();
  }

  // -------------------------------------------------------------------------
  // Layer class
  // -------------------------------------------------------------------------

  updateLayerClass(cls: string): void {
    this.layerClass = cls;
    if (this.featureLayer) (this.featureLayer as any).className = cls;
    if (this.labelLayer) (this.labelLayer as any).className = `${cls}-labels`;
  }

  // -------------------------------------------------------------------------
  // Renderer
  // -------------------------------------------------------------------------

  updateRenderer(newRenderer: any): void {
    if (newRenderer !== undefined && newRenderer !== null) {
      this.renderer = newRenderer;
    }
    if (!this.featureLayer) return;
    this.featureLayer.graphics.forEach((g: Graphic) => {
      if (g.geometry) g.symbol = this.getSymbolForGraphic(g);
    });
  }

  // -------------------------------------------------------------------------
  // Drawing
  // -------------------------------------------------------------------------

  async startDrawing(drawGeometryType: string): Promise<void> {
    if (!this.featureLayer || !this.view) return;

    const existingType = this.determineExistingGeometryType();
    if (
      existingType &&
      !this.validGeometryType(drawGeometryType, existingType)
    ) return;

    // Recreate SketchViewModel fresh — avoids stale state
    await this.createEditor();

    this.inDrawingMode = true;
    this.enableInfoPopupWindow(false);

    const tool = this.toSketchCreateTool(drawGeometryType);

    // Brief pause ensures MapView is ready
    await new Promise<void>(resolve => setTimeout(resolve, 50));

    this.graphicsEditor.create(tool);
  }

  async cancelDrawing(): Promise<void> {
    this.inDrawingMode = false;
    if (this.graphicsEditor) {
      try { this.graphicsEditor.cancel(); } catch { }
    }
    this.enableInfoPopupWindow(true);
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  async findFeatureByUniqueId(
    uniqueId: string | number
  ): Promise<Graphic | undefined> {
    return this.featureLayer?.graphics.find(
      (g: Graphic) => g.attributes?.[this.uniqueIdPropertyName] === uniqueId
    );
  }

  async getLayerId(): Promise<string> {
    return this.featureLayer?.id ?? 'arc-geojson-layer';
  }

  async openPopup(id: string | number): Promise<void> {
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic?.geometry) return;
    this.showGraphicPopup(graphic, ArcGeojsonLayer.getPopupPoint(graphic.geometry));
  }

  async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic?.geometry) return;
    const { geometry } = graphic;
    if (ArcGeojsonLayer.isPoint(geometry)) {
      await this.view.goTo({ center: geometry, zoom: zoomLevel });
      return;
    }
    if (ArcGeojsonLayer.isPolyline(geometry) || ArcGeojsonLayer.isPolygon(geometry)) {
      const ext = geometry.extent;
      if (ext) await this.view.goTo(ext.expand(1.5));
    }
  }

  enableInfoPopupWindow(enable: boolean): void {
    const ok = enable && !this.enableUserEdit && !this.inDrawingMode;
    if (!ok && this.view?.popup?.visible) {
      this.view.popup.close();
    }
  }

  async activateGraphicsEditor(graphic: Graphic): Promise<void> {
    if (!this.enableUserEdit || !this.graphicsEditor) return;
    this.enableInfoPopupWindow(false);
    this.graphicsEditor.update([graphic], {
      tool: this.resolveUpdateTool(),
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      multipleSelectionEnabled: false,
      toggleToolOnClick: false
    } as any);
  }

  // -------------------------------------------------------------------------
  // Symbol resolution
  // -------------------------------------------------------------------------

  private getSymbolForGraphic(graphic: Graphic): any {
    if (!graphic.geometry) return null;

    if (this.renderer) {
      const parsed = ArcGeojsonLayer.parseJson(this.renderer);
      if (parsed.parsedJson) {
        const cfg = parsed.parsedJson;

        if (cfg.type === 'simple' && cfg.symbol) {
          return JsonUtils.normalizePlainSymbol(cfg.symbol);
        }

        if (Array.isArray(cfg.uniqueValueInfos) && cfg.uniqueValueInfos.length) {
          const geomType = graphic.geometry.type;
          const match = cfg.uniqueValueInfos.find((info: any) => {
            const val = (info.value ?? '').toString().toLowerCase();
            const sym = (info.symbol?.type ?? '')
              .toLowerCase().replace(/[\s-_]/g, '');
            if (geomType === 'polygon') {
              return val.endsWith('polygon') || sym === 'esrisfs' ||
                sym === 'simplefill' || sym === 'simplefillsymbol';
            }
            if (geomType === 'polyline') {
              return val.endsWith('polyline') || val.endsWith('line') ||
                sym === 'esrisls' || sym === 'simpleline' ||
                sym === 'simplelinesymbol';
            }
            return sym === 'esrisms' || sym === 'esrismscirlce' ||
              sym === 'esrismscircle' || sym === 'simplemarker' ||
              sym === 'simplemarkersymbol' ||
              (!val.endsWith('polygon') && !val.endsWith('polyline'));
          });
          if (match?.symbol) return JsonUtils.normalizePlainSymbol(match.symbol);
        }

        if (cfg.defaultSymbol) {
          return JsonUtils.normalizePlainSymbol(cfg.defaultSymbol);
        }
      }
    }

    return this.getDefaultSymbolForGeometry(graphic.geometry);
  }

  // -------------------------------------------------------------------------
  // GeoJSON helpers
  // -------------------------------------------------------------------------

  private getUpGISJson(
    geojson: string | object
  ): { graphics: Graphic[]; geometryType?: string } | null {
    const result = ArcGeojsonLayer.parseJson<FeatureCollection>(geojson);
    if (!result.parsedJson || result.parsedJson.type !== 'FeatureCollection')
      return null;

    const graphics: Graphic[] = [];
    let geometryType: string | undefined;

    result.parsedJson.features.forEach((feature: Feature, index: number) => {
      const g = this.geojsonFeatureToGraphic(feature, index);
      if (g?.geometry) {
        if (!geometryType) geometryType = g.geometry.type;
        graphics.push(g);
      }
    });

    return { graphics, geometryType };
  }

  private geojsonFeatureToGraphic(
    feature: Feature,
    index: number
  ): Graphic | null {
    const geometry = this.geojsonGeometryToArcGeometry(feature.geometry);
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
        const pts = geometry.coordinates as number[][];
        if (!pts.length) return null;
        return new Point({
          x: pts[0][0], y: pts[0][1],
          spatialReference: { wkid: 4326 }
        });
      }
      case 'LineString':
        return new Polyline({
          paths: [geometry.coordinates as number[][]],
          spatialReference: { wkid: 4326 }
        });
      case 'MultiLineString':
        return new Polyline({
          paths: geometry.coordinates as number[][][],
          spatialReference: { wkid: 4326 }
        });
      case 'Polygon':
        return new Polygon({
          rings: geometry.coordinates as number[][][],
          spatialReference: { wkid: 4326 }
        });
      case 'MultiPolygon': {
        const first = (geometry.coordinates as number[][][][])[0];
        if (!first) return null;
        return new Polygon({ rings: first, spatialReference: { wkid: 4326 } });
      }
      default:
        return null;
    }
  }

  private arcGeometryToGeoJsonGeometry(geometry: Geometry): GeoJsonGeometry {
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
        .filter((f): f is Feature => f !== null)
    };
  }

  // -------------------------------------------------------------------------
  // addToGeojson — Symbol tagging, no timeouts
  // -------------------------------------------------------------------------

  private addToGeojson(newGraphic: Graphic): void {
    if (!newGraphic.attributes) newGraphic.attributes = {};
    if (newGraphic.attributes[this.uniqueIdPropertyName] === undefined)
      newGraphic.attributes[this.uniqueIdPropertyName] = Date.now();
    if (newGraphic.attributes.OBJECTID === undefined)
      newGraphic.attributes.OBJECTID = Date.now();

    // Guaranteed symbol — default first, renderer on top
    newGraphic.symbol = this.getDefaultSymbolForGeometry(newGraphic.geometry);
    const rendererSym = this.getSymbolForGraphic(newGraphic);
    if (rendererSym) newGraphic.symbol = rendererSym;

    newGraphic.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic: newGraphic,
      infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName,
      fallbackTitle: this.name || 'Details'
    });

    if (!this.featureLayer.graphics.includes(newGraphic)) {
      this.featureLayer.add(newGraphic);
    }

    // Tag as internal — LitElement updated() skips it
    // NgRx strips the tag → Angular push becomes external
    this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());

    this.refreshLabels();
    this.emitLayerEvent(
      'userDrawItemAdded',
      this.graphicToGeoJsonFeature(newGraphic)
    );
  }

  private removeFromGeojson(graphicToRemove: Graphic): void {
    this.featureLayer.remove(graphicToRemove);
    this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
    this.refreshLabels();
    this.emitLayerEvent(
      'userEditItemRemoved',
      this.graphicToGeoJsonFeature(graphicToRemove)
    );
  }

  private updateGeojsonWithChanges(graphicToUpdate: Graphic): void {
    graphicToUpdate.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic: graphicToUpdate,
      infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName,
      fallbackTitle: this.name || 'Details'
    });
    this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
    this.refreshLabels();
    this.emitLayerEvent(
      'userEditItemUpdated',
      this.graphicToGeoJsonFeature(graphicToUpdate)
    );
  }

  // -------------------------------------------------------------------------
  // Popup
  // -------------------------------------------------------------------------

  private buildPopupTemplate(info: InfoTemplateDetails): PopupTemplate {
    return new PopupTemplate({
      title: (evt: any) => {
        const g = evt?.graphic ?? evt;
        return typeof info.listItem === 'function'
          ? info.listItem(g) : info.listItem;
      },
      content: (evt: any) => {
        const g = evt?.graphic ?? evt;
        return typeof info.details === 'function'
          ? info.details(g) : info.details;
      }
    });
  }

  private buildPopupTemplateFromCurrent(graphic: Graphic): PopupTemplate | null {
    const parsed = ArcGeojsonLayer.parseJson<InfoTemplateDetails>(this.infoTemplate);
    if (!parsed.parsedJson) return null;
    const info = parsed.parsedJson;
    const title = typeof info.listItem === 'function'
      ? info.listItem(graphic) : info.listItem;
    const content = typeof info.details === 'function'
      ? info.details(graphic) : info.details;
    return new PopupTemplate({ title, content });
  }

  private showGraphicPopup(graphic: Graphic, mapPoint?: Point): void {
    if (this.enableUserEdit || this.inDrawingMode) return;
    if (!graphic.geometry) return;
    const location = mapPoint ?? ArcGeojsonLayer.getPopupPoint(graphic.geometry);
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

  // -------------------------------------------------------------------------
  // Labels
  // -------------------------------------------------------------------------

  private refreshLabels(): void {
    if (!this.labelLayer) return;
    this.labelLayer.removeAll();

    const labelColor = JsonUtils.resolveLabelColor(this.labelColor);
    const labelSize = JsonUtils.resolveLabelSize(this.labelSize);

    this.featureLayer.graphics.forEach((graphic: Graphic) => {
      const label = graphic.attributes?.LABEL;
      if (!label || !graphic.geometry) return;
      const pt = ArcGeojsonLayer.getPopupPoint(graphic.geometry);
      this.labelLayer.add(new Graphic({
        geometry: pt,
        attributes: {
          __labelFor: graphic.attributes?.[this.uniqueIdPropertyName]
        },
        symbol: new TextSymbol({
          text: String(label),
          color: labelColor as any,
          haloColor: 'black',
          haloSize: 1,
          xoffset: 3,
          yoffset: 3,
          font: { size: labelSize, family: 'sans-serif', weight: 'bold' }
        })
      }));
    });
  }

  // -------------------------------------------------------------------------
  // Default symbol
  // -------------------------------------------------------------------------

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
          color: [0, 0, 0, 200], width: 1, style: 'solid'
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

  // -------------------------------------------------------------------------
  // Geometry type helpers
  // -------------------------------------------------------------------------

  private determineExistingGeometryType(): string | undefined {
    return this.featureLayer?.graphics?.getItemAt(0)?.geometry?.type;
  }

  private validGeometryType(drawType: string, layerType: string): boolean {
    return this.determineFeatureLayerGeometryType(drawType) === layerType;
  }

  private determineFeatureLayerGeometryType(drawType: string): string {
    switch ((drawType || '').toUpperCase()) {
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
    drawType: string
  ): 'point' | 'polyline' | 'polygon' | 'rectangle' | 'circle' {
    switch ((drawType || '').toUpperCase()) {
      case DrawGeometryTypes.POINT: return 'point';
      case DrawGeometryTypes.LINE:
      case DrawGeometryTypes.POLYLINE:
      case DrawGeometryTypes.FREEHAND_POLYLINE: return 'polyline';
      case DrawGeometryTypes.RECTANGLE:
      case DrawGeometryTypes.EXTENT: return 'rectangle';
      case DrawGeometryTypes.CIRCLE:
      case DrawGeometryTypes.ELLIPSE: return 'circle';
      default: return 'polygon';
    }
  }

  private resolveUpdateTool(): 'move' | 'reshape' | 'transform' {
    if (
      this.enableUserEditVertices ||
      this.enableUserEditAddVertices ||
      this.enableUserEditDeleteVertices
    ) return 'reshape';
    if (this.enableUserEditScaling || this.enableUserEditRotating)
      return 'transform';
    return 'move';
  }

  // -------------------------------------------------------------------------
  // Geographic projection
  // -------------------------------------------------------------------------

  private toGeographicPoint(point: Point): Point {
    return point.spatialReference?.isWGS84
      ? point
      : webMercatorUtils.webMercatorToGeographic(point) as Point;
  }

  private toGeographicPolyline(polyline: Polyline): Polyline {
    return polyline.spatialReference?.isWGS84
      ? polyline
      : webMercatorUtils.webMercatorToGeographic(polyline) as Polyline;
  }

  private toGeographicPolygon(polygon: Polygon): Polygon {
    return polygon.spatialReference?.isWGS84
      ? polygon
      : webMercatorUtils.webMercatorToGeographic(polygon) as Polygon;
  }

  // -------------------------------------------------------------------------
  // Mouse / event helpers
  // -------------------------------------------------------------------------

  private buildMouseEvent(
    graphic: Graphic,
    mapPoint: Point | null
  ): LayerMouseEvent {
    const geo = mapPoint
      ? webMercatorUtils.webMercatorToGeographic(mapPoint) as Point
      : null;
    return {
      coordinates: { latitude: geo?.y ?? 0, longitude: geo?.x ?? 0 },
      attributes: graphic?.attributes ?? {}
    };
  }

  private emitLayerEvent(name: string, detail: any): void {
    this.dispatchEvent(
      new CustomEvent(name, { detail, bubbles: true, composed: true })
    );
  }

  private getLayerGraphicFromHit(hit: any): Graphic | undefined {
    const r = hit?.results?.find(
      (r: any) => r.graphic?.layer === this.featureLayer
    );
    return r?.graphic as Graphic | undefined;
  }

  private getGraphicUniqueId(
    graphic: Graphic
  ): string | number | undefined {
    return (
      graphic.attributes?.[this.uniqueIdPropertyName] ??
      graphic.attributes?.OBJECTID
    );
  }

  // -------------------------------------------------------------------------
  // Static helpers
  // -------------------------------------------------------------------------

  static parseJson<T = any>(value: any): JsonParseResult<T> {
    if (value === null || value === undefined) {
      return { error: new Error('Value is null or undefined') };
    }
    if (typeof value === 'string') {
      try {
        return { parsedJson: JSON.parse(value) as T };
      } catch (e: any) {
        return { error: e instanceof Error ? e : new Error(String(e)) };
      }
    }
    return { parsedJson: value as T };
  }

  private static getPopupPoint(geometry: Geometry): Point {
    if (!geometry) return new Point({ x: 0, y: 0 });
    if (ArcGeojsonLayer.isPoint(geometry)) return geometry as Point;
    if (ArcGeojsonLayer.isPolyline(geometry)) {
      const pl = geometry as Polyline;
      const path = pl.paths?.[0] ?? [];
      const mid = Math.floor(path.length / 2);
      return new Point({
        x: path[mid]?.[0] ?? 0,
        y: path[mid]?.[1] ?? 0,
        spatialReference: pl.spatialReference
      });
    }
    if (ArcGeojsonLayer.isPolygon(geometry)) {
      return (geometry as Polygon).centroid ?? new Point({ x: 0, y: 0 });
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
