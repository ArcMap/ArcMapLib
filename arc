import { LitElement, PropertyValues } from 'lit';
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
import * as rendererJsonUtils from '@arcgis/core/renderers/support/jsonUtils';
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

// Internal tag to mark geojson updates that come from the library itself
// Prevents update loops without needing blockGeoJsonUpdate flag
const INTERNAL_GEOJSON_TAG = Symbol('internal-geojson');

@customElement('arc-geojson-layer')
export class ArcGeojsonLayer extends LitElement {

  private graphicsEditor!: SketchViewModel;
  private ancestorMap!: any;
  private readonly DEFAULT_SYMBOL_COLOR: number[] = ArcGeojsonLayer.getRandomColor();

  private static readonly DEFAULT_SYMBOL_LINE_WIDTH = 1;
  private static readonly DEFAULT_SYMBOL_MARKER_SIZE = 10;

  private featureLayer!: GraphicsLayer;
  private labelLayer!: GraphicsLayer;

  // FIX: separate sketchLayer for SketchViewModel
  // In original code, SketchViewModel used featureLayer directly.
  // This caused graphics to be on featureLayer during editing and
  // made it impossible to clear them when switching draw modes.
  private sketchLayer!: GraphicsLayer;

  private view!: MapView;

  private inDrawingMode = false;
  private removingItem = false;
  private blockGeoJsonUpdate = false;
  private graphicMoved = false;
  private _isStartingDraw = false;
  private hoveredGraphicUid: string | number | undefined;
  private eventHandles: Array<{ remove: () => void }> = [];
  private editorHandles: Array<{ remove: () => void }> = [];

  // FIX: tracks init state — LitElement updated() fires before
  // connectedCallback async work completes unlike Stencil @Watch
  private _initComplete = false;
  private _pendingEnableUserEdit: boolean | undefined = undefined;

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

    // FIX: MutationObserver waits for element to be inside arc-map.
    // Angular @if recreates element but connectedCallback fires before
    // element is fully attached to DOM — closest() returns null without this.
    await this.waitForAncestorMap();
    if (!this.isConnected) return;

    try {
      await this.resolveAncestorMapAndView();
      await this.createLayer(this.geojson);
      this.bindViewEvents();
      this._initComplete = true;
      console.log('[arc-geojson-layer] connectedCallback COMPLETE, name:', this.name);

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
    console.log('[arc-geojson-layer] disconnectedCallback, name:', this.name);

    for (const handle of this.eventHandles) { if (handle) handle.remove(); }
    this.eventHandles = [];
    for (const handle of this.editorHandles) { if (handle) handle.remove(); }
    this.editorHandles = [];

    if (this.graphicsEditor) {
      try { this.graphicsEditor.cancel(); } catch { }
      try { this.graphicsEditor.destroy(); } catch { }
    }

    // FIX: explicitly remove ALL layers including sketchLayer
    // Without this, old layers stay on map as ghost graphics
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
  }

