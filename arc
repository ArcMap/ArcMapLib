import { LitElement, PropertyValues } from 'lit';
import { customElement, property } from 'lit/decorators.js';
import type { FeatureCollection } from 'geojson';

import Graphic from '@arcgis/core/Graphic';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer';
import SketchViewModel from '@arcgis/core/widgets/Sketch/SketchViewModel';
import Point from '@arcgis/core/geometry/Point';
import Polyline from '@arcgis/core/geometry/Polyline';
import Polygon from '@arcgis/core/geometry/Polygon';
import Multipoint from '@arcgis/core/geometry/Multipoint';
import SimpleMarkerSymbol from '@arcgis/core/symbols/SimpleMarkerSymbol';
import SimpleLineSymbol from '@arcgis/core/symbols/SimpleLineSymbol';
import SimpleFillSymbol from '@arcgis/core/symbols/SimpleFillSymbol';
import TextSymbol from '@arcgis/core/symbols/TextSymbol';
import PopupTemplate from '@arcgis/core/PopupTemplate';
import * as webMercatorUtils from '@arcgis/core/geometry/support/webMercatorUtils';
import type MapView from '@arcgis/core/views/MapView';
import type Geometry from '@arcgis/core/geometry/Geometry';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface IHandle { remove(): void; }

// DIFFERENCE FROM STENCIL:
// Stencil used getEsriMap() which returned MapView directly from map.ts.
// In ArcGIS 5.0 LitElement arc-map: getViewInstance() returns MapView,
// getEsriMap() returns the Map object. We call getViewInstance() for the view.
type ArcMapElement = HTMLElement & {
  getViewInstance(): Promise<MapView>;
  getEsriMap(): Promise<any>;
  addLayer(layer: GraphicsLayer, element?: HTMLElement): Promise<void>;
  removeLayer(layer: GraphicsLayer): Promise<void>;
  hideZoomSlider(): Promise<void>;
  showZoomSlider(): Promise<void>;
  hideScaleBar(): Promise<void>;
  showScaleBar(): Promise<void>;
  enableInfoWindow(enable: boolean): void;
};

type InfoTemplateDetails = {
  title?: string;
  content?: any;
  // Legacy Stencil format — still supported
  listItem?: string | ((g: any) => string);
  details?: string | ((g: any) => string);
};

// DIFFERENCE FROM STENCIL:
// Stencil @Watch('geojson') only fired after componentDidLoad, so blockGeoJsonUpdate
// flag was enough to prevent loops. LitElement updated() fires on every render
// including before connectedCallback async work finishes.
// We use a Symbol tag on the FeatureCollection object itself — more robust than
// a boolean flag that can get out of sync across async boundaries.
const INTERNAL_GEOJSON_TAG = Symbol('internal-geojson');

// ---------------------------------------------------------------------------
// GeoJSON <-> ArcGIS geometry helpers
//
// DIFFERENCE FROM STENCIL:
// Stencil used arcgisToGeoJSON / geojsonToArcGIS from @terraformer/arcgis.
// ArcGIS 5.0 removed the terraformer dependency from the SDK.
// We implement the conversion inline using ArcGIS 5.0 geometry constructors.
// ---------------------------------------------------------------------------

function geojsonToArcGISGeometry(geom: any): Geometry | null {
  if (!geom) return null;
  const sr = { wkid: 4326 };
  switch (geom.type) {
    case 'Point':
      return new Point({ x: geom.coordinates[0], y: geom.coordinates[1], spatialReference: sr });
    case 'MultiPoint':
      return new Multipoint({ points: geom.coordinates, spatialReference: sr });
    case 'LineString':
      return new Polyline({ paths: [geom.coordinates], spatialReference: sr });
    case 'MultiLineString':
      return new Polyline({ paths: geom.coordinates, spatialReference: sr });
    case 'Polygon':
      return new Polygon({ rings: geom.coordinates, spatialReference: sr });
    case 'MultiPolygon':
      return new Polygon({ rings: geom.coordinates.flat(1), spatialReference: sr });
    default:
      return null;
  }
}

function arcGISGeometryToGeoJson(geom: any): any {
  if (!geom) return null;
  switch (geom.type) {
    case 'point':
      return { type: 'Point', coordinates: [geom.x, geom.y] };
    case 'multipoint':
      return { type: 'MultiPoint', coordinates: geom.points };
    case 'polyline':
      return geom.paths?.length === 1
        ? { type: 'LineString', coordinates: geom.paths[0] }
        : { type: 'MultiLineString', coordinates: geom.paths };
    case 'polygon':
      return geom.rings?.length === 1
        ? { type: 'Polygon', coordinates: geom.rings }
        : { type: 'MultiPolygon', coordinates: [geom.rings] };
    default:
      return null;
  }
}

function graphicToGeoJsonFeature(g: Graphic, uniqueIdProp: string): any {
  return {
    type: 'Feature',
    id: g.attributes?.[uniqueIdProp],
    geometry: arcGISGeometryToGeoJson(g.geometry),
    properties: { ...(g.attributes ?? {}) },
  };
}

// ---------------------------------------------------------------------------
// Symbol helpers
//
// DIFFERENCE FROM STENCIL:
// Stencil json-utils.ts used esri prefix strings (REST API format):
//   type: 'esriSMS', style: 'esriSMSCircle'   → point
//   type: 'esriSLS', style: 'esriSLSSolid'    → line
//   type: 'esriSFS', style: 'esriSFSSolid'    → polygon
// ArcGIS 5.0 uses autocast type strings (no esri prefix):
//   type: 'simple-marker', style: 'circle'    → point
//   type: 'simple-line',   style: 'solid'     → line
//   type: 'simple-fill',   style: 'solid'     → polygon
// ---------------------------------------------------------------------------

