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

interface IHandle { remove(): void; }

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
  listItem?: string | ((g: any) => string);
  details?: string | ((g: any) => string);
};

const INTERNAL_GEOJSON_TAG = Symbol('internal-geojson');

// ---------------------------------------------------------------------------
// GeoJSON <-> ArcGIS helpers
// ---------------------------------------------------------------------------

function geojsonToArcGISGeometry(geom: any): Geometry | null {
  if (!geom) return null;
  const sr = { wkid: 4326 };
  switch (geom.type) {
    case 'Point': return new Point({ x: geom.coordinates[0], y: geom.coordinates[1], spatialReference: sr });
    case 'MultiPoint': return new Multipoint({ points: geom.coordinates, spatialReference: sr });
    case 'LineString': return new Polyline({ paths: [geom.coordinates], spatialReference: sr });
    case 'MultiLineString': return new Polyline({ paths: geom.coordinates, spatialReference: sr });
    case 'Polygon': return new Polygon({ rings: geom.coordinates, spatialReference: sr });
    case 'MultiPolygon': return new Polygon({ rings: geom.coordinates.flat(1), spatialReference: sr });
    default: return null;
  }
}

function arcGISGeometryToGeoJson(geom: any): any {
  if (!geom) return null;
  switch (geom.type) {
    case 'point': return { type: 'Point', coordinates: [geom.x, geom.y] };
    case 'multipoint': return { type: 'MultiPoint', coordinates: geom.points };
    case 'polyline': return geom.paths?.length === 1
      ? { type: 'LineString', coordinates: geom.paths[0] }
      : { type: 'MultiLineString', coordinates: geom.paths };
    case 'polygon': return geom.rings?.length === 1
      ? { type: 'Polygon', coordinates: geom.rings }
      : { type: 'MultiPolygon', coordinates: [geom.rings] };
    default: return null;
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
// ---------------------------------------------------------------------------

function getDefaultSymbolForGeometry(geom: Geometry | null, color: number[]): any {
  if (!geom) return null;
  const [r, g, b, a = 255] = color;
  switch (geom.type) {
    case 'point':
    case 'multipoint':
      return new SimpleMarkerSymbol({
        style: 'circle', size: 10, color: [r, g, b, a],
        outline: new SimpleLineSymbol({ color: [r, g, b, 255], width: 1 }),
      });
    case 'polyline':
      return new SimpleLineSymbol({ color: [r, g, b, 255], width: 2, style: 'solid' });
    case 'polygon':
      return new SimpleFillSymbol({
        color: [r, g, b, 80], style: 'solid',
        outline: new SimpleLineSymbol({ color: [r, g, b, 255], width: 2 }),
      });
    default: return null;
  }
}

function parseRendererSymbol(renderer: any): any {
  if (!renderer) return null;
  try {
    const sym = renderer?.symbol ?? renderer;
    if (!sym?.type) return null;
    const t = (sym.type as string).toLowerCase();
    if (t === 'simple-marker' || t === 'esrisms') {
      const c = sym.color ?? [0, 0, 0, 255];
      return new SimpleMarkerSymbol({
        style: sym.style === 'esriSMSCircle' ? 'circle' : (sym.style ?? 'circle'),
        size: sym.size ?? 10, color: c,
        outline: sym.outline ? new SimpleLineSymbol({ color: sym.outline.color ?? c, width: sym.outline.width ?? 1 }) : undefined,
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
  } catch (e) { console.warn('[arc-geojson-layer] parseRendererSymbol failed:', e); }
  return null;
}

// Maps draw geometry type string to SketchViewModel tool type
function toSketchTool(drawGeometryType: string): string {
  switch (drawGeometryType.toLowerCase()) {
    case 'point': return 'point';
    case 'multipoint': return 'multipoint';
    case 'polyline':
    case 'line':
    case 'freehand_polyline': return 'polyline';
    case 'polygon':
    case 'freehand_polygon':
    case 'rectangle':
    case 'circle':
    case 'ellipse':
    case 'triangle':
    case 'arrow': return 'polygon';
    default: return drawGeometryType.toLowerCase();
  }
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

@customElement('arc-geojson-layer')
export class ArcGeoJsonLayer extends LitElement {

  private view!: MapView;
  private ancestorMap!: ArcMapElement;
  private featureLayer!: GraphicsLayer;
  private labelLayer!: GraphicsLayer;
  private sketchLayer!: GraphicsLayer;
  private graphicsEditor!: SketchViewModel;

  private eventHandles: IHandle[] = [];
  private editorHandles: IHandle[] = [];
  private _wireEventsRegistered = false;
  private _initComplete = false;
  private _pendingEnableUserEdit: boolean | undefined = undefined;

  // Ready promise — resolves when createLayer completes
  // Queues all updated() property changes until init is done
  private _readyResolve!: () => void;
  private _ready: Promise<void> = new Promise(resolve => {
    this._readyResolve = resolve;
  });

  private inDrawingMode = false;
  private removingItem = false;
  private graphicMoved = false;
  private blockGeoJsonUpdate = false;
  private _sourceCache: Graphic[] = [];
  private readonly DEFAULT_SYMBOL_COLOR: number[] = ArcGeoJsonLayer.getRandomColor();

  // ── Properties ───────────────────────────────────────────────────────────

  @property({ attribute: 'enable-user-edit', type: Boolean }) enableUserEdit = false;
  @property({ attribute: 'enable-user-edit-move', type: Boolean }) enableUserEditMove = true;
  @property({ attribute: 'enable-user-edit-vertices', type: Boolean }) enableUserEditVertices = true;
  @property({ attribute: 'enable-user-edit-scaling', type: Boolean }) enableUserEditScaling = true;
  @property({ attribute: 'enable-user-edit-rotating', type: Boolean }) enableUserEditRotating = true;
  @property({ attribute: 'enable-user-edit-uniform-scaling', type: Boolean }) enableUserEditUniformScaling = true;
  @property({ attribute: 'enable-user-edit-add-vertices', type: Boolean }) enableUserEditAddVertices = true;
  @property({ attribute: 'enable-user-edit-delete-vertices', type: Boolean }) enableUserEditDeleteVertices = true;
  @property() geojson: string | FeatureCollection = '';
  @property({ attribute: 'info-template' }) infoTemplate: string | InfoTemplateDetails = '';
  @property({ attribute: 'label-color' }) labelColor: string | number[] = this.DEFAULT_SYMBOL_COLOR;
  @property({ attribute: 'label-json' }) labelJson: string | object | object[] = '';
  @property({ attribute: 'label-size', type: Number }) labelSize = 12;
  @property({ attribute: 'layer-class' }) layerClass = '';
  @property({ reflect: true }) name = '';
  @property({ type: Object }) renderer: any = null;
  @property({ attribute: 'unique-id-property-name' }) uniqueIdPropertyName = 'id';

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  createRenderRoot() { return this; }
  render() { return null; }

  async connectedCallback(): Promise<void> {
    super.connectedCallback();

    // MutationObserver waits for element to be inside arc-map/up-map in DOM.
    // Needed because Angular @if recreates the element but connectedCallback
    // fires before the element is fully attached to the DOM tree.
    await this.waitForAncestorMap();

    if (!this.isConnected) return;

    console.log('[arc-geojson-layer] connectedCallback START');
    try {
      await this.resolveAncestorMapAndView();
      await this.createLayer(this.geojson);
      this._initComplete = true;
      this._readyResolve();
      console.log('[arc-geojson-layer] connectedCallback COMPLETE — featureLayer:', this.featureLayer?.id);
      if (this._pendingEnableUserEdit !== undefined) {
        await this.updateEditing(this._pendingEnableUserEdit);
        this._pendingEnableUserEdit = undefined;
      }
    } catch (e) {
      console.error('[arc-geojson-layer] connectedCallback error:', e);
    }
  }

  disconnectedCallback(): void {
    super.disconnectedCallback();
    // Reset ready promise for next connectedCallback cycle (Angular @if recreation)
    this._ready = new Promise(resolve => { this._readyResolve = resolve; });
    this._initComplete = false;
    this.cleanup();
  }

  updated(changedProps: PropertyValues): void {
    super.updated(changedProps);

    if (!this._initComplete) {
      if (changedProps.has('enableUserEdit')) {
        this._pendingEnableUserEdit = this.enableUserEdit;
      }
      return;
    }

    if (changedProps.has('geojson')) this.updateGeojson(this.geojson);
    if (changedProps.has('renderer') && !this.inDrawingMode) this.updateRenderer(this.renderer);
    if (changedProps.has('labelJson')) this.updateLabelJson(this.labelJson);
    if (changedProps.has('labelColor') || changedProps.has('labelSize')) this.refreshLabels();
    if (changedProps.has('layerClass')) this.updateLayerClass(this.layerClass);
    if (changedProps.has('infoTemplate')) this.updateInfoTemplate(this.infoTemplate);
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

  // ── waitForAncestorMap ────────────────────────────────────────────────────

  private waitForAncestorMap(): Promise<void> {
    return new Promise<void>(resolve => {
      const found = this.closest('arc-map') ?? this.closest('up-map');
      if (found) { resolve(); return; }
      const observer = new MutationObserver(() => {
        if (this.closest('arc-map') ?? this.closest('up-map')) {
          observer.disconnect();
          resolve();
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });
    });
  }

  // ── resolveAncestorMapAndView ─────────────────────────────────────────────

  private async resolveAncestorMapAndView(): Promise<void> {
    console.log('[arc-geojson-layer] resolveAncestorMapAndView');
    const mapEl = this.closest<ArcMapElement>('arc-map') ?? this.closest<ArcMapElement>('up-map');
    if (!mapEl) throw new Error('[arc-geojson-layer] Must be inside <arc-map>');
    this.ancestorMap = mapEl;
    this.view = await mapEl.getViewInstance();
    await this.view.when();
    console.log('[arc-geojson-layer] view ready');
  }

  // ── createLayer ───────────────────────────────────────────────────────────

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
      console.log('[arc-geojson-layer] layers added to map, featureLayer on map:',
        this.view.map.layers.includes(this.featureLayer));
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
      const g = new Graphic({ geometry: geom, attributes: attrs, symbol: this.getSymbolForGeometry(geom) });
      g.popupTemplate = this.buildPopupTemplateFromCurrent() ?? undefined;
      this.featureLayer.graphics.add(g);
    }
    this.rebuildSourceCache();
  }

  // ── createEditor ─────────────────────────────────────────────────────────

  private async createEditor(): Promise<void> {
    console.log('[arc-geojson-layer] createEditor START');

    // Destroy existing
    if (this.graphicsEditor) {
      try { this.graphicsEditor.cancel(); } catch { }
      try { this.graphicsEditor.destroy(); } catch { }
    }
    this.editorHandles.forEach(h => h.remove());
    this.editorHandles = [];

    if (!this.view) { console.warn('[arc-geojson-layer] createEditor: no view'); return; }

    // Remove old sketch layer
    if (this.sketchLayer) {
      try { this.view.map?.remove(this.sketchLayer); } catch { }
    }
    this.sketchLayer = new GraphicsLayer({
      listMode: 'hide',
      id: `${this.id || 'arc-geojson-layer'}-sketch-${Date.now()}`,
    });
    this.view.map?.add(this.sketchLayer);

    this.graphicsEditor = new SketchViewModel({
      view: this.view as any,
      layer: this.sketchLayer,
      updateOnGraphicClick: false,
    });

    const createHandle = this.graphicsEditor.on('create', (evt: any) => {
      console.log('[arc-geojson-layer] CREATE EVENT state:', evt.state, 'geomType:', evt.graphic?.geometry?.type);
      if (evt.state === 'complete') {
        this.onDrawComplete(evt.graphic);
      }
    });
    this.editorHandles.push(createHandle);

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

    console.log('[arc-geojson-layer] createEditor COMPLETE');
    this.bindViewEvents();
  }

  // ── bindViewEvents ────────────────────────────────────────────────────────

  private bindViewEvents(): void {
    if (this._wireEventsRegistered) return;
    this._wireEventsRegistered = true;

    this.eventHandles.forEach(h => h.remove());
    this.eventHandles = [];

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

  // ── startDrawing / cancelDrawing ──────────────────────────────────────────

  async startDrawing(drawGeometryType: string): Promise<void> {
    console.log('[arc-geojson-layer] startDrawing called with:', drawGeometryType);

    // KEY FIX: Recreate SketchViewModel fresh on every draw.
    // SketchViewModel gets stuck after completing a draw — destroy and
    // recreate guarantees clean state for every new draw operation.
    await this.createEditor();

    this.inDrawingMode = true;
    this.enableInfoPopupWindow(false);
    await this.ancestorMap?.hideZoomSlider?.();
    await this.ancestorMap?.hideScaleBar?.();

    const tool = toSketchTool(drawGeometryType);
    console.log('[arc-geojson-layer] creating sketch tool:', tool);

    // Brief pause ensures MapView is fully ready to accept sketch input.
    // Without this, SketchViewModel.create() can silently fail on second draw.
    await new Promise<void>(resolve => setTimeout(resolve, 50));

    try {
      this.graphicsEditor.create(tool as any);
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
    this.sketchLayer?.graphics?.removeAll();
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

    // Clone graphic before clearing sketch layer —
    // SketchViewModel owns the original reference on sketchLayer
    const cloned = graphic.clone();
    this.sketchLayer?.graphics?.removeAll();

    this.addToGeoJson(cloned);
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  private addToGeoJson(newGraphic: Graphic): void {
    if (!newGraphic.attributes) newGraphic.attributes = {};
    if (newGraphic.attributes[this.uniqueIdPropertyName] === undefined) {
      newGraphic.attributes[this.uniqueIdPropertyName] = Date.now();
    }
    if (newGraphic.attributes.OBJECTID === undefined) {
      newGraphic.attributes.OBJECTID = Date.now() + Math.random();
    }

    const sym = this.getSymbolForGraphic(newGraphic);
    newGraphic.symbol = sym;

    console.log('[arc-geojson-layer] addToGeojson called, geomType:', newGraphic.geometry?.type);
    console.log('[arc-geojson-layer] addToGeojson symbol:', (sym as any)?.type,
      'featureLayer on map:', this.view?.map?.layers?.includes(this.featureLayer));

    newGraphic.popupTemplate = this.enableUserEdit ? (null as any) : (this.buildPopupTemplateFromCurrent() ?? undefined);

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
        this.featureLayer?.graphics?.length, 'enableUserEdit:', this.enableUserEdit);
    }, 500);
    setTimeout(() => {
      console.log('[arc-geojson-layer] 2000ms check - graphics count:', this.featureLayer?.graphics?.length);
    }, 2000);
  }

  private removeFromGeoJson(graphicToRemove: Graphic): void {
    this.featureLayer.graphics.remove(graphicToRemove);
    this.labelLayer.graphics.removeAll();
    this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
    this.refreshLabels();
    this.rebuildSourceCache();
    this.emitLayerEvent('userEditItemRemoved', graphicToGeoJsonFeature(graphicToRemove, this.uniqueIdPropertyName));
  }

  private updateGeoJsonWithChanges(graphicToUpdate: Graphic): void {
    this.blockGeoJsonUpdate = true;
    this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
    this.blockGeoJsonUpdate = false;
    this.refreshLabels();
    this.rebuildSourceCache();
    this.emitLayerEvent('userEditItemUpdated', graphicToGeoJsonFeature(graphicToUpdate, this.uniqueIdPropertyName));
  }

  // ── updateGeojson ─────────────────────────────────────────────────────────

  private updateGeojson(value: string | FeatureCollection): void {
    if (this.isInternalGeojson(value)) {
      console.log('[arc-geojson-layer] updateGeojson SKIPPED: internal tag');
      return;
    }
    const parsed = this.parseGeojson(value);
    console.log('[arc-geojson-layer] updateGeojson called:', {
      inDrawingMode: this.inDrawingMode, removingItem: this.removingItem,
      enableUserEdit: this.enableUserEdit, incomingCount: parsed?.features?.length ?? 0,
    });
    if (this.inDrawingMode || this.removingItem || this.blockGeoJsonUpdate) return;
    if (this.enableUserEdit) return;
    if (!parsed) return;
    this.loadFeaturesFromGeojson(parsed);
    this.updateRenderer(this.renderer);
    this.refreshLabels();
  }

  // ── updateEditing ─────────────────────────────────────────────────────────

  async updateEditing(newUserEnableEdit: boolean): Promise<void> {
    console.log('[arc-geojson-layer] updateEditing - featureLayer:',
      this.featureLayer?.id ?? 'NULL', 'graphics:', this.featureLayer?.graphics?.length ?? 'NULL');

    if (!this.featureLayer) {
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
          console.log('[arc-geojson-layer] updateEditing symbol type:',
            sym?.constructor?.name, (sym as any)?.type);
          g.symbol = sym;
        }
        g.popupTemplate = null as unknown as never;
      });
      this.updateRenderer(this.renderer);
    } else {
      this.featureLayer.graphics.forEach((g: Graphic) => {
        if (g.geometry) g.symbol = this.getSymbolForGraphic(g);
        g.popupTemplate = this.buildPopupTemplateFromCurrent(g) ?? undefined;
      });
    }
    this.enableInfoPopupWindow(!newUserEnableEdit && !this.inDrawingMode);
  }

  // ── updateRenderer ────────────────────────────────────────────────────────

  updateRenderer(newRenderer: any): void {
    if (newRenderer !== undefined && newRenderer !== null) this.renderer = newRenderer;
    if (!this.featureLayer) return;
    this.featureLayer.graphics.forEach((g: Graphic) => {
      if (g.geometry) g.symbol = this.getSymbolForGeometry(g.geometry);
    });
  }

  // ── refreshLabels ─────────────────────────────────────────────────────────

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

  updateLabelJson(newLabelJson: string | object | object[]): void {
    this.labelJson = newLabelJson;
    this.refreshLabels();
  }

  updateInfoTemplate(newInfoTemplate: string | InfoTemplateDetails): void {
    if (!this.featureLayer) return;
    const tmpl = this.buildPopupTemplateFromCurrent();
    this.featureLayer.graphics.forEach((g: Graphic) => {
      g.popupTemplate = (this.enableUserEdit ? null : tmpl) ?? undefined;
    });
  }

  updateLayerClass(cls: string): void {
    if (!this.featureLayer) return;
    if (cls) this.featureLayer.listMode = 'hide-children';
  }

  // ── activateGraphicsEditor ────────────────────────────────────────────────

  private activateGraphicsEditor(graphic: Graphic): void {
    if (!this.graphicsEditor || !this.enableUserEdit) return;
    if (!this.enableUserEditMove && !this.enableUserEditVertices &&
        !this.enableUserEditScaling && !this.enableUserEditRotating) {
      console.error('[arc-geojson-layer] all editing features disabled');
      return;
    }
    this.featureLayer.graphics.remove(graphic);
    this.sketchLayer.graphics.add(graphic);
    const tool = this.enableUserEditVertices ? 'reshape' : 'transform';
    this.graphicsEditor.update([graphic], {
      tool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: !this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
    } as any);
  }

  private enableInfoPopupWindow(enable: boolean): void {
    this.ancestorMap?.enableInfoWindow?.(enable);
  }

  // ── Public methods ────────────────────────────────────────────────────────

  findFeatureByUniqueId(uniqueId: string | number): Graphic | null {
    return this.featureLayer?.graphics?.find(
      (g: Graphic) => g.attributes?.[this.uniqueIdPropertyName] === uniqueId
    ) ?? null;
  }

  getLayerId(): string { return this.featureLayer?.id ?? ''; }

  async zoomTo(featureId?: string | number, zoomLevel = 9): Promise<void> {
    if (!this.view) return;
    const graphics = featureId != null
      ? [this.findFeatureByUniqueId(featureId)].filter(Boolean) as Graphic[]
      : this.featureLayer?.graphics?.toArray() ?? [];
    if (!graphics.length) return;
    try { await (this.view as any).goTo(graphics); }
    catch (e) { console.warn('[arc-geojson-layer] zoomTo error:', e); }
  }

  openPopup(id: string | number): void {
    const g = this.findFeatureByUniqueId(id);
    if (!g || !this.view) return;
    (this.view as any).popup?.open({ features: [g], location: this.getPopupPoint(g.geometry) });
  }

  getGeoJson(): FeatureCollection { return this.toFeatureCollectionFromLayer(); }

  clearLayer(): void {
    this.featureLayer?.graphics?.removeAll();
    this.labelLayer?.graphics?.removeAll();
    this._sourceCache = [];
    this.geojson = this.tagAsInternal({ type: 'FeatureCollection', features: [] } as FeatureCollection);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  private getPopupPoint(geometry: Geometry | null | undefined): Point | null {
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
    return this.getSymbolForGeometry(g.geometry ?? null);
  }

  private getSymbolForGeometry(geom: Geometry | null | undefined): any {
    if (!geom) return null;
    if (this.renderer) {
      const sym = parseRendererSymbol(this.renderer);
      if (sym) return sym;
    }
    return getDefaultSymbolForGeometry(geom as Geometry, this.DEFAULT_SYMBOL_COLOR);
  }

  private buildPopupTemplateFromCurrent(g?: Graphic): PopupTemplate | null {
    if (!this.infoTemplate) return null;
    try {
      const tmpl = typeof this.infoTemplate === 'string' ? JSON.parse(this.infoTemplate) : this.infoTemplate;
      if (tmpl.title || tmpl.content) {
        return new PopupTemplate({ title: tmpl.title ?? (this.name || 'Feature Details'), content: tmpl.content });
      }
      if (tmpl.listItem || tmpl.details) {
        const listItem = typeof tmpl.listItem === 'string' ? tmpl.listItem.replace(/\$\{([^}]+)\}/g, '{$1}') : '';
        const details = typeof tmpl.details === 'string' ? tmpl.details.replace(/\$\{([^}]+)\}/g, '{$1}') : '';
        return new PopupTemplate({ title: this.name || 'Feature Details', content: `${listItem}<br/>${details}` });
      }
    } catch (e) { console.warn('[arc-geojson-layer] buildPopupTemplateFromCurrent failed:', e); }
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
    try { this.graphicsEditor?.destroy(); } catch { }
    if (this.view?.map) {
      if (this.featureLayer) this.view.map.remove(this.featureLayer);
      if (this.labelLayer) this.view.map.remove(this.labelLayer);
      if (this.sketchLayer) this.view.map.remove(this.sketchLayer);
    }
  }
}
