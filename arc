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
import * as webMercatorUtils from '@arcgis/core/geometry/support/webMercatorUtils';
import SimpleMarkerSymbol from '@arcgis/core/symbols/SimpleMarkerSymbol';
import SimpleLineSymbol from '@arcgis/core/symbols/SimpleLineSymbol';
import SimpleFillSymbol from '@arcgis/core/symbols/SimpleFillSymbol';
import TextSymbol from '@arcgis/core/symbols/TextSymbol';
import type Geometry from '@arcgis/core/geometry/Geometry';

import type { FeatureCollection, Feature, Geometry as GeoJsonGeometry } from 'geojson';
import JsonUtils from '../common/json-utils';
import { InfoTemplateDetails } from '../external-api';

type LayerMouseEvent = {
  coordinates: { latitude: number; longitude: number; };
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

@customElement('arc-geojson-layer')
export class ArcGeojsonLayer extends LitElement {

  private graphicsEditor!: SketchViewModel;
  private ancestorMap!: any;
  private readonly DEFAULT_SYMBOL_COLOR: number[] = ArcGeojsonLayer.getRandomColor();
  private static readonly DEFAULT_SYMBOL_LINE_WIDTH = 1;
  private static readonly DEFAULT_SYMBOL_MARKER_SIZE = 10;

  private featureLayer!: GraphicsLayer;
  private labelLayer!: GraphicsLayer;
  private sketchLayer!: GraphicsLayer;
  private view!: MapView;

  private inDrawingMode = false;
  private removingItem = false;
  private blockGeoJsonUpdate = false;
  private graphicMoved = false;
  private _isStartingDraw = false;
  private _initComplete = false;
  private _pendingEnableUserEdit: boolean | undefined = undefined;
  private _pendingGeojson: string | FeatureCollection | undefined = undefined;
  private hoveredGraphicUid: string | number | undefined;
  private eventHandles: Array<{ remove: () => void }> = [];
  private editorHandles: Array<{ remove: () => void }> = [];

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
  geojson: string | FeatureCollection = { type: 'FeatureCollection', features: [] };

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

  protected createRenderRoot(): this { return this; }
  render() { return null; }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  async connectedCallback(): Promise<void> {
    super.connectedCallback();
    await this.waitForAncestorMap();
    if (!this.isConnected) return;
    try {
      await this.resolveAncestorMapAndView();
      await this.createLayer(this.geojson);
      this.bindViewEvents();
      this._initComplete = true;
      console.log('[arc-geojson-layer] READY, name:', this.name);

      if (this._pendingGeojson !== undefined) {
        await this.updateGeojson(this._pendingGeojson);
        this._pendingGeojson = undefined;
      }
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
    for (const h of this.eventHandles) { try { h.remove(); } catch { } }
    this.eventHandles = [];
    for (const h of this.editorHandles) { try { h.remove(); } catch { } }
    this.editorHandles = [];
    if (this.graphicsEditor) {
      try { this.graphicsEditor.cancel(); } catch { }
      try { this.graphicsEditor.destroy(); } catch { }
    }
    if (this.view?.map) {
      if (this.featureLayer) {
        this.featureLayer.graphics.removeAll();
        this.view.map.remove(this.featureLayer);
      }
      if (this.labelLayer) {
        this.labelLayer.graphics.removeAll();
        this.view.map.remove(this.labelLayer);
      }
      if (this.sketchLayer) {
        this.sketchLayer.graphics.removeAll();
        this.view.map.remove(this.sketchLayer);
      }
    }
    this._initComplete = false;
    this._pendingGeojson = undefined;
    this._pendingEnableUserEdit = undefined;
  }

  protected updated(changedProps: Map<string, unknown>): void {
    if (!this._initComplete) {
      if (changedProps.has('geojson') && !this.blockGeoJsonUpdate) {
        this._pendingGeojson = this.geojson;
      }
      if (changedProps.has('enableUserEdit')) {
        this._pendingEnableUserEdit = this.enableUserEdit;
      }
      return;
    }
    if (changedProps.has('geojson') && !this.blockGeoJsonUpdate) {
      this.updateGeojson(this.geojson);
    }
    if (changedProps.has('infoTemplate')) this.updateInfoTemplate(this.infoTemplate);
    if (changedProps.has('renderer')) this.updateRenderer(this.renderer);
    if (changedProps.has('labelJson')) this.updateLabelJson(this.labelJson);
    if (changedProps.has('labelColor') || changedProps.has('labelSize')) this.refreshLabels();
    if (changedProps.has('layerClass')) this.updateLayerClass(this.layerClass);
    if (changedProps.has('enableUserEdit') ||
        changedProps.has('enableUserEditMove') ||
        changedProps.has('enableUserEditVertices') ||
        changedProps.has('enableUserEditScaling') ||
        changedProps.has('enableUserEditRotating') ||
        changedProps.has('enableUserEditUniformScaling') ||
        changedProps.has('enableUserEditAddVertices') ||
        changedProps.has('enableUserEditDeleteVertices')) {
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
          observer.disconnect(); resolve();
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });
    });
  }

  // ── resolveAncestorMapAndView ─────────────────────────────────────────────

  private async resolveAncestorMapAndView(): Promise<void> {
    this.ancestorMap = this.closest('arc-map') as any;
    if (!this.ancestorMap) throw new Error('arc-geojson-layer must be inside <arc-map>');
    if (typeof this.ancestorMap.componentOnReady === 'function') {
      await this.ancestorMap.componentOnReady();
    }
    if (typeof this.ancestorMap.getViewInstance !== 'function') {
      throw new Error('arc-map must expose getViewInstance()');
    }
    this.view = await this.ancestorMap.getViewInstance();
    if (!this.view) throw new Error('getViewInstance() returned undefined');
    await this.view.when();
  }

  // ── createLayer ───────────────────────────────────────────────────────────

  private async createLayer(geojson: string | FeatureCollection): Promise<void> {
    console.log('[arc-geojson-layer] createLayer, name:', this.name);

    const gId = `${this.id || 'arc-geojson-layer'}-graphics`;
    const lId = `${this.id || 'arc-geojson-layer'}-labels`;
    const sId = `${this.id || 'arc-geojson-layer'}-sketch`;

    // Remove stale layers — prevents ghost graphics on @if recreation
    if (this.view?.map) {
      [gId, lId, sId].forEach(id => {
        const s = this.view.map.findLayerById(id);
        if (s) { (s as GraphicsLayer).graphics?.removeAll(); this.view.map.remove(s); }
      });
    }

    this.featureLayer = new GraphicsLayer({ id: gId, title: this.name || this.id || 'Arc GeoJSON Layer' });
    this.labelLayer = new GraphicsLayer({ id: lId, listMode: 'hide' });
    this.sketchLayer = new GraphicsLayer({ id: sId, listMode: 'hide' });

    if (this.view?.map) {
      this.view.map.add(this.featureLayer);
      this.view.map.add(this.labelLayer);
      this.view.map.add(this.sketchLayer);
    }

    const fsInfo = this.getUpGISJson(geojson ?? { type: 'FeatureCollection', features: [] });
    if (fsInfo) for (const g of fsInfo.graphics) this.featureLayer.add(g);

    this.updateRenderer(this.renderer);
    this.refreshLabels();
    this.updateInfoTemplate(this.infoTemplate);
    this.updateLayerClass(this.layerClass);
    await this.createEditor();

    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();
    this.blockGeoJsonUpdate = false;

    console.log('[arc-geojson-layer] createLayer DONE, name:', this.name,
      'graphics:', this.featureLayer.graphics.length);
  }

  // ── createEditor ─────────────────────────────────────────────────────────

  private async createEditor(): Promise<void> {
    for (const h of this.editorHandles) { try { h.remove(); } catch { } }
    this.editorHandles = [];
    if (this.graphicsEditor) {
      try { this.graphicsEditor.cancel(); } catch { }
      try { this.graphicsEditor.destroy(); } catch { }
    }

    this.graphicsEditor = new SketchViewModel({
      view: this.view,
      layer: this.sketchLayer,
      defaultUpdateOptions: {
        enableRotation: this.enableUserEditRotating,
        enableScaling: this.enableUserEditScaling,
        multipleSelectionEnabled: false,
        preserveAspectRatio: this.enableUserEditUniformScaling,
        toggleToolOnClick: false
      },
      updateOnGraphicClick: false
    });

    const createHandle = this.graphicsEditor.on('create', (evt: any) => {
      console.log('[arc-geojson-layer] create:', evt.state, evt.graphic?.geometry?.type);
      if (evt.state === 'complete' && evt.graphic && !this._isStartingDraw) {
        const cloned = evt.graphic.clone();
        this.sketchLayer.graphics.removeAll();
        this.inDrawingMode = false;
        this.addToGeojson(cloned);
      }
    });
    this.editorHandles.push(createHandle);

    const updateHandle = this.graphicsEditor.on('update', (evt: any) => {
      if (evt.state === 'complete' && evt.graphics?.length) {
        for (const g of evt.graphics) {
          if (!g?.geometry) continue;
          this.sketchLayer.graphics.remove(g);
          if (!this.featureLayer.graphics.includes(g)) this.featureLayer.add(g);
          this.updateGeojsonWithChanges(g);
        }
        this.enableInfoPopupWindow(true);
      }
      if (evt.state === 'cancel') {
        this.sketchLayer.graphics.toArray().forEach((g: Graphic) => {
          this.sketchLayer.graphics.remove(g);
          if (!this.featureLayer.graphics.includes(g)) this.featureLayer.add(g);
        });
        this.enableInfoPopupWindow(true);
      }
    });
    this.editorHandles.push(updateHandle);
  }

  // ── bindViewEvents ────────────────────────────────────────────────────────

  private bindViewEvents(): void {
    let clickTimer: any = null;

    const clickHandle = this.view.on('click', async (evt: any) => {
      const hit = await this.view.hitTest(evt);
      const graphic = this.getLayerGraphicFromHit(hit);
      if (!graphic) return;
      clickTimer = setTimeout(async () => {
        clickTimer = null;
        if (this.enableUserEdit) {
          if ((evt.native?.ctrlKey || evt.native?.metaKey) && this.enableUserEditRemove) {
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
        if (!this.inDrawingMode) this.showGraphicPopup(graphic, evt.mapPoint);
      }, 250);
    });

    const dblClickHandle = this.view.on('double-click', async (evt: any) => {
      if (clickTimer) { clearTimeout(clickTimer); clickTimer = null; }
      if (this.view?.popup?.visible) this.view.popup.close();
      const hit = await this.view.hitTest(evt);
      const graphic = this.getLayerGraphicFromHit(hit);
      if (!graphic) return;
      this.emitLayerEvent('doubleClick', this.buildMouseEvent(graphic, evt.mapPoint));
      if (this.enableUserEdit) {
        this.enableInfoPopupWindow(false);
        await this.activateGraphicsEditor(graphic);
        return;
      }
      if (!this.inDrawingMode) this.showGraphicPopup(graphic, evt.mapPoint);
    });

    const pointerMoveHandle = this.view.on('pointer-move', async (evt: any) => {
      const hit = await this.view.hitTest(evt);
      const graphic = this.getLayerGraphicFromHit(hit);
      if (!graphic) {
        if (this.hoveredGraphicUid !== undefined) {
          this.hoveredGraphicUid = undefined;
          this.emitLayerEvent('layerMouseOut', { coordinates: { latitude: 0, longitude: 0 }, attributes: {} });
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

  // ── updateEditing ─────────────────────────────────────────────────────────

  async updateEditing(_newUserEnableEdit: boolean): Promise<void> {
    if (!this.featureLayer) { this._pendingEnableUserEdit = _newUserEnableEdit; return; }
    if (this.graphicsEditor?.state === 'active') {
      try { this.graphicsEditor.cancel(); } catch { }
    }
    this.featureLayer.graphics.forEach((g: Graphic) => {
      g.popupTemplate = _newUserEnableEdit
        ? null as unknown as never
        : this.buildPopupTemplateFromCurrent(g);
    });
    this.enableInfoPopupWindow(!_newUserEnableEdit && !this.inDrawingMode);
  }

  // ── updateGeojson ─────────────────────────────────────────────────────────

  async updateGeojson(newGeojson: string | FeatureCollection): Promise<void> {
    if (this.inDrawingMode || this.removingItem ||
        this.blockGeoJsonUpdate || this._isStartingDraw) return;

    const parsed = ArcGeojsonLayer.parseJson<FeatureCollection>(newGeojson);
    const incomingCount = parsed.parsedJson?.features?.length ?? 0;

    console.log('[arc-geojson-layer] updateGeojson name:', this.name,
      'count:', incomingCount, 'editMode:', this.enableUserEdit);

    // Allow clear always; block data updates during edit mode
    if (this.enableUserEdit && incomingCount > 0) return;

    if (!this.featureLayer) { await this.createLayer(newGeojson); return; }

    if (incomingCount === 0) {
      try { this.graphicsEditor?.cancel(); } catch { }
      this.sketchLayer?.graphics?.removeAll();
    }

    this.featureLayer.removeAll();
    this.labelLayer?.removeAll();

    const fsInfo = this.getUpGISJson(newGeojson);
    if (fsInfo) for (const g of fsInfo.graphics) this.featureLayer.add(g);

    console.log('[arc-geojson-layer] updateGeojson DONE name:', this.name,
      'graphics:', this.featureLayer.graphics.length);

    this.updateRenderer(this.renderer);
    this.refreshLabels();
    this.updateInfoTemplate(this.infoTemplate);
  }

  // ── updateInfoTemplate ────────────────────────────────────────────────────

  updateInfoTemplate(newInfoTemplate: any): void {
    this.infoTemplate = newInfoTemplate;
    if (!this.featureLayer) return;
    const parsed = ArcGeojsonLayer.parseJson<InfoTemplateDetails>(newInfoTemplate);
    if (!parsed.parsedJson) return;
    this.featureLayer.graphics.forEach((g: Graphic) => {
      g.popupTemplate = this.buildPopupTemplate(parsed.parsedJson);
    });
  }

  updateLabelJson(v: string | object | object[]): void { this.labelJson = v; this.refreshLabels(); }

  updateLayerClass(cls: string): void {
    this.layerClass = cls;
    if (this.featureLayer) (this.featureLayer as any).className = cls;
    if (this.labelLayer) (this.labelLayer as any).className = `${cls}-labels`;
  }

  // ── updateRenderer ────────────────────────────────────────────────────────
  // GraphicsLayer does NOT support renderers — symbols must be set per-graphic.
  // We parse the renderer JSON, extract the symbol, and apply it to each graphic.
  // Supports both legacy esriSMS/esriSLS/esriSFS and ArcGIS 5.0 format.

  updateRenderer(newRenderer: any): void {
    this.renderer = newRenderer;
    if (!this.featureLayer) return;

    // Parse renderer and extract symbol config
    const parsedSymbol = this.extractSymbolFromRenderer(newRenderer);

    this.featureLayer.graphics.forEach((g: Graphic) => {
      g.symbol = this.buildSymbolForGraphic(g.geometry, parsedSymbol);
    });
  }

  // Extracts symbol config from renderer JSON (supports simple/uniqueValue/classBreaks)
  private extractSymbolFromRenderer(renderer: any): any | null {
    if (!renderer) return null;
    const parsed = ArcGeojsonLayer.parseJson(renderer);
    if (!parsed.parsedJson) return null;
    // For simple renderer, use the symbol directly
    return parsed.parsedJson?.symbol ?? null;
  }

  // Builds ArcGIS 5.0 symbol from symbol config
  // Supports both esriSMS/esriSLS/esriSFS (old) and simple-marker/simple-line/simple-fill (new)
  private buildSymbolForGraphic(geometry: Geometry | null | undefined, symbolConfig: any): any {
    if (!geometry) return null;

    // If we have a renderer symbol config, use it
    if (symbolConfig) {
      const type = (symbolConfig.type || '').toLowerCase();
      const color = symbolConfig.color ?? this.DEFAULT_SYMBOL_COLOR;

      // Point symbols: esriSMS or simple-marker
      if (type === 'esrisms' || type === 'simple-marker' || ArcGeojsonLayer.isPoint(geometry)) {
        return new SimpleMarkerSymbol({
          style: this.normalizeStyle(symbolConfig.style, 'circle'),
          size: symbolConfig.size ?? ArcGeojsonLayer.DEFAULT_SYMBOL_MARKER_SIZE,
          color: color,
          outline: symbolConfig.outline
            ? new SimpleLineSymbol({
                color: symbolConfig.outline.color ?? [0, 0, 0, 200],
                width: symbolConfig.outline.width ?? 1
              })
            : new SimpleLineSymbol({ color: [0, 0, 0, 200], width: 1 })
        });
      }

      // Line symbols: esriSLS or simple-line
      if (type === 'esrisls' || type === 'simple-line' || ArcGeojsonLayer.isPolyline(geometry)) {
        return new SimpleLineSymbol({
          style: this.normalizeStyle(symbolConfig.style, 'solid'),
          width: symbolConfig.width ?? ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH,
          color: color
        });
      }

      // Fill symbols: esriSFS or simple-fill
      if (type === 'esrisfs' || type === 'simple-fill' || ArcGeojsonLayer.isPolygon(geometry)) {
        return new SimpleFillSymbol({
          style: this.normalizeStyle(symbolConfig.style, 'solid'),
          color: color,
          outline: symbolConfig.outline
            ? new SimpleLineSymbol({
                color: symbolConfig.outline.color ?? [110, 110, 110, 255],
                width: symbolConfig.outline.width ?? ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH
              })
            : new SimpleLineSymbol({ color: [110, 110, 110, 255], width: ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH })
        });
      }
    }

    // No renderer or unrecognized — use JsonUtils default
    return this.getDefaultSymbolForGeometry(geometry);
  }

  // Normalizes esri legacy style strings to ArcGIS 5.0 style strings
  private normalizeStyle(style: string | undefined, fallback: string): string {
    if (!style) return fallback;
    const map: Record<string, string> = {
      'esriSMSCircle': 'circle',
      'esriSMSSquare': 'square',
      'esriSMSDiamond': 'diamond',
      'esriSMSCross': 'cross',
      'esriSMSX': 'x',
      'esriSLSSolid': 'solid',
      'esriSLSDash': 'dash',
      'esriSLSDot': 'dot',
      'esriSFSSolid': 'solid',
      'esriSFSNull': 'none',
    };
    return map[style] ?? style;
  }

  // ── getDefaultSymbolForGeometry ───────────────────────────────────────────
  // Uses JsonUtils.getJsonSymbolFor to get symbol config (returns esriSMS format)
  // then constructs ArcGIS 5.0 symbols directly — fromJSON() not used because
  // ArcGIS 5.0 does not accept esriSMS/esriSLS/esriSFS in fromJSON()

  private getDefaultSymbolForGeometry(geometry: Geometry | null | undefined): any {
    if (!geometry) return null;

    const symbolJson = JsonUtils.getJsonSymbolFor(
      geometry.type,
      this.DEFAULT_SYMBOL_COLOR,
      ArcGeojsonLayer.DEFAULT_SYMBOL_MARKER_SIZE
    ) as any;

    const sym = symbolJson?.symbol;
    if (!sym) return this.buildFallbackSymbol(geometry);

    return this.buildSymbolForGraphic(geometry, sym);
  }

  // Fallback symbols using direct ArcGIS 5.0 constructors
  private buildFallbackSymbol(geometry: Geometry): any {
    const c = this.DEFAULT_SYMBOL_COLOR;
    if (ArcGeojsonLayer.isPoint(geometry)) {
      return new SimpleMarkerSymbol({
        style: 'circle', size: ArcGeojsonLayer.DEFAULT_SYMBOL_MARKER_SIZE,
        color: c as any,
        outline: new SimpleLineSymbol({ color: [0, 0, 0, 200] as any, width: 1 })
      });
    }
    if (ArcGeojsonLayer.isPolyline(geometry)) {
      return new SimpleLineSymbol({
        style: 'solid', width: ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH, color: c as any
      });
    }
    return new SimpleFillSymbol({
      style: 'solid', color: [c[0], c[1], c[2], 100] as any,
      outline: new SimpleLineSymbol({ color: [110, 110, 110, 255] as any, width: ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH })
    });
  }

  // ── startDrawing ──────────────────────────────────────────────────────────

  async startDrawing(drawGeometryType: string): Promise<void> {
    if (!this.featureLayer || !this.view) return;
    console.log('[arc-geojson-layer] startDrawing:', drawGeometryType, 'name:', this.name);

    this._isStartingDraw = true;
    try { this.graphicsEditor?.cancel(); } catch { }
    this.featureLayer.removeAll();
    this.labelLayer?.removeAll();
    this.sketchLayer?.graphics?.removeAll();
    this._isStartingDraw = false;

    this.enableUserEdit = false;
    this.inDrawingMode = true;
    this.enableInfoPopupWindow(false);

    await this.createEditor();
    await new Promise<void>(r => setTimeout(r, 50));

    const tool = this.toSketchCreateTool(drawGeometryType);
    console.log('[arc-geojson-layer] tool:', tool);

    try {
      this.graphicsEditor.create(tool);
      if (this.graphicsEditor.state !== 'active') {
        await this.createEditor();
        await new Promise<void>(r => setTimeout(r, 50));
        this.graphicsEditor.create(tool);
      }
    } catch (e) {
      console.error('[arc-geojson-layer] startDrawing error:', e);
      await this.createEditor();
      await new Promise<void>(r => setTimeout(r, 50));
      try { this.graphicsEditor.create(tool); } catch { }
      this.inDrawingMode = false;
    }
  }

  async cancelDrawing(): Promise<void> {
    this.inDrawingMode = false;
    this.sketchLayer?.graphics?.removeAll();
    try { this.graphicsEditor.cancel(); } catch { }
    this.enableInfoPopupWindow(true);
  }

  // ── activateGraphicsEditor ────────────────────────────────────────────────

  async activateGraphicsEditor(graphic: Graphic): Promise<void> {
    if (!this.enableUserEdit || !this.graphicsEditor) return;
    this.enableInfoPopupWindow(false);
    if (this.graphicsEditor.state === 'active') {
      try { this.graphicsEditor.cancel(); } catch { }
    }
    this.featureLayer.remove(graphic);
    if (!graphic.symbol) graphic.symbol = this.getDefaultSymbolForGeometry(graphic.geometry);
    this.sketchLayer.add(graphic);
    try {
      this.graphicsEditor.update([graphic], {
        tool: this.resolveUpdateTool(),
        enableRotation: this.enableUserEditRotating,
        enableScaling: this.enableUserEditScaling,
        preserveAspectRatio: this.enableUserEditUniformScaling,
        multipleSelectionEnabled: false,
        toggleToolOnClick: false
      });
    } catch (e: any) {
      console.warn('[arc-geojson-layer] activateGraphicsEditor error:', e?.message);
      this.sketchLayer.remove(graphic);
      this.featureLayer.add(graphic);
    }
  }

  // ── Public methods ────────────────────────────────────────────────────────

  async findFeatureByUniqueId(uniqueId: string | number): Promise<Graphic | undefined> {
    return this.featureLayer?.graphics.find(
      (g: Graphic) => g.attributes?.[this.uniqueIdPropertyName] === uniqueId
    );
  }

  async getLayerId(): Promise<string> { return this.featureLayer?.id ?? 'arc-geojson-layer'; }

  async openPopup(id: string | number): Promise<void> {
    const g = await this.findFeatureByUniqueId(id);
    if (!g?.geometry) return;
    this.showGraphicPopup(g, ArcGeojsonLayer.getPopupPoint(g.geometry));
  }

  async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {
    const g = await this.findFeatureByUniqueId(id);
    if (!g?.geometry) return;
    if (ArcGeojsonLayer.isPoint(g.geometry)) {
      await this.view.goTo({ center: g.geometry, zoom: zoomLevel }); return;
    }
    const extent = g.geometry.extent;
    if (extent) await this.view.goTo(extent.expand(1.5));
  }

  enableInfoPopupWindow(enable: boolean): void {
    if (!enable && this.view?.popup?.visible) this.view.popup.close();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  private getUpGISJson(geojson: string | object): { graphics: Graphic[]; geometryType?: string } | null {
    const result = ArcGeojsonLayer.parseJson<FeatureCollection>(geojson);
    if (!result.parsedJson || result.parsedJson.type !== 'FeatureCollection') return null;
    const graphics: Graphic[] = [];
    let geometryType: string | undefined;
    result.parsedJson.features.forEach((f: Feature, i: number) => {
      const g = this.geojsonFeatureToGraphic(f, i);
      if (g?.geometry) {
        if (!geometryType) geometryType = g.geometry.type;
        graphics.push(g);
      }
    });
    return { graphics, geometryType };
  }

  private geojsonFeatureToGraphic(feature: Feature, index: number): Graphic | null {
    const geometry = this.geojsonGeometryToArcGeometry(feature.geometry);
    if (!geometry) return null;
    const props = { ...(feature.properties ?? {}) } as any;
    if (props[this.uniqueIdPropertyName] === undefined) props[this.uniqueIdPropertyName] = index;
    if (props.OBJECTID === undefined) props.OBJECTID = index;
    const graphic = new Graphic({
      geometry, attributes: props,
      symbol: this.getDefaultSymbolForGeometry(geometry)
    });
    graphic.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic, infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName,
      fallbackTitle: this.name || 'Details'
    });
    return graphic;
  }

  private geojsonGeometryToArcGeometry(geometry: GeoJsonGeometry | null): Geometry | null {
    if (!geometry) return null;
    const sr = { wkid: 4326 };
    switch (geometry.type) {
      case 'Point': { const [x, y] = geometry.coordinates as number[]; return new Point({ x, y, spatialReference: sr }); }
      case 'MultiPoint': { const pts = geometry.coordinates as number[][]; if (!pts.length) return null; return new Point({ x: pts[0][0], y: pts[0][1], spatialReference: sr }); }
      case 'LineString': return new Polyline({ paths: [geometry.coordinates as number[][]], spatialReference: sr });
      case 'MultiLineString': return new Polyline({ paths: geometry.coordinates as number[][][], spatialReference: sr });
      case 'Polygon': return new Polygon({ rings: geometry.coordinates as number[][][], spatialReference: sr });
      case 'MultiPolygon': { const f = (geometry.coordinates as number[][][][])[0]; return f ? new Polygon({ rings: f, spatialReference: sr }) : null; }
      default: return null;
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
      return paths.length <= 1 ? { type: 'LineString', coordinates: paths[0] ?? [] } : { type: 'MultiLineString', coordinates: paths };
    }
    const poly = this.toGeographicPolygon(geometry as Polygon);
    return { type: 'Polygon', coordinates: poly.rings as any };
  }

  private graphicToGeoJsonFeature(graphic: Graphic): Feature | null {
    if (!graphic.geometry) return null;
    return { type: 'Feature', geometry: this.arcGeometryToGeoJsonGeometry(graphic.geometry), properties: { ...(graphic.attributes ?? {}) } };
  }

  private toFeatureCollectionFromLayer(): FeatureCollection {
    return {
      type: 'FeatureCollection',
      features: this.featureLayer.graphics.toArray()
        .map((g: Graphic) => this.graphicToGeoJsonFeature(g))
        .filter((f: Feature | null): f is Feature => f !== null)
    };
  }

  private addToGeojson(newGraphic: Graphic): void {
    if (this._isStartingDraw) return;
    if (!newGraphic.attributes) newGraphic.attributes = {};
    if (newGraphic.attributes[this.uniqueIdPropertyName] === undefined)
      newGraphic.attributes[this.uniqueIdPropertyName] = Date.now();
    if (newGraphic.attributes.OBJECTID === undefined)
      newGraphic.attributes.OBJECTID = Date.now();
    newGraphic.symbol = this.getDefaultSymbolForGeometry(newGraphic.geometry);
    newGraphic.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic: newGraphic, infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName, fallbackTitle: this.name || 'Details'
    });
    if (!this.featureLayer.graphics.includes(newGraphic)) this.featureLayer.add(newGraphic);
    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();
    this.blockGeoJsonUpdate = false;
    this.refreshLabels();
    this.emitLayerEvent('userDrawItemAdded', this.graphicToGeoJsonFeature(newGraphic));
  }

  private removeFromGeojson(graphicToRemove: Graphic): void {
    this.featureLayer.remove(graphicToRemove);
    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();
    this.blockGeoJsonUpdate = false;
    this.refreshLabels();
    this.emitLayerEvent('userEditItemRemoved', this.graphicToGeoJsonFeature(graphicToRemove));
  }

  private updateGeojsonWithChanges(graphicToUpdate: Graphic): void {
    if (!graphicToUpdate?.geometry) return;
    graphicToUpdate.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic: graphicToUpdate, infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName, fallbackTitle: this.name || 'Details'
    });
    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();
    this.blockGeoJsonUpdate = false;
    this.refreshLabels();
    const feature = this.graphicToGeoJsonFeature(graphicToUpdate);
    if (!feature?.geometry) return;
    this.emitLayerEvent('userEditItemUpdated', feature);
  }

  private buildPopupTemplate(info: InfoTemplateDetails): PopupTemplate {
    return new PopupTemplate({
      title: (e: any) => { const g = e?.graphic ?? e; return typeof info.listItem === 'function' ? info.listItem(g) : info.listItem; },
      content: (e: any) => { const g = e?.graphic ?? e; return typeof info.details === 'function' ? info.details(g) : info.details; }
    });
  }

  private buildPopupTemplateFromCurrent(graphic: Graphic): PopupTemplate | null {
    const p = ArcGeojsonLayer.parseJson<InfoTemplateDetails>(this.infoTemplate);
    if (!p.parsedJson) return null;
    const info = p.parsedJson;
    return new PopupTemplate({
      title: typeof info.listItem === 'function' ? info.listItem(graphic) : info.listItem,
      content: typeof info.details === 'function' ? info.details(graphic) : info.details
    });
  }

  private showGraphicPopup(graphic: Graphic, mapPoint?: Point): void {
    if (this.enableUserEdit || this.inDrawingMode) return;
    if (!graphic.geometry) return;
    const location = mapPoint ?? ArcGeojsonLayer.getPopupPoint(graphic.geometry);
    graphic.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic, infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName, fallbackTitle: this.name || 'Details'
    });
    if (this.view?.popup) this.view.openPopup({ location, features: [graphic] });
  }

  private refreshLabels(): void {
    if (!this.labelLayer) return;
    this.labelLayer.removeAll();
    const labelColor = JsonUtils.resolveLabelColor(this.labelColor);
    const labelSize = JsonUtils.resolveLabelSize(this.labelSize);
    this.featureLayer.graphics.forEach((g: Graphic) => {
      const label = g.attributes?.LABEL;
      if (!label || !g.geometry) return;
      const pt = ArcGeojsonLayer.getPopupPoint(g.geometry);
      this.labelLayer.add(new Graphic({
        geometry: pt,
        attributes: { __labelFor: g.attributes?.[this.uniqueIdPropertyName] },
        symbol: new TextSymbol({
          text: String(label), color: labelColor as any,
          haloColor: 'black', haloSize: 1, xoffset: 3, yoffset: 3,
          font: { size: labelSize, family: 'sans-serif', weight: 'bold' }
        })
      }));
    });
  }

  private determineExistingGeometryType(): string | undefined {
    return this.featureLayer?.graphics?.getItemAt(0)?.geometry?.type;
  }

  private toSketchCreateTool(t: string): 'point' | 'polyline' | 'polygon' | 'rectangle' | 'circle' {
    switch ((t || '').toUpperCase()) {
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
    if (this.enableUserEditVertices || this.enableUserEditAddVertices || this.enableUserEditDeleteVertices) return 'reshape';
    if (this.enableUserEditScaling || this.enableUserEditRotating) return 'transform';
    return 'move';
  }

  private toGeographicPoint(p: Point): Point {
    return p.spatialReference?.isWGS84 ? p : webMercatorUtils.webMercatorToGeographic(p) as Point;
  }

  private toGeographicPolyline(p: Polyline): Polyline {
    return p.spatialReference?.isWGS84 ? p : webMercatorUtils.webMercatorToGeographic(p) as Polyline;
  }

  private toGeographicPolygon(p: Polygon): Polygon {
    return p.spatialReference?.isWGS84 ? p : webMercatorUtils.webMercatorToGeographic(p) as Polygon;
  }

  private buildMouseEvent(graphic: Graphic, mapPoint: Point | null): LayerMouseEvent {
    const gp = mapPoint ? webMercatorUtils.webMercatorToGeographic(mapPoint) as Point : null;
    return { coordinates: { latitude: gp?.y ?? 0, longitude: gp?.x ?? 0 }, attributes: graphic?.attributes ?? {} };
  }

  private emitLayerEvent(name: string, detail: any): void {
    this.dispatchEvent(new CustomEvent(name, { detail, bubbles: true, composed: true }));
  }

  private getLayerGraphicFromHit(hit: any): Graphic | undefined {
    return hit?.results?.find(
      (r: any) => r.graphic?.layer === this.featureLayer || r.graphic?.layer === this.sketchLayer
    )?.graphic;
  }

  private getGraphicUniqueId(g: Graphic): string | number | undefined {
    return g.attributes?.[this.uniqueIdPropertyName] ?? g.attributes?.OBJECTID;
  }

  static parseJson<T = any>(value: any): JsonParseResult<T> {
    if (value === null || value === undefined) return { error: new Error('null/undefined') };
    if (typeof value === 'string') {
      try { return { parsedJson: JSON.parse(value) as T }; }
      catch (e: any) { return { error: e instanceof Error ? e : new Error(String(e)) }; }
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
      return new Point({ x: path[mid]?.[0] ?? 0, y: path[mid]?.[1] ?? 0, spatialReference: pl.spatialReference });
    }
    if (ArcGeojsonLayer.isPolygon(geometry)) return (geometry as Polygon).centroid ?? new Point({ x: 0, y: 0 });
    return new Point({ x: 0, y: 0 });
  }

  static getRandomColor(): number[] {
    return [Math.floor(Math.random() * 200), Math.floor(Math.random() * 200), Math.floor(Math.random() * 200), 200];
  }

  static isPoint(g: Geometry): g is Point { return g?.type === 'point'; }
  static isPolyline(g: Geometry): g is Polyline { return g?.type === 'polyline'; }
  static isPolygon(g: Geometry): g is Polygon { return g?.type === 'polygon'; }
}

declare global {
  interface HTMLElementTagNameMap { 'arc-geojson-layer': ArcGeojsonLayer; }
}