function getDefaultSymbolForGeometry(geom: Geometry | null, color: number[]): any {
  if (!geom) return null;
  const [r, g, b, a = 255] = color;
  switch (geom.type) {
    case 'point':
    case 'multipoint':
      return new SimpleMarkerSymbol({
        style: 'circle', size: 10,
        color: [r, g, b, a],
        outline: new SimpleLineSymbol({ color: [r, g, b, 255], width: 1 }),
      });
    case 'polyline':
      return new SimpleLineSymbol({ color: [r, g, b, 255], width: 2, style: 'solid' });
    case 'polygon':
      return new SimpleFillSymbol({
        color: [r, g, b, 80], style: 'solid',
        outline: new SimpleLineSymbol({ color: [r, g, b, 255], width: 2 }),
      });
    default:
      return null;
  }
}

function parseRendererSymbol(renderer: any): any {
  if (!renderer) return null;
  try {
    const sym = renderer?.symbol ?? renderer;
    if (!sym?.type) return null;
    const t = (sym.type as string).toLowerCase();
    if (t === 'simple-marker' || t === 'esrismi' || t === 'esrisms') {
      const c = sym.color ?? [0, 0, 0, 255];
      return new SimpleMarkerSymbol({
        style: sym.style === 'esriSMSCircle' ? 'circle' : (sym.style ?? 'circle'),
        size: sym.size ?? 10, color: c,
        outline: sym.outline
          ? new SimpleLineSymbol({ color: sym.outline.color ?? c, width: sym.outline.width ?? 1 })
          : undefined,
      });
    }
    if (t === 'simple-line' || t === 'esrisls') {
      return new SimpleLineSymbol({
        color: sym.color ?? [0, 0, 0, 255], width: sym.width ?? 2,
        style: sym.style === 'esriSLSSolid' ? 'solid' : (sym.style ?? 'solid'),
      });
    }
    if (t === 'simple-fill' || t === 'esrisfs') {
      const c = sym.color ?? [0, 0, 0, 80];
      return new SimpleFillSymbol({
        color: c, style: sym.style === 'esriSFSSolid' ? 'solid' : (sym.style ?? 'solid'),
        outline: sym.outline
          ? new SimpleLineSymbol({ color: sym.outline.color ?? [0, 0, 0, 255], width: sym.outline.width ?? 2 })
          : new SimpleLineSymbol({ color: [0, 0, 0, 255], width: 2 }),
      });
    }
  } catch (e) {
    console.warn('[arc-geojson-layer] parseRendererSymbol failed:', e);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

@customElement('arc-geojson-layer')
export class ArcGeoJsonLayer extends LitElement {

  // ── Private fields ───────────────────────────────────────────────────────

  private view!: MapView;
  private ancestorMap!: ArcMapElement;

  // DIFFERENCE FROM STENCIL:
  // Stencil used FeatureLayer for display and graphics storage.
  // ArcGIS 5.0 GraphicsLayer is used instead — full control over graphic
  // lifecycle, symbol assignment, no server round-trips.
  // featureLayer name kept identical to Stencil for Angular template compatibility.
  private featureLayer!: GraphicsLayer;

  // DIFFERENCE FROM STENCIL:
  // Stencil used FeatureLayer.labelingInfo for labels.
  // ArcGIS 5.0 GraphicsLayer does NOT support labelingInfo.
  // Separate GraphicsLayer with TextSymbol graphics used for labels.
  private labelLayer!: GraphicsLayer;

  // Hidden layer owned by SketchViewModel for its internal draw graphics
  private sketchLayer!: GraphicsLayer;

  // DIFFERENCE FROM STENCIL:
  // Stencil had: esriDraw = new Draw(view) + graphicsEditor = new Edit(view)
  // ArcGIS 5.0: single SketchViewModel handles both draw and edit.
  // graphicsEditor name kept same as Stencil.
  private graphicsEditor!: SketchViewModel;

  private eventHandles: IHandle[] = [];
  private editorHandles: IHandle[] = [];
  private _wireEventsRegistered = false;
  private _editorCreated = false;

  // DIFFERENCE FROM STENCIL:
  // Stencil @Watch only fired after componentDidLoad — init was guaranteed done.
  // LitElement updated() fires before connectedCallback async work finishes.
  // _initComplete prevents updated() from acting before featureLayer exists.
  private _initComplete = false;
  private _pendingEnableUserEdit: boolean | undefined = undefined;

  // Same internal flags as Stencil
  private inDrawingMode = false;
  private removingItem = false;
  private graphicMoved = false;
  private blockGeoJsonUpdate = false;

  // DIFFERENCE FROM STENCIL:
  // Stencil click used view.hitTest() — caused ~20s delays with GraphicsLayer.
  // _sourceCache + findNearest() = synchronous, instant lookup. No hitTest.
  private _sourceCache: Graphic[] = [];

  private readonly DEFAULT_SYMBOL_COLOR: number[] = ArcGeoJsonLayer.getRandomColor();

  // ── @property (exact same names as Stencil @Prop) ────────────────────────

  @property({ attribute: 'enable-user-edit', type: Boolean })
  enableUserEdit = false;

  @property({ attribute: 'enable-user-edit-move', type: Boolean })
  enableUserEditMove = true;

  @property({ attribute: 'enable-user-edit-vertices', type: Boolean })
  enableUserEditVertices = true;

  @property({ attribute: 'enable-user-edit-scaling', type: Boolean })
  enableUserEditScaling = true;

  @property({ attribute: 'enable-user-edit-rotating', type: Boolean })
  enableUserEditRotating = true;

  @property({ attribute: 'enable-user-edit-uniform-scaling', type: Boolean })
  enableUserEditUniformScaling = true;

  @property({ attribute: 'enable-user-edit-add-vertices', type: Boolean })
  enableUserEditAddVertices = true;

  @property({ attribute: 'enable-user-edit-delete-vertices', type: Boolean })
  enableUserEditDeleteVertices = true;

  @property()
  geojson: string | FeatureCollection = '';

  @property({ attribute: 'info-template' })
  infoTemplate: string | InfoTemplateDetails = '';

  @property({ attribute: 'label-color' })
  labelColor: string | number[] = this.DEFAULT_SYMBOL_COLOR;

  // NOTE: @property decorator required — Stencil tracked all @Prop automatically.
  // Without this decorator LitElement never fires updated() for labelJson changes.
  @property({ attribute: 'label-json' })
  labelJson: string | object | object[] = '';

  @property({ attribute: 'label-size', type: Number })
  labelSize = 12;

  @property({ attribute: 'layer-class' })
  layerClass = '';

  @property({ reflect: true })
  name = '';

  @property({ type: Object })
  renderer: any = null;

  @property({ attribute: 'unique-id-property-name' })
  uniqueIdPropertyName = 'id';

  // ── LitElement lifecycle ─────────────────────────────────────────────────

  // DIFFERENCE FROM STENCIL:
  // Returning `this` disables shadow DOM — required so ArcGIS layers attach
  // to document DOM, not shadow DOM.
  createRenderRoot() { return this; }
  render() { return null; }

  async connectedCallback(): Promise<void> {
    super.connectedCallback();
    console.log('[arc-geojson-layer] connectedCallback START');
    try {
      await this.resolveAncestorMapAndView();
      await this.createLayer(this.geojson);
      this._initComplete = true;
      console.log('[arc-geojson-layer] connectedCallback COMPLETE — featureLayer:', this.featureLayer?.id);
      if (this._pendingEnableUserEdit !== undefined) {
        console.log('[arc-geojson-layer] applying pending enableUserEdit:', this._pendingEnableUserEdit);
        await this.updateEditing(this._pendingEnableUserEdit);
        this._pendingEnableUserEdit = undefined;
      }
    } catch (e) {
      console.error('[arc-geojson-layer] connectedCallback error:', e);
    }
  }

  disconnectedCallback(): void {
    super.disconnectedCallback();
    console.log('[arc-geojson-layer] disconnectedCallback');
    this.cleanup();
  }

  // DIFFERENCE FROM STENCIL:
  // Stencil @Watch per property fired independently always after load.
  // LitElement updated() fires for all changed props at once, before init completes.
  updated(changedProps: PropertyValues): void {
    super.updated(changedProps);

    if (!this._initComplete) {
      if (changedProps.has('enableUserEdit')) {
        console.log('[arc-geojson-layer] updated: init not complete, storing pending enableUserEdit:', this.enableUserEdit);
        this._pendingEnableUserEdit = this.enableUserEdit;
      }
      return;
    }

    if (changedProps.has('geojson')) {
      this.updateGeojson(this.geojson);
    }
    if (changedProps.has('renderer')) {
      if (!this.inDrawingMode) this.updateRenderer(this.renderer);
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
    if (changedProps.has('infoTemplate')) {
      this.updateInfoTemplate(this.infoTemplate);
    }
    if (changedProps.has('enableUserEdit') ||
        changedProps.has('enableUserEditMove') ||
        changedProps.has('enableUserEditVertices') ||
        changedProps.has('enableUserEditScaling') ||
        changedProps.has('enableUserEditRotating') ||
        changedProps.has('enableUserEditUniformScaling') ||
        changedProps.has('enableUserEditAddVertices') ||
        changedProps.has('enableUserEditDeleteVertices')) {
      console.log('[arc-geojson-layer] updated: calling updateEditing, enableUserEdit:', this.enableUserEdit);
      this.updateEditing(this.enableUserEdit);
    }
  }

  // ── Initialization ───────────────────────────────────────────────────────

  private async resolveAncestorMapAndView(): Promise<void> {
    console.log('[arc-geojson-layer] resolveAncestorMapAndView');
    const mapEl = this.closest<ArcMapElement>('arc-map') ?? this.closest<ArcMapElement>('up-map');
    if (!mapEl) throw new Error('[arc-geojson-layer] Must be a child of <arc-map>');
    this.ancestorMap = mapEl;
    this.view = await mapEl.getViewInstance();
    await this.view.when();
    console.log('[arc-geojson-layer] view ready');
  }

  private async createLayer(geojson: string | FeatureCollection): Promise<void> {
    console.log('[arc-geojson-layer] createLayer START');
    const parsed = this.parseGeojson(geojson) ?? ({ type: 'FeatureCollection', features: [] } as FeatureCollection);

    this.featureLayer = new GraphicsLayer({
      id: `${this.id || 'arc-geojson-layer'}-graphics`,
      title: this.name || this.id || 'Arc GeoJSON Layer',
    });
    this.labelLayer = new GraphicsLayer({
      id: `${this.id || 'arc-geojson-layer'}-labels`,
      title: `${this.name || this.id || 'Arc GeoJSON Layer'} Labels`,
      listMode: 'hide',
    });

    if (this.view?.map) {
      this.view.map.add(this.featureLayer);
      this.view.map.add(this.labelLayer);
      console.log('[arc-geojson-layer] layers added to map');
    }

    this.loadFeaturesFromGeojson(parsed);
    this.updateRenderer(this.renderer);
    this.refreshLabels();
    this.updateInfoTemplate(this.infoTemplate);
    this.updateLayerClass(this.layerClass);

    await this.createEditor();

    this.rebuildSourceCache();
    this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
    console.log('[arc-geojson-layer] createLayer COMPLETE, graphics:', this.featureLayer.graphics.length);
  }

  private loadFeaturesFromGeojson(fc: FeatureCollection): void {
    this.featureLayer.graphics.removeAll();
    for (const feature of fc.features) {
      const geom = geojsonToArcGISGeometry(feature.geometry as any);
      if (!geom) continue;
      const attrs = {
        ...(feature.properties ?? {}),
        [this.uniqueIdPropertyName]: (feature as any).id ?? feature.properties?.[this.uniqueIdPropertyName] ?? Date.now(),
        OBJECTID: Date.now() + Math.random(),
      };
      const sym = this.getSymbolForGeometry(geom);
      const g = new Graphic({ geometry: geom, attributes: attrs, symbol: sym });
      g.popupTemplate = this.buildPopupTemplateFromCurrent() ?? undefined;
      this.featureLayer.graphics.add(g);
      console.log('[arc-geojson-layer] loaded feature geomType:', geom.type);
    }
    this.rebuildSourceCache();
  }

  // ── createEditor — replaces Stencil createDrawing() + createEditor() ────

  private async createEditor(): Promise<void> {
    console.log('[arc-geojson-layer] createEditor START');
    if (this.graphicsEditor) {
      try { this.graphicsEditor.destroy(); } catch { }
    }
    this.editorHandles.forEach(h => h.remove());
    this.editorHandles = [];
    this._editorCreated = false;

    if (!this.view) {
      console.warn('[arc-geojson-layer] createEditor: no view');
      return;
    }

    if (this.sketchLayer) {
      try { this.view.map?.remove(this.sketchLayer); } catch { }
    }
    this.sketchLayer = new GraphicsLayer({
      listMode: 'hide',
      id: `${this.id || 'arc-geojson-layer'}-sketch`,
    });
    this.view.map?.add(this.sketchLayer);

    // DIFFERENCE FROM STENCIL:
    // Stencil: new Draw(view) for drawing + new Edit(view, featureLayer) for editing.
    // ArcGIS 5.0: SketchViewModel handles both. updateOnGraphicClick=false means
    // we control edit activation manually — same as Stencil's explicit activate() call.
    this.graphicsEditor = new SketchViewModel({
      view: this.view as any,
      layer: this.sketchLayer,
      updateOnGraphicClick: false,
    });

    // DIFFERENCE FROM STENCIL:
    // Stencil Draw widget emitted 'draw-complete' event.
    // ArcGIS 5.0 SketchViewModel emits 'create' event with state='complete'.
    const createHandle = this.graphicsEditor.on('create', (evt: any) => {
      console.log('[arc-geojson-layer] CREATE EVENT state:', evt.state, 'geomType:', evt.graphic?.geometry?.type);
      if (evt.state === 'complete') {
        this.onDrawComplete(evt.graphic);
      }
    });
    this.editorHandles.push(createHandle);

    // DIFFERENCE FROM STENCIL:
    // Stencil Edit widget had separate events: rotate-stop, scale-stop, vertex-add,
    // vertex-delete, vertex-move-stop, graphic-first-move, graphic-move-stop.
    // ArcGIS 5.0 SketchViewModel: single 'update' event, toolEventInfo.type identifies sub-event.
    const updateHandle = this.graphicsEditor.on('update', (evt: any) => {
      if (!evt.toolEventInfo) return;
      const type: string = evt.toolEventInfo.type;
      if (type === 'move-start') this.graphicMoved = false;
      if (type === 'move') this.graphicMoved = true;
      if (['rotate-stop', 'scale-stop', 'vertex-add', 'vertex-remove', 'reshape-stop'].includes(type)) {
        evt.graphics?.forEach((g: Graphic) => this.updateGeoJsonWithChanges(g));
      }
      if (type === 'move-stop' && this.graphicMoved) {
        this.graphicMoved = false;
        evt.graphics?.forEach((g: Graphic) => this.updateGeoJsonWithChanges(g));
      }
    });
    this.editorHandles.push(updateHandle);

    this._editorCreated = true;
    console.log('[arc-geojson-layer] createEditor COMPLETE');
    this.bindViewEvents();
  }

  private bindViewEvents(): void {
    if (this._wireEventsRegistered) return;
    this._wireEventsRegistered = true;
    console.log('[arc-geojson-layer] bindViewEvents');
    this.eventHandles.forEach(h => h.remove());
    this.eventHandles = [];

    // DIFFERENCE FROM STENCIL:
    // Stencil used view.hitTest() for clicks — caused ~20s delays with GraphicsLayer.
    // Replaced with findNearest() against _sourceCache for instant synchronous lookup.
    const clickHandle = (this.view as any).on('click', (evt: any) => {
      if (!this.enableUserEdit || this.inDrawingMode) return;
      evt.stopPropagation?.();
      const nearest = this.findNearest(evt.mapPoint);
      if (!nearest) return;
      if (evt.native?.ctrlKey && !evt.native?.shiftKey) {
        this.removingItem = true;
        this.removeFromGeoJson(nearest);
        this.graphicsEditor?.cancel();
        this.removingItem = false;
        return;
      }
      this.activateGraphicsEditor(nearest);
    });
    this.eventHandles.push(clickHandle);

    const pointerMoveHandle = (this.view as any).on('pointer-move', (evt: any) => {
      if (this.inDrawingMode) return;
      const mp = this.view.toMap({ x: evt.x, y: evt.y });
      if (!mp) return;
      const nearest = this.findNearest(mp);
      if (nearest) {
        (this.view.container as HTMLElement).style.cursor = 'pointer';
        const geo = webMercatorUtils.webMercatorToGeographic(mp) as Point;
        this.emitLayerEvent('layerMouseOver', this.buildMouseEvent(nearest, geo as Point));
      } else {
        (this.view.container as HTMLElement).style.cursor = '';
        this.emitLayerEvent('layerMouseOut', null);
      }
    });
    this.eventHandles.push(pointerMoveHandle);
  }

  // ── startDrawing / cancelDrawing ─────────────────────────────────────────

  async startDrawing(drawGeometryType: string): Promise<void> {
    console.log('[arc-geojson-layer] startDrawing called with:', drawGeometryType);
    if (!this.graphicsEditor) {
      console.warn('[arc-geojson-layer] startDrawing: graphicsEditor not ready');
      return;
    }
    this.inDrawingMode = true;
    this.enableInfoPopupWindow(false);
    await this.ancestorMap?.hideZoomSlider?.();
    await this.ancestorMap?.hideScaleBar?.();

    // DIFFERENCE FROM STENCIL:
    // Stencil validated against DrawEditUtils.DrawGeometryTypes enum then called esriDraw.create(type).
    // ArcGIS 5.0: graphicsEditor.create(type) directly on SketchViewModel.
    // 'circle' completes as polygon geometry type.
    const toolType = drawGeometryType.toLowerCase() as any;
    console.log('[arc-geojson-layer] creating sketch tool:', toolType);
    try {
      this.graphicsEditor.create(toolType);
      console.log('[arc-geojson-layer] graphicsEditor state after create:', this.graphicsEditor.state);
    } catch (e) {
      console.error('[arc-geojson-layer] startDrawing error:', e);
      this.inDrawingMode = false;
    }
  }

  async cancelDrawing(): Promise<void> {
    console.log('[arc-geojson-layer] cancelDrawing');
    this.inDrawingMode = false;
    try { this.graphicsEditor?.cancel(); } catch { }
    this.enableInfoPopupWindow(!this.enableUserEdit);
    await this.ancestorMap?.showZoomSlider?.();
    await this.ancestorMap?.showScaleBar?.();
  }

  private onDrawComplete(graphic: Graphic): void {
    if (!graphic?.geometry) {
      console.warn('[arc-geojson-layer] onDrawComplete: no geometry');
      this.inDrawingMode = false;
      return;
    }
    console.log('[arc-geojson-layer] DRAWING COMPLETE - graphics before add:', this.featureLayer.graphics.length);
    this.ancestorMap?.showZoomSlider?.();
    this.ancestorMap?.showScaleBar?.();
    this.inDrawingMode = false;
    this.addToGeoJson(graphic);
  }

  // ── addToGeoJson / removeFromGeoJson / updateGeoJsonWithChanges ──────────

  private addToGeoJson(newGraphic: Graphic): void {
    if (!newGraphic.attributes) newGraphic.attributes = {};
    if (newGraphic.attributes[this.uniqueIdPropertyName] === undefined) {
      newGraphic.attributes[this.uniqueIdPropertyName] = Date.now();
    }
    if (newGraphic.attributes.OBJECTID === undefined) {
      newGraphic.attributes.OBJECTID = Date.now() + Math.random();
    }

    // CRITICAL: GraphicsLayer requires explicit symbol per graphic.
    // DIFFERENCE FROM STENCIL: FeatureLayer applied symbols via renderer automatically.
    const sym = this.getSymbolForGraphic(newGraphic);
    newGraphic.symbol = sym;

    console.log('[arc-geojson-layer] addToGeojson called, geomType:', newGraphic.geometry?.type);
    console.log('[arc-geojson-layer] addToGeojson final symbol:',
      sym?.constructor?.name, (sym as any)?.type, (sym as any)?.color, (sym as any)?.style,
      'visible:', this.featureLayer?.visible);
    console.log('[arc-geojson-layer] featureLayer visible:', this.featureLayer?.visible,
      'listMode:', this.featureLayer?.listMode);

    newGraphic.popupTemplate = this.enableUserEdit ? (null as any) : (this.buildPopupTemplateFromCurrent() ?? undefined);

    // DIFFERENCE FROM STENCIL:
    // Stencil: featureLayer.applyEdits({ addFeatures: [graphic] })
    // ArcGIS 5.0 GraphicsLayer: featureLayer.graphics.add(graphic)
    if (!this.featureLayer.graphics.includes(newGraphic)) {
      this.featureLayer.graphics.add(newGraphic);
    }

    console.log('[arc-geojson-layer] DRAWING COMPLETE - graphics after add:', this.featureLayer.graphics.length);
    this.rebuildSourceCache();

    const newCollection = this.toFeatureCollectionFromLayer();
    console.log('[arc-geojson-layer] addToGeojson: setting tagged geojson, features:', newCollection.features.length);
    this.geojson = this.tagAsInternal(newCollection);

    this.refreshLabels();
    this.emitLayerEvent('userDrawItemAdded', graphicToGeoJsonFeature(newGraphic, this.uniqueIdPropertyName));

    setTimeout(() => {
      console.log('[arc-geojson-layer] 500ms check - graphics count:',
        this.featureLayer?.graphics?.length,
        'enableUserEdit:', this.enableUserEdit, 'inDrawingMode:', this.inDrawingMode);
    }, 500);
    setTimeout(() => {
      console.log('[arc-geojson-layer] 2000ms check - graphics count:', this.featureLayer?.graphics?.length);
    }, 2000);
  }

  private removeFromGeoJson(graphicToRemove: Graphic): void {
    // DIFFERENCE FROM STENCIL:
    // Stencil: featureLayer.applyEdits({ deleteFeatures: [graphic] })
    // ArcGIS 5.0 GraphicsLayer: featureLayer.graphics.remove(graphic)
    this.featureLayer.graphics.remove(graphicToRemove);
    this.labelLayer.graphics.removeAll();
    this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
    this.refreshLabels();
    this.rebuildSourceCache();
    this.emitLayerEvent('userEditItemRemoved', graphicToGeoJsonFeature(graphicToRemove, this.uniqueIdPropertyName));
  }

  private updateGeoJsonWithChanges(graphicToUpdate: Graphic): void {
    // DIFFERENCE FROM STENCIL:
    // Stencil: featureLayer.applyEdits({ updateFeatures: [graphic] })
    // ArcGIS 5.0: SketchViewModel mutates geometry in-place. Just sync geojson.
    this.blockGeoJsonUpdate = true;
    this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
    this.blockGeoJsonUpdate = false;
    this.refreshLabels();
    this.rebuildSourceCache();
    this.emitLayerEvent('userEditItemUpdated', graphicToGeoJsonFeature(graphicToUpdate, this.uniqueIdPropertyName));
  }

  // ── updateGeojson ────────────────────────────────────────────────────────

  private updateGeojson(value: string | FeatureCollection): void {
    if (this.isInternalGeojson(value)) {
      console.log('[arc-geojson-layer] updateGeojson SKIPPED: internal tag');
      return;
    }
    const parsed = this.parseGeojson(value);
    const currentCount = this.featureLayer?.graphics?.length ?? 0;
    const incomingCount = parsed?.features?.length ?? 0;
    console.log('[arc-geojson-layer] updateGeojson called:', {
      isInternal: false, inDrawingMode: this.inDrawingMode,
      removingItem: this.removingItem, enableUserEdit: this.enableUserEdit,
      incomingCount, currentCount,
    });
    if (this.inDrawingMode || this.removingItem || this.blockGeoJsonUpdate) return;
    if (this.enableUserEdit) return;
    if (!parsed) return;
    this.loadFeaturesFromGeojson(parsed);
    this.updateRenderer(this.renderer);
    this.refreshLabels();
  }

  // ── updateEditing ────────────────────────────────────────────────────────

  async updateEditing(newUserEnableEdit: boolean): Promise<void> {
    console.log('[arc-geojson-layer] updateEditing TOP - featureLayer:',
      this.featureLayer?.id ?? 'NULL',
      'graphics:', this.featureLayer?.graphics?.length ?? 'NULL');

    if (!this.featureLayer) {
      console.warn('[arc-geojson-layer] updateEditing: featureLayer not ready, storing pending');
      this._pendingEnableUserEdit = newUserEnableEdit;
      return;
    }

    if (this.graphicsEditor?.state === 'active') {
      try { this.graphicsEditor.cancel(); } catch { }
    }

    if (newUserEnableEdit) {
      this.featureLayer.graphics.forEach((g: Graphic) => {
        console.log('[arc-geojson-layer] updateEditing graphic:',
          g?.geometry?.type ?? 'NO GEOMETRY', 'symbol:', g?.symbol?.type ?? 'NO SYMBOL');
        if (g.geometry) {
          const sym = this.getSymbolForGraphic(g);
          console.log('[arc-geojson-layer] updateEditing symbol:', JSON.stringify((sym as any)?.type));
          console.log('[arc-geojson-layer] updateEditing symbol type:',
            sym?.constructor?.name, (sym as any)?.type, (sym as any)?.color, (sym as any)?.style);
          g.symbol = sym;
        }
        g.popupTemplate = null as unknown as never;
      });
      // Force re-apply renderer to guarantee all graphics have symbols
      this.updateRenderer(this.renderer);
    } else {
      this.featureLayer.graphics.forEach((g: Graphic) => {
        if (g.geometry) g.symbol = this.getSymbolForGraphic(g);
        g.popupTemplate = this.buildPopupTemplateFromCurrent(g) ?? undefined;
      });
    }

    this.enableInfoPopupWindow(!newUserEnableEdit && !this.inDrawingMode);
  }

  // ── updateRenderer ───────────────────────────────────────────────────────

  updateRenderer(newRenderer: any): void {
    if (newRenderer !== undefined && newRenderer !== null) {
      this.renderer = newRenderer;
    }
    if (!this.featureLayer) return;
    console.log('[arc-geojson-layer] updateRenderer called, graphics count:',
      this.featureLayer.graphics.length, 'renderer:', this.renderer?.type ?? 'none');
    // DIFFERENCE FROM STENCIL:
    // Stencil: JsonUtils.updateRenderer() set FeatureLayer.renderer.
    // ArcGIS 5.0 GraphicsLayer: set symbol on each Graphic individually.
    this.featureLayer.graphics.forEach((g: Graphic) => {
      if (g.geometry) {
        const sym = this.getSymbolForGeometry(g.geometry);
        console.log('[arc-geojson-layer] updateRenderer symbol:', sym?.type, 'geomType:', g.geometry.type);
        g.symbol = sym;
      }
    });
  }

  // ── refreshLabels ────────────────────────────────────────────────────────

  refreshLabels(): void {
    if (!this.labelLayer || !this.featureLayer) return;
    this.labelLayer.graphics.removeAll();
    if (!this.labelJson) return;
    let labelFields: any[] = [];
    try {
      const lj = typeof this.labelJson === 'string' ? JSON.parse(this.labelJson) : this.labelJson;
      labelFields = Array.isArray(lj) ? lj : [lj];
    } catch { return; }
    const color = this.resolveLabelColor();
    const size = this.labelSize ?? 12;
    this.featureLayer.graphics.forEach((g: Graphic) => {
      if (!g.geometry || !g.attributes) return;
      const labelParts: string[] = [];
      for (const field of labelFields) {
        const fieldName = field.fieldName ?? field.field ?? field;
        if (typeof fieldName === 'string' && g.attributes[fieldName] !== undefined) {
          labelParts.push(String(g.attributes[fieldName]));
        }
      }
      if (!labelParts.length) return;
      const labelPoint = this.getPopupPoint(g.geometry);
      if (!labelPoint) return;
      this.labelLayer.graphics.add(new Graphic({
        geometry: labelPoint,
        symbol: new TextSymbol({
          text: labelParts.join(' '), color,
          font: { size, family: 'sans-serif' },
          haloColor: [255, 255, 255, 200], haloSize: 1,
        }),
      }));
    });
  }

  // ── updateLabelJson ──────────────────────────────────────────────────────

  updateLabelJson(newLabelJson: string | object | object[]): void {
    this.labelJson = newLabelJson;
    this.refreshLabels();
  }

  // ── updateInfoTemplate ───────────────────────────────────────────────────

  updateInfoTemplate(newInfoTemplate: string | InfoTemplateDetails): void {
    if (!this.featureLayer) return;
    const tmpl = this.buildPopupTemplateFromCurrent();
    // DIFFERENCE FROM STENCIL:
    // Stencil: PopupUtils.updatePopup() → featureLayer.setInfoTemplate().
    // ArcGIS 5.0: setInfoTemplate() does not exist. PopupTemplate set per Graphic.
    this.featureLayer.graphics.forEach((g: Graphic) => {
      g.popupTemplate = (this.enableUserEdit ? null : tmpl) ?? undefined;
    });
  }

  // ── updateLayerClass ─────────────────────────────────────────────────────

  updateLayerClass(cls: string): void {
    if (!this.featureLayer) return;
    if (cls) this.featureLayer.listMode = 'hide-children';
  }

  // ── activateGraphicsEditor ───────────────────────────────────────────────

  private activateGraphicsEditor(graphic: Graphic): void {
    if (!this.graphicsEditor || !this.enableUserEdit) return;
    if (!this.enableUserEditMove && !this.enableUserEditVertices &&
        !this.enableUserEditScaling && !this.enableUserEditRotating) {
      console.error('[arc-geojson-layer] Cannot edit: all editing features are turned off.');
      return;
    }
    this.featureLayer.graphics.remove(graphic);
    this.sketchLayer.graphics.add(graphic);
    // DIFFERENCE FROM STENCIL:
    // Stencil: built bitmask (MOVE|SCALE|ROTATE), called graphicsEditor.activate(bitmask, [graphic]).
    // ArcGIS 5.0: graphicsEditor.update([graphic], options) — no bitmask.
    const tool = this.enableUserEditVertices ? 'reshape' : 'transform';
    this.graphicsEditor.update([graphic], {
      tool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: !this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
    } as any);
  }

  // ── enableInfoPopupWindow ────────────────────────────────────────────────

  private enableInfoPopupWindow(enable: boolean): void {
    this.ancestorMap?.enableInfoWindow?.(enable);
  }

  // ── Public methods (same names as Stencil @Method) ───────────────────────

  findFeatureByUniqueId(uniqueId: string | number): Graphic | null {
    return this.featureLayer?.graphics?.find(
      (g: Graphic) => g.attributes?.[this.uniqueIdPropertyName] === uniqueId
    ) ?? null;
  }

  getLayerId(): string {
    return this.featureLayer?.id ?? '';
  }

  async zoomTo(featureId?: string | number, zoomLevel = 9): Promise<void> {
    if (!this.view) return;
    const graphics = featureId != null
      ? [this.findFeatureByUniqueId(featureId)].filter(Boolean) as Graphic[]
      : this.featureLayer?.graphics?.toArray() ?? [];
    if (!graphics.length) return;
    // DIFFERENCE FROM STENCIL:
    // Stencil: centerAndZoom() for points, setExtent() for polygons/polylines.
    // ArcGIS 5.0: view.goTo() works for all geometry types.
    try { await (this.view as any).goTo(graphics); }
    catch (e) { console.warn('[arc-geojson-layer] zoomTo error:', e); }
  }

  openPopup(id: string | number): void {
    const g = this.findFeatureByUniqueId(id);
    if (!g || !this.view) return;
    const location = this.getPopupPoint(g.geometry);
    (this.view as any).popup?.open({ features: [g], location });
  }

  getGeoJson(): FeatureCollection {
    return this.toFeatureCollectionFromLayer();
  }

  clearLayer(): void {
    this.featureLayer?.graphics?.removeAll();
    this.labelLayer?.graphics?.removeAll();
    this._sourceCache = [];
    this.geojson = this.tagAsInternal({ type: 'FeatureCollection', features: [] } as FeatureCollection);
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  private getPopupPoint(geometry: Geometry | null): Point | null {
    if (!geometry) return null;
    if (geometry.type === 'point') return geometry as Point;
    if (geometry.type === 'polygon') return (geometry as any).centroid ?? null;
    if (geometry.type === 'polyline') {
      const paths = (geometry as any).paths;
      if (paths?.[0]?.length) {
        const mid = paths[0][Math.floor(paths[0].length / 2)];
        return new Point({ x: mid[0], y: mid[1], spatialReference: geometry.spatialReference });
      }
    }
    return null;
  }

  private getSymbolForGraphic(g: Graphic): any {
    return this.getSymbolForGeometry(g.geometry);
  }

  private getSymbolForGeometry(geom: Geometry | null): any {
    if (!geom) return null;
    if (this.renderer) {
      const sym = parseRendererSymbol(this.renderer);
      if (sym) return sym;
    }
    return getDefaultSymbolForGeometry(geom, this.DEFAULT_SYMBOL_COLOR);
  }

  private buildPopupTemplateFromCurrent(g?: Graphic): PopupTemplate | null {
    if (!this.infoTemplate) return null;
    try {
      const tmpl = typeof this.infoTemplate === 'string' ? JSON.parse(this.infoTemplate) : this.infoTemplate;
      if (tmpl.title || tmpl.content) {
        return new PopupTemplate({ title: tmpl.title ?? (this.name || 'Feature Details'), content: tmpl.content });
      }
      // Legacy Stencil format { listItem, details }
      // DIFFERENCE FROM STENCIL:
      // Stencil used ${fieldName}. ArcGIS 5.0 PopupTemplate uses {fieldName}.
      if (tmpl.listItem || tmpl.details) {
        const listItem = typeof tmpl.listItem === 'string'
          ? tmpl.listItem.replace(/\$\{([^}]+)\}/g, '{$1}') : '';
        const details = typeof tmpl.details === 'string'
          ? tmpl.details.replace(/\$\{([^}]+)\}/g, '{$1}') : '';
        return new PopupTemplate({ title: this.name || 'Feature Details', content: `${listItem}<br/>${details}` });
      }
    } catch (e) {
      console.warn('[arc-geojson-layer] buildPopupTemplateFromCurrent failed:', e);
    }
    return null;
  }

  private resolveLabelColor(): any {
    try {
      if (Array.isArray(this.labelColor)) return this.labelColor;
      if (typeof this.labelColor === 'string') {
        const parsed = JSON.parse(this.labelColor);
        if (Array.isArray(parsed)) return parsed;
      }
    } catch { }
    return this.DEFAULT_SYMBOL_COLOR;
  }

  private toFeatureCollectionFromLayer(): FeatureCollection {
    const features = (this.featureLayer?.graphics?.toArray() ?? [])
      .map((g: Graphic) => graphicToGeoJsonFeature(g, this.uniqueIdPropertyName))
      .filter((f: any) => f.geometry != null);
    return { type: 'FeatureCollection', features } as FeatureCollection;
  }

  private parseGeojson(value: string | FeatureCollection | null | undefined): FeatureCollection | null {
    if (!value) return null;
    if (typeof value === 'object') {
      if (this.isInternalGeojson(value)) return null;
      return value as FeatureCollection;
    }
    try { return JSON.parse(value) as FeatureCollection; } catch { return null; }
  }

  private tagAsInternal(fc: FeatureCollection): FeatureCollection {
    Object.defineProperty(fc, INTERNAL_GEOJSON_TAG,
      { value: true, enumerable: false, configurable: true, writable: false });
    return fc;
  }

  private isInternalGeojson(value: any): boolean {
    return value != null && typeof value === 'object' && (value as any)[INTERNAL_GEOJSON_TAG] === true;
  }

  private rebuildSourceCache(): void {
    this._sourceCache = this.featureLayer?.graphics?.toArray() ?? [];
  }

  private findNearest(mapPoint: any): Graphic | null {
    if (!mapPoint || !this._sourceCache.length) return null;
    const THRESHOLD_PX = 15;
    let nearest: Graphic | null = null;
    let minDist = Infinity;
    for (const g of this._sourceCache) {
      if (!g.geometry) continue;
      const labelPoint = this.getPopupPoint(g.geometry);
      if (!labelPoint) continue;
      const screenPt = this.view.toScreen(labelPoint as any);
      const clickPt = this.view.toScreen(mapPoint);
      if (!screenPt || !clickPt) continue;
      const dist = Math.hypot(screenPt.x - clickPt.x, screenPt.y - clickPt.y);
      if (dist < minDist && dist < THRESHOLD_PX) { minDist = dist; nearest = g; }
    }
    return nearest;
  }

  private emitLayerEvent(eventName: string, detail: any): void {
    this.dispatchEvent(new CustomEvent(eventName, { detail, bubbles: true, composed: true }));
  }

  private buildMouseEvent(g: Graphic, geoPoint: Point): any {
    return {
      coordinates: { latitude: geoPoint.latitude, longitude: geoPoint.longitude },
      attributes: g.attributes ?? {},
    };
  }

  static getRandomColor(): number[] {
    return [
      Math.floor(Math.random() * 200),
      Math.floor(Math.random() * 200),
      Math.floor(Math.random() * 200),
      180,
    ];
  }

  private cleanup(): void {
    this.eventHandles.forEach(h => h.remove());
    this.eventHandles = [];
    this.editorHandles.forEach(h => h.remove());
    this.editorHandles = [];
    this._wireEventsRegistered = false;
    this._editorCreated = false;
    this._initComplete = false;
    try { this.graphicsEditor?.destroy(); } catch { }
    if (this.view?.map) {
      if (this.featureLayer) this.view.map.remove(this.featureLayer);
      if (this.labelLayer) this.view.map.remove(this.labelLayer);
      if (this.sketchLayer) this.view.map.remove(this.sketchLayer);
    }
  }
}