  protected updated(changedProps: Map<string, unknown>): void {
    // FIX: guard against updated() firing before init completes
    if (!this._initComplete) {
      if (changedProps.has('enableUserEdit')) {
        this._pendingEnableUserEdit = this.enableUserEdit;
      }
      return;
    }

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
          observer.disconnect();
          resolve();
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });
    });
  }

  // ── resolveAncestorMapAndView ─────────────────────────────────────────────

  private async resolveAncestorMapAndView(): Promise<void> {
    this.ancestorMap = this.closest('arc-map') as any;
    if (!this.ancestorMap) {
      throw new Error('arc-geojson-layer must be a descendant of an <arc-map> element');
    }
    if (typeof this.ancestorMap.componentOnReady === 'function') {
      await this.ancestorMap.componentOnReady();
    }
    if (typeof this.ancestorMap.getViewInstance !== 'function') {
      throw new Error('ancestor arc-map must expose getViewInstance()');
    }
    this.view = await this.ancestorMap.getViewInstance();
    if (!this.view) throw new Error('ancestor arc-map getViewInstance() returned undefined');
    await this.view.when();
  }

  // ── createLayer ───────────────────────────────────────────────────────────

  private async createLayer(geojson: string | FeatureCollection): Promise<void> {
    console.log('[arc-geojson-layer] createLayer START, name:', this.name);

    const graphicsId = `${this.id || 'arc-geojson-layer'}-graphics`;
    const labelsId = `${this.id || 'arc-geojson-layer'}-labels`;
    const sketchId = `${this.id || 'arc-geojson-layer'}-sketch`;

    // FIX: remove stale layers from previous instance
    // Angular @if recreation leaves old layers on map if disconnectedCallback
    // didn't fully clean up (race condition with async view operations)
    if (this.view?.map) {
      const staleGraphics = this.view.map.findLayerById(graphicsId);
      if (staleGraphics) {
        (staleGraphics as GraphicsLayer).graphics?.removeAll();
        this.view.map.remove(staleGraphics);
        console.log('[arc-geojson-layer] removed stale featureLayer, name:', this.name);
      }
      const staleLabels = this.view.map.findLayerById(labelsId);
      if (staleLabels) {
        (staleLabels as GraphicsLayer).graphics?.removeAll();
        this.view.map.remove(staleLabels);
      }
      const staleSketch = this.view.map.findLayerById(sketchId);
      if (staleSketch) {
        (staleSketch as GraphicsLayer).graphics?.removeAll();
        this.view.map.remove(staleSketch);
      }
    }

    this.featureLayer = new GraphicsLayer({
      id: graphicsId,
      title: this.name || this.id || 'Arc GeoJSON Layer'
    });

    this.labelLayer = new GraphicsLayer({
      id: labelsId,
      title: `${this.name || this.id || 'Arc GeoJSON Layer'} Labels`,
      listMode: 'hide'
    });

    // FIX: separate sketchLayer for SketchViewModel
    // Original used featureLayer as sketch layer which caused
    // graphics to be unremovable when switching draw modes
    this.sketchLayer = new GraphicsLayer({
      id: sketchId,
      listMode: 'hide'
    });

    if (this.view?.map) {
      this.view.map.add(this.featureLayer);
      this.view.map.add(this.labelLayer);
      this.view.map.add(this.sketchLayer);
      console.log('[arc-geojson-layer] layers added, name:', this.name,
        'on map:', this.view.map.layers.includes(this.featureLayer));
    }

    const parsedGeojson = geojson ?? { type: 'FeatureCollection', features: [] };
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

    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();
    this.blockGeoJsonUpdate = false;

    console.log('[arc-geojson-layer] createLayer COMPLETE, name:', this.name,
      'graphics:', this.featureLayer.graphics.length);
  }

  // ── createEditor ─────────────────────────────────────────────────────────

  private async createEditor(): Promise<void> {
    // Destroy previous editor
    for (const h of this.editorHandles) { try { h.remove(); } catch { } }
    this.editorHandles = [];
    if (this.graphicsEditor) {
      try { this.graphicsEditor.cancel(); } catch { }
      try { this.graphicsEditor.destroy(); } catch { }
    }

    // FIX: use sketchLayer not featureLayer
    // Original: layer: this.featureLayer
    // This caused SketchViewModel to own featureLayer graphics
    // making them impossible to remove independently
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
      console.log('[arc-geojson-layer] CREATE EVENT state:', evt.state,
        'geomType:', evt.graphic?.geometry?.type);
      if (evt.state === 'complete' && evt.graphic) {
        if (this._isStartingDraw) return;
        // FIX: clone graphic before clearing sketchLayer
        const cloned = evt.graphic.clone();
        this.sketchLayer.graphics.removeAll();
        this.inDrawingMode = false;
        this.enableInfoPopupWindow(false);
        this.addToGeojson(cloned);
      }
    });
    this.editorHandles.push(createHandle);

    // FIX: only fire on stop events — not mid-edit
    // Prevents emitting events with undefined geometry
    const updateHandle = this.graphicsEditor.on('update', (evt: any) => {
      if (evt.toolEventInfo?.type === 'move-start') this.graphicMoved = false;
      if (evt.toolEventInfo?.type === 'move') this.graphicMoved = true;
      if (evt.toolEventInfo?.type === 'reshape-start') this.graphicMoved = true;
      if (evt.toolEventInfo?.type === 'scale-start') this.graphicMoved = true;
      if (evt.toolEventInfo?.type === 'rotate-start') this.graphicMoved = true;

      if (evt.state === 'complete' && evt.graphics?.length) {
        for (const graphic of evt.graphics) {
          if (!graphic?.geometry) continue;
          // Move graphic back to featureLayer after edit completes
          this.sketchLayer.graphics.remove(graphic);
          if (!this.featureLayer.graphics.includes(graphic)) {
            this.featureLayer.add(graphic);
          }
          this.updateGeojsonWithChanges(graphic);
        }
        this.enableInfoPopupWindow(true);
      }

      if (evt.state === 'cancel') {
        // Restore graphics from sketchLayer to featureLayer on cancel
        this.sketchLayer.graphics.toArray().forEach((g: Graphic) => {
          this.sketchLayer.graphics.remove(g);
          if (!this.featureLayer.graphics.includes(g)) {
            this.featureLayer.add(g);
          }
        });
        this.enableInfoPopupWindow(true);
      }
    });
    this.editorHandles.push(updateHandle);
  }

  // ── bindViewEvents ────────────────────────────────────────────────────────

  private bindViewEvents(): void {
    let clickTimer: any = null;

    // FIX: use hitTest on both featureLayer AND sketchLayer
    const clickHandle = this.view.on('click', async (evt: any) => {
      // FIX: 250ms delay so double-click can cancel single-click
      // prevents popup from showing when double-clicking to edit
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

        const mouseEvent = this.buildMouseEvent(graphic, evt.mapPoint);
        this.emitLayerEvent('layerClick', mouseEvent);

        if (!this.inDrawingMode) {
          this.showGraphicPopup(graphic, evt.mapPoint);
        }
      }, 250);
    });

    const dblClickHandle = this.view.on('double-click', async (evt: any) => {
      // Cancel pending single-click — prevents popup
      if (clickTimer) { clearTimeout(clickTimer); clickTimer = null; }

      if (this.view?.popup?.visible) this.view.popup.close();

      const hit = await this.view.hitTest(evt);
      const graphic = this.getLayerGraphicFromHit(hit);
      if (!graphic) return;

      const mouseEvent = this.buildMouseEvent(graphic, evt.mapPoint);
      this.emitLayerEvent('doubleClick', mouseEvent);

      // FIX: double-click always activates editor if enableUserEdit is on
      if (this.enableUserEdit) {
        this.enableInfoPopupWindow(false);
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

      const graphicUid = this.getGraphicUniqueId(graphic);
      if (this.hoveredGraphicUid !== graphicUid) {
        if (this.hoveredGraphicUid !== undefined) {
          this.emitLayerEvent('layerMouseOut', this.buildMouseEvent(graphic, evt.mapPoint));
        }
        this.hoveredGraphicUid = graphicUid;
        this.emitLayerEvent('layerMouseOver', this.buildMouseEvent(graphic, evt.mapPoint));
      }
    });

    this.eventHandles.push(clickHandle, dblClickHandle, pointerMoveHandle);
  }

  // ── updateEditing ─────────────────────────────────────────────────────────

  async updateEditing(_newUserEnableEdit: boolean): Promise<void> {
    if (!this.featureLayer) {
      this._pendingEnableUserEdit = _newUserEnableEdit;
      return;
    }

    if (this.graphicsEditor?.state === 'active') {
      try { this.graphicsEditor.cancel(); } catch { }
    }

    if (_newUserEnableEdit) {
      this.featureLayer.graphics.forEach((graphic: Graphic) => {
        graphic.popupTemplate = null as unknown as never;
      });
    } else {
      this.featureLayer.graphics.forEach((graphic: Graphic) => {
        graphic.popupTemplate = this.buildPopupTemplateFromCurrent(graphic);
      });
    }

    this.enableInfoPopupWindow(!_newUserEnableEdit && !this.inDrawingMode);
  }

  // ── updateGeojson ─────────────────────────────────────────────────────────

  async updateGeojson(newGeojson: string | FeatureCollection): Promise<void> {
    if (this.inDrawingMode || this.removingItem || this.blockGeoJsonUpdate || this._isStartingDraw) {
      return;
    }

    // FIX: allow clear (incomingCount=0) even when enableUserEdit is true
    // Original blocked all updates when enableUserEdit was on
    // This prevented clearing fences when closing the expansion panel
    const parsed = ArcGeojsonLayer.parseJson<FeatureCollection>(newGeojson);
    const incomingCount = parsed.parsedJson?.features?.length ?? 0;
    if (this.enableUserEdit && incomingCount > 0) return;

    if (!this.featureLayer) {
      await this.createLayer(newGeojson);
      return;
    }

    console.log('[arc-geojson-layer] updateGeojson PROCEEDING, name:', this.name,
      'incomingCount:', incomingCount);

    // FIX: cancel editor and clear sketchLayer before clearing featureLayer
    // Graphic may be on sketchLayer if edit was active
    if (incomingCount === 0) {
      try { this.graphicsEditor?.cancel(); } catch { }
      this.sketchLayer?.graphics?.removeAll();
    }

    this.featureLayer.removeAll();
    this.labelLayer?.removeAll();

    const fsInfo = this.getUpGISJson(newGeojson);
    if (!fsInfo) return;

    for (const graphic of fsInfo.graphics) {
      this.featureLayer.add(graphic);
    }

    console.log('[arc-geojson-layer] updateGeojson DONE, name:', this.name,
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

    const info = parsed.parsedJson;
    this.featureLayer.graphics.forEach((graphic: Graphic) => {
      graphic.popupTemplate = this.buildPopupTemplate(info);
    });
  }

  updateLabelJson(newLabelJsonArg: string | object | object[]): void {
    this.labelJson = newLabelJsonArg;
    this.refreshLabels();
  }

  updateLayerClass(newLayerClass: string): void {
    this.layerClass = newLayerClass;
    if (this.featureLayer) (this.featureLayer as any).className = newLayerClass;
    if (this.labelLayer) (this.labelLayer as any).className = `${newLayerClass}-labels`;
  }

  updateRenderer(newRenderer: any): void {
    this.renderer = newRenderer;
    if (!this.featureLayer) return;

    let parsedRenderer: any | undefined;
    const parsed = ArcGeojsonLayer.parseJson(newRenderer);

    if (parsed.parsedJson) {
      try {
        parsedRenderer = rendererJsonUtils.fromJSON(parsed.parsedJson);
      } catch {
        parsedRenderer = undefined;
      }
    }

    this.featureLayer.graphics.forEach((graphic: Graphic) => {
      if (parsedRenderer?.getSymbol) {
        try {
          graphic.symbol = parsedRenderer.getSymbol(graphic);
          return;
        } catch { }
      }
      graphic.symbol = this.getDefaultSymbolForGeometry(graphic.geometry);
    });
  }

  // ── startDrawing ──────────────────────────────────────────────────────────

  async startDrawing(drawGeometryType: string): Promise<void> {
    if (!this.featureLayer || !this.view) return;

    console.log('[arc-geojson-layer] startDrawing:', drawGeometryType, 'name:', this.name);

    this._isStartingDraw = true;

    // FIX: cancel active editor first
    try { this.graphicsEditor?.cancel(); } catch { }

    // FIX: clear ALL layers — graphic may be on sketchLayer if edit was active
    this.featureLayer.removeAll();
    this.labelLayer?.removeAll();
    this.sketchLayer?.graphics?.removeAll();

    this._isStartingDraw = false;

    this.inDrawingMode = true;
    this.enableUserEdit = false;
    this.enableInfoPopupWindow(false);

    // FIX: recreate editor fresh on every draw
    // SketchViewModel gets stuck after completing a draw
    await this.createEditor();

    // FIX: 50ms pause — ensures MapView is ready to accept sketch input
    await new Promise<void>(r => setTimeout(r, 50));

    const tool = this.toSketchCreateTool(drawGeometryType);
    console.log('[arc-geojson-layer] creating sketch tool:', tool);

    try {
      this.graphicsEditor.create(tool);
      console.log('[arc-geojson-layer] state after create:', this.graphicsEditor.state);

      if (this.graphicsEditor.state !== 'active') {
        console.warn('[arc-geojson-layer] editor stuck, recreating');
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
    if (!this.enableUserEdit) return;
    if (!this.graphicsEditor) return;

    this.enableInfoPopupWindow(false);

    // FIX: cancel active state before updating
    if (this.graphicsEditor.state === 'active') {
      try { this.graphicsEditor.cancel(); } catch { }
    }

    // FIX: move graphic from featureLayer to sketchLayer
    // so SketchViewModel can control it independently
    this.featureLayer.remove(graphic);
    if (!graphic.symbol) graphic.symbol = this.getDefaultSymbolForGeometry(graphic.geometry);
    this.sketchLayer.add(graphic);

    const updateOptions: any = {
      tool: this.resolveUpdateTool(),
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      multipleSelectionEnabled: false,
      toggleToolOnClick: false
    };

    try {
      this.graphicsEditor.update([graphic], updateOptions);
      console.log('[arc-geojson-layer] editor activated, state:', this.graphicsEditor.state);
    } catch (e: any) {
      console.warn('[arc-geojson-layer] activateGraphicsEditor error:', e?.message);
      // Restore graphic on error
      this.sketchLayer.remove(graphic);
      this.featureLayer.add(graphic);
    }
  }

  // ── Public methods ────────────────────────────────────────────────────────

  async findFeatureByUniqueId(uniqueId: string | number): Promise<Graphic | undefined> {
    return this.featureLayer?.graphics.find(
      (graphic: Graphic) => graphic.attributes?.[this.uniqueIdPropertyName] === uniqueId
    );
  }

  async getLayerId(): Promise<string> {
    return this.featureLayer?.id ?? 'arc-geojson-layer';
  }

  async openPopup(id: string | number): Promise<void> {
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic || !graphic.geometry) return;
    const popupPoint = ArcGeojsonLayer.getPopupPoint(graphic.geometry);
    this.showGraphicPopup(graphic, popupPoint);
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
      const extent = geometry.extent;
      if (extent) await this.view.goTo(extent.expand(1.5));
    }
  }

  enableInfoPopupWindow(enable: boolean): void {
    const enablePopup = enable && !this.inDrawingMode;
    if (!enablePopup && this.view?.popup?.visible) {
      this.view.popup.close();
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  private getUpGISJson(
    geojson: string | object
  ): { graphics: Graphic[]; geometryType?: string } | null {
    const result = ArcGeojsonLayer.parseJson<FeatureCollection>(geojson);
    if (!result.parsedJson || result.parsedJson.type !== 'FeatureCollection') return null;

    const graphics: Graphic[] = [];
    let geometryType: string | undefined;

    result.parsedJson.features.forEach((feature: Feature, index: number) => {
      const graphic = this.geojsonFeatureToGraphic(feature, index);
      if (graphic) {
        if (!graphic.geometry) return;
        if (geometryType === undefined) geometryType = graphic.geometry.type;
        graphics.push(graphic);
      }
    });

    return { graphics, geometryType };
  }

  private geojsonFeatureToGraphic(feature: Feature, index: number): Graphic | null {
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
        return new Point({ x: points[0][0], y: points[0][1], spatialReference: { wkid: 4326 } });
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
        const firstPolygon = (geometry.coordinates as number[][][][])[0];
        if (!firstPolygon) return null;
        return new Polygon({ rings: firstPolygon, spatialReference: { wkid: 4326 } });
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
        .filter((f: Feature | null): f is Feature => f !== null)
    };
  }

  private addToGeojson(newGraphic: Graphic): void {
    if (this._isStartingDraw) return;
    if (!newGraphic.attributes) newGraphic.attributes = {};

    if (newGraphic.attributes[this.uniqueIdPropertyName] === undefined) {
      newGraphic.attributes[this.uniqueIdPropertyName] = Date.now();
    }
    if (newGraphic.attributes.OBJECTID === undefined) {
      newGraphic.attributes.OBJECTID = Date.now();
    }

    newGraphic.symbol = this.getDefaultSymbolForGeometry(newGraphic.geometry);
    newGraphic.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic: newGraphic,
      infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName,
      fallbackTitle: this.name || 'Details'
    });

    if (!this.featureLayer.graphics.includes(newGraphic)) {
      this.featureLayer.add(newGraphic);
    }

    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();
    this.blockGeoJsonUpdate = false;

    this.refreshLabels();
    this.emitLayerEvent('userDrawItemAdded', this.graphicToGeoJsonFeature(newGraphic));

    console.log('[arc-geojson-layer] addToGeojson DONE, graphics:',
      this.featureLayer.graphics.length);
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
    if (!graphicToUpdate?.geometry) {
      console.warn('[arc-geojson-layer] updateGeojsonWithChanges: no geometry');
      return;
    }

    graphicToUpdate.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
      graphic: graphicToUpdate,
      infoTemplate: this.infoTemplate,
      uniqueIdPropertyName: this.uniqueIdPropertyName,
      fallbackTitle: this.name || 'Details'
    });

    this.blockGeoJsonUpdate = true;
    this.geojson = this.toFeatureCollectionFromLayer();
    this.blockGeoJsonUpdate = false;

    this.refreshLabels();

    const feature = this.graphicToGeoJsonFeature(graphicToUpdate);
    if (!feature?.geometry) {
      console.warn('[arc-geojson-layer] updateGeojsonWithChanges: feature geometry null');
      return;
    }
    this.emitLayerEvent('userEditItemUpdated', feature);
  }

  private buildPopupTemplate(info: InfoTemplateDetails): PopupTemplate {
    return new PopupTemplate({
      title: (event: any) => {
        const graphic = event?.graphic ?? event;
        return typeof info.listItem === 'function' ? info.listItem(graphic) : info.listItem;
      },
      content: (event: any) => {
        const graphic = event?.graphic ?? event;
        return typeof info.details === 'function' ? info.details(graphic) : info.details;
      }
    });
  }

  private buildPopupTemplateFromCurrent(graphic: Graphic): PopupTemplate | null {
    const parsed = ArcGeojsonLayer.parseJson<InfoTemplateDetails>(this.infoTemplate);
    if (!parsed.parsedJson) return null;
    const info = parsed.parsedJson;
    const title = typeof info.listItem === 'function' ? info.listItem(graphic) : info.listItem;
    const content = typeof info.details === 'function' ? info.details(graphic) : info.details;
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

  private refreshLabels(): void {
    if (!this.labelLayer) return;
    this.labelLayer.removeAll();

    const labelColor = JsonUtils.resolveLabelColor(this.labelColor);
    const labelSize = JsonUtils.resolveLabelSize(this.labelSize);

    this.featureLayer.graphics.forEach((graphic: Graphic) => {
      const label = graphic.attributes?.LABEL;
      if (!label || !graphic.geometry) return;
      const labelPoint = ArcGeojsonLayer.getPopupPoint(graphic.geometry);

      this.labelLayer.add(new Graphic({
        geometry: labelPoint,
        attributes: { __labelFor: graphic.attributes?.[this.uniqueIdPropertyName] },
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

  private getDefaultSymbolForGeometry(geometry: Geometry): any {
    const symbolJson = JsonUtils.getJsonSymbolFor(
      geometry.type,
      this.DEFAULT_SYMBOL_COLOR,
      ArcGeojsonLayer.DEFAULT_SYMBOL_MARKER_SIZE
    ) as any;

    const symbol = symbolJson?.symbol;
    if (!symbol) return null;

    try {
      if (symbol.type === 'esriSMS' || geometry.type === 'point') {
        return SimpleMarkerSymbol.fromJSON(symbol);
      }
      if (symbol.type === 'esriSLS' || geometry.type === 'polyline') {
        return SimpleLineSymbol.fromJSON(symbol);
      }
      return SimpleFillSymbol.fromJSON(symbol);
    } catch {
      if (ArcGeojsonLayer.isPoint(geometry)) {
        return new SimpleMarkerSymbol({
          style: 'circle',
          size: ArcGeojsonLayer.DEFAULT_SYMBOL_MARKER_SIZE,
          color: this.DEFAULT_SYMBOL_COLOR as any,
          outline: { color: [0, 0, 0, 200] as any, width: 1 }
        });
      }
      if (ArcGeojsonLayer.isPolyline(geometry)) {
        return new SimpleLineSymbol({
          style: 'solid',
          width: ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH,
          color: this.DEFAULT_SYMBOL_COLOR as any
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
          color: [110, 110, 110, 255] as any,
          width: ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH
        }
      });
    }
  }

  // ── Geometry helpers ──────────────────────────────────────────────────────

  private determineExistingGeometryType(): string | undefined {
    return this.featureLayer?.graphics?.getItemAt(0)?.geometry?.type;
  }

  private validGeometryType(drawGeometryType: string, featureLayerGeometryType: string): boolean {
    return this.determineFeatureLayerGeometryType(drawGeometryType) === featureLayerGeometryType;
  }

  private determineFeatureLayerGeometryType(drawGeometryType: string): string {
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
    if (this.enableUserEditVertices || this.enableUserEditAddVertices || this.enableUserEditDeleteVertices) {
      return 'reshape';
    }
    if (this.enableUserEditScaling || this.enableUserEditRotating) return 'transform';
    return 'move';
  }

  private toGeographicPoint(point: Point): Point {
    return point.spatialReference?.isWGS84
      ? point
      : (webMercatorUtils.webMercatorToGeographic(point) as Point);
  }

  private toGeographicPolyline(polyline: Polyline): Polyline {
    return polyline.spatialReference?.isWGS84
      ? polyline
      : (webMercatorUtils.webMercatorToGeographic(polyline) as Polyline);
  }

  private toGeographicPolygon(polygon: Polygon): Polygon {
    return polygon.spatialReference?.isWGS84
      ? polygon
      : (webMercatorUtils.webMercatorToGeographic(polygon) as Polygon);
  }

  private buildMouseEvent(graphic: Graphic, mapPoint: Point | null): LayerMouseEvent {
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
    this.dispatchEvent(new CustomEvent(name, { detail, bubbles: true, composed: true }));
  }

  // FIX: check both featureLayer AND sketchLayer for hit results
  private getLayerGraphicFromHit(hit: any): Graphic | undefined {
    const result = hit?.results?.find(
      (r: any) => r.graphic?.layer === this.featureLayer ||
                  r.graphic?.layer === this.sketchLayer
    );
    return result?.graphic as Graphic | undefined;
  }

  private getGraphicUniqueId(graphic: Graphic): string | number | undefined {
    return graphic.attributes?.[this.uniqueIdPropertyName] ?? graphic.attributes?.OBJECTID;
  }

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
      const polyline = geometry as Polyline;
      const path = polyline.paths?.[0] ?? [];
      const mid = Math.floor(path.length / 2);
      return new Point({
        x: path[mid]?.[0] ?? 0, y: path[mid]?.[1] ?? 0,
        spatialReference: polyline.spatialReference
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
