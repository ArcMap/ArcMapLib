import { LitElement, html } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import type { PropertyValues } from 'lit';

import Graphic from '@arcgis/core/Graphic';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer';
import SketchViewModel from '@arcgis/core/widgets/Sketch/SketchViewModel';
import SimpleRenderer from '@arcgis/core/renderers/SimpleRenderer';
import SimpleMarkerSymbol from '@arcgis/core/symbols/SimpleMarkerSymbol';
import SimpleLineSymbol from '@arcgis/core/symbols/SimpleLineSymbol';
import SimpleFillSymbol from '@arcgis/core/symbols/SimpleFillSymbol';
import PopupTemplate from '@arcgis/core/PopupTemplate';
import Point from '@arcgis/core/geometry/Point';
import Multipoint from '@arcgis/core/geometry/Multipoint';
import Polyline from '@arcgis/core/geometry/Polyline';
import Polygon from '@arcgis/core/geometry/Polygon';
import * as webMercatorUtils from '@arcgis/core/geometry/support/webMercatorUtils';
import Handles from '@arcgis/core/core/Handles';
import type MapView from '@arcgis/core/views/MapView';
import type Geometry from '@arcgis/core/geometry/Geometry';

// ------------------------------------------------------------------
// TYPES
// ------------------------------------------------------------------
type DrawTool =
  | 'point' | 'multipoint' | 'polyline' | 'polygon'
  | 'rectangle' | 'circle' | 'freehand_polyline' | 'freehand_polygon'
  | 'triangle' | 'arrow' | 'left_arrow' | 'right_arrow'
  | 'up_arrow' | 'down_arrow' | 'extent' | null;

type GeoJsonPoint        = { type: 'Point';           coordinates: number[]       };
type GeoJsonMultiPoint   = { type: 'MultiPoint';       coordinates: number[][]     };
type GeoJsonLineString   = { type: 'LineString';       coordinates: number[][]     };
type GeoJsonMultiLine    = { type: 'MultiLineString';  coordinates: number[][][]   };
type GeoJsonPolygon      = { type: 'Polygon';          coordinates: number[][][]   };
type GeoJsonMultiPolygon = { type: 'MultiPolygon';     coordinates: number[][][][] };

type GeoJsonGeometry =
  | GeoJsonPoint | GeoJsonMultiPoint
  | GeoJsonLineString | GeoJsonMultiLine
  | GeoJsonPolygon | GeoJsonMultiPolygon;

type GeoJsonFeature = {
  type: 'Feature';
  id?: string | number;
  geometry: GeoJsonGeometry | null;
  properties?: Record<string, any>;
};

type GeoJsonFeatureCollection = {
  type: 'FeatureCollection';
  features: GeoJsonFeature[];
};

type PopupInput =
  | null
  | string
  | { title?: string; content?: string; details?: string };

// ------------------------------------------------------------------
// COMPONENT
// ------------------------------------------------------------------
@customElement('arc-geojson-layer')
export class ArcGeoJsonLayer extends LitElement {

  // ----------------------------------------------------------------
  // PUBLIC API
  // ----------------------------------------------------------------
  @property({ type: Object })
  geojson: GeoJsonFeatureCollection | string | null = null;

  @property({ attribute: 'unique-id-property-name' })
  uniqueIdPropertyName = 'id';

  @property({ type: Boolean, attribute: 'enable-user-edit' })
  enableUserEdit = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-add-vertices' })
  enableUserEditAddVertices = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-delete-vertices' })
  enableUserEditDeleteVertices = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-move' })
  enableUserEditMove = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-remove' })
  enableUserEditRemove = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-rotating' })
  enableUserEditRotating = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-scaling' })
  enableUserEditScaling = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-uniform-scaling' })
  enableUserEditUniformScaling = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-vertices' })
  enableUserEditVertices = false;

  @property({ type: Object })
  renderer: any = null;

  @property({ type: Object })
  infoTemplate: PopupInput = null;

  // ----------------------------------------------------------------
  // INTERNAL STATE
  // ----------------------------------------------------------------
  @state() private ready = false;

  private ancestorMap: any = null;
  private view: MapView | null = null;
  private handles = new Handles();

  // TWO separate GraphicsLayers:
  // displayLayer  — holds the committed GeoJSON graphics (hittable, popup)
  // sketchLayer   — holds the temporary editing graphic (SVM only)
  private displayLayer: GraphicsLayer | null = null;
  private sketchLayer: GraphicsLayer | null = null;
  private sketchVM: SketchViewModel | null = null;

  private inDrawingMode = false;
  private editorActive = false;
  private editActivationInProgress = false;
  private editingUniqueId: string | number | null = null;
  private popupTemplate: PopupTemplate | null = null;

  // ----------------------------------------------------------------
  // LIFECYCLE
  // ----------------------------------------------------------------
  override connectedCallback(): void {
    super.connectedCallback();
    void this.bootstrap();
  }

  override async firstUpdated(): Promise<void> {
    await this.bootstrap();
  }

  override async updated(changed: PropertyValues<this>): Promise<void> {
    if (changed.has('geojson')) {
      this.refreshDisplayLayer();
    }
    if (changed.has('infoTemplate')) {
      this.buildPopupTemplate();
      this.refreshDisplayLayer();
    }
    if (changed.has('renderer')) {
      this.refreshDisplayLayer();
    }
    if (
      changed.has('enableUserEditRotating') ||
      changed.has('enableUserEditScaling') ||
      changed.has('enableUserEditUniformScaling')
    ) {
      this.syncSvmOptions();
    }
  }

  override disconnectedCallback(): void {
    super.disconnectedCallback();
    this.handles.removeAll();
    this.sketchVM?.cancel();
    this.sketchVM?.destroy();
    this.sketchVM = null;
    if (this.view) {
      if (this.displayLayer) this.view.map?.remove(this.displayLayer);
      if (this.sketchLayer)  this.view.map?.remove(this.sketchLayer);
    }
    this.displayLayer?.destroy();
    this.sketchLayer?.destroy();
    this.displayLayer = null;
    this.sketchLayer = null;
  }

  protected override render() { return html``; }

  // ----------------------------------------------------------------
  // BOOTSTRAP
  // ----------------------------------------------------------------
  private async bootstrap(): Promise<void> {
    if (this.ready) return;

    await this.resolveView();
    if (!this.view) return;

    // display layer — all committed graphics live here
    this.displayLayer = new GraphicsLayer({ listMode: 'show' });
    this.view.map?.add(this.displayLayer);

    // sketch layer — only the graphic being edited lives here
    this.sketchLayer = new GraphicsLayer({ listMode: 'hide' });
    this.view.map?.add(this.sketchLayer);

    this.sketchVM = new SketchViewModel({
      view: this.view,
      layer: this.sketchLayer,
      defaultUpdateOptions: {
        enableRotation: this.enableUserEditRotating,
        enableScaling: this.enableUserEditScaling,
        preserveAspectRatio: this.enableUserEditUniformScaling,
        toggleToolOnClick: false,
        multipleSelectionEnabled: false
      }
    });

    this.buildPopupTemplate();
    this.refreshDisplayLayer();
    this.registerSketchHandlers();
    this.registerMapEvents();

    this.ready = true;
  }

  private async resolveView(): Promise<void> {
    this.ancestorMap = this.closest('arc-map') as any;
    if (!this.ancestorMap) {
      console.error('<arc-geojson-layer> must be inside <arc-map>');
      return;
    }
    if (typeof this.ancestorMap.getInstance === 'function') {
      this.view = await this.ancestorMap.getInstance();
    } else {
      this.view = this.ancestorMap.view ?? null;
    }
    if (!this.view) {
      console.error('Could not resolve MapView from <arc-map>');
      return;
    }
    if (typeof (this.view as any).when === 'function') {
      await (this.view as any).when();
    }
  }

  // ----------------------------------------------------------------
  // DISPLAY LAYER — rebuild from geojson
  // ----------------------------------------------------------------
  private refreshDisplayLayer(): void {
    if (!this.displayLayer) return;
    // Never wipe display layer while editor is active
    if (this.editorActive) return;

    this.displayLayer.removeAll();

    const fc = this.parseFC(this.geojson);
    if (!fc) return;

    fc.features.forEach((feature, index) => {
      const g = this.featureToGraphic(feature, index);
      if (g) this.displayLayer!.add(g);
    });
  }

  private featureToGraphic(feature: GeoJsonFeature, index: number): Graphic | null {
    if (!feature.geometry) return null;

    const geometry = this.toArcGisGeometry(feature.geometry);
    if (!geometry) return null;

    const attributes: Record<string, any> = { ...(feature.properties ?? {}) };
    if (attributes[this.uniqueIdPropertyName] == null) {
      attributes[this.uniqueIdPropertyName] = feature.id ?? `feature-${index}`;
    }

    const symbol = this.symbolForGeometry(geometry.type);

    return new Graphic({
      geometry,
      attributes,
      symbol,
      popupTemplate: this.enableUserEdit ? undefined : (this.popupTemplate ?? undefined)
    });
  }

  // ----------------------------------------------------------------
  // SKETCH HANDLERS
  // ----------------------------------------------------------------
  private registerSketchHandlers(): void {
    if (!this.sketchVM) return;

    // ---- CREATE complete ----
    this.handles.add(
      this.sketchVM.on('create', async (event: any) => {
        if (event.state !== 'complete' || !event.graphic) return;

        const g = event.graphic;
        g.popupTemplate = null;
        if (!g.attributes) g.attributes = {};
        if (g.attributes[this.uniqueIdPropertyName] == null) {
          g.attributes[this.uniqueIdPropertyName] =
            crypto.randomUUID?.() ?? `id-${Date.now()}`;
        }

        // 1. clear sketch layer first
        this.sketchLayer?.removeAll();
        this.inDrawingMode = false;

        // 2. persist to geojson
        const feature = this.graphicToFeature(g);
        await this.appendFeature(feature);

        // 3. refreshDisplayLayer is called by appendFeature via geojson setter

        this.dispatchEvent(new CustomEvent('userDrawItemAdded', {
          detail: feature, bubbles: true, composed: true
        }));
      }),
      'sketch-create'
    );

    // ---- UPDATE ----
    this.handles.add(
      this.sketchVM.on('update', async (event: any) => {
        if (event.state === 'start') {
          // hide the display graphic so we don't see double
          this.hideDisplayGraphic(this.editingUniqueId);
          return;
        }

        if (event.state === 'cancel' || event.state === 'complete') {
          // restore display graphic regardless
          this.refreshDisplayLayer();
          this.sketchLayer?.removeAll();
          this.editorActive = false;
          this.editingUniqueId = null;

          if (event.state === 'cancel') return;
          if (!event.graphics?.length) return;

          const g = event.graphics[0];
          g.popupTemplate = null;
          const feature = this.graphicToFeature(g);

          if (this.editingUniqueId != null) {
            (feature.properties as any)[this.uniqueIdPropertyName] = this.editingUniqueId;
          }

          await this.updateFeature(feature);

          this.dispatchEvent(new CustomEvent('userEditItemUpdated', {
            detail: feature, bubbles: true, composed: true
          }));
        }
      }),
      'sketch-update'
    );
  }

  // ----------------------------------------------------------------
  // MAP EVENTS
  // ----------------------------------------------------------------
  private registerMapEvents(): void {
    if (!this.view) return;

    // single click
    this.handles.add(
      this.view.on('click', async (event: any) => {
        if (!this.view || this.inDrawingMode || this.editorActive) return;

        const hit = await this.view.hitTest(event);
        const result = (hit.results ?? []).find((r: any) =>
          r?.type === 'graphic' && r?.graphic?.layer === this.displayLayer
        ) as any;

        const graphic = result?.graphic as Graphic | undefined;
        if (!graphic) return;

        const uniqueId = graphic.attributes?.[this.uniqueIdPropertyName];
        const nativeEvent = event?.native ?? event;

        // ctrl/cmd + click = remove
        if (
          this.enableUserEdit &&
          this.enableUserEditRemove &&
          (nativeEvent?.ctrlKey || nativeEvent?.metaKey)
        ) {
          await this.removeById(uniqueId);
          return;
        }

        // edit mode: no popup on single click
        if (this.enableUserEdit) return;

        // view mode: popup
        const location = event.mapPoint ?? this.getPopupCenter(graphic.geometry);
        if (location) {
          (this.view as any).openPopup?.({ features: [graphic], location });
        }

        this.dispatchEvent(new CustomEvent('layerClick', {
          detail: { graphic, uniqueId, attributes: graphic.attributes ?? {} },
          bubbles: true, composed: true
        }));
      }),
      'view-click'
    );

    // native dblclick
    const container = this.view.container as HTMLElement | null;
    if (!container) return;

    const onDblClick = async (evt: MouseEvent) => {
      if (!this.view || this.inDrawingMode) return;
      if (this.editActivationInProgress || this.editorActive) return;

      evt.preventDefault();
      evt.stopPropagation();

      if (!this.enableUserEdit) return;

      const rect = container.getBoundingClientRect();
      const hit = await this.view.hitTest({
        x: evt.clientX - rect.left,
        y: evt.clientY - rect.top
      } as any);

      const result = (hit.results ?? []).find((r: any) =>
        r?.type === 'graphic' && r?.graphic?.layer === this.displayLayer
      ) as any;

      if (!result?.graphic) return;

      this.editActivationInProgress = true;
      try {
        await this.activateEditor(result.graphic as Graphic);
      } catch (err) {
        console.error('Editor activation failed', err);
        this.editorActive = false;
      } finally {
        this.editActivationInProgress = false;
      }
    };

    container.addEventListener('dblclick', onDblClick);
    this.handles.add(
      { remove: () => container.removeEventListener('dblclick', onDblClick) },
      'native-dblclick'
    );
  }

  // ----------------------------------------------------------------
  // ACTIVATE EDITOR
  // The KEY fix: build a completely detached Graphic with only geometry
  // and attributes — zero connection to any layer.
  // ----------------------------------------------------------------
  private async activateEditor(displayGraphic: Graphic): Promise<void> {
    if (!this.sketchVM || !this.sketchLayer) return;
    if (this.editorActive) return;

    this.editingUniqueId =
      displayGraphic.attributes?.[this.uniqueIdPropertyName] ?? null;

    // cancel any in-progress sketch silently
    this.sketchVM.cancel();
    this.sketchLayer.removeAll();

    const updateTool = this.getUpdateTool();
    if (!updateTool) {
      console.warn(
        'No update tool configured. Enable at least one of: ' +
        'enableUserEditMove, enableUserEditVertices, enableUserEditScaling.'
      );
      return;
    }

    // Build a DETACHED graphic — no .layer, no .popupTemplate, no symbol ref issues
    const detached = new Graphic({
      geometry: displayGraphic.geometry.clone(),
      attributes: { ...(displayGraphic.attributes ?? {}) },
      symbol: displayGraphic.symbol
        ? displayGraphic.symbol.clone()
        : this.symbolForGeometry(displayGraphic.geometry.type)
    });

    this.sketchLayer.add(detached);

    // Hide the display copy so we don't see the original underneath
    this.hideDisplayGraphic(this.editingUniqueId);

    // Give the sketch layer one render tick
    await new Promise<void>((resolve) => setTimeout(resolve, 30));

    this.editorActive = true;

    this.sketchVM.update([detached], {
      tool: updateTool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
      multipleSelectionEnabled: false
    });
  }

  // hide a display graphic by id without removing it
  // (we restore it via refreshDisplayLayer on update complete/cancel)
  private hideDisplayGraphic(uniqueId: string | number | null): void {
    if (!this.displayLayer || uniqueId == null) return;
    const g = this.findDisplayGraphic(uniqueId);
    if (g) (g as any).visible = false;
  }

  private findDisplayGraphic(uniqueId: string | number): Graphic | undefined {
    return this.displayLayer?.graphics
      .toArray()
      .find(g => g.attributes?.[this.uniqueIdPropertyName] === uniqueId);
  }

  // ----------------------------------------------------------------
  // SVM OPTIONS SYNC
  // ----------------------------------------------------------------
  private syncSvmOptions(): void {
    if (!this.sketchVM) return;
    this.sketchVM.defaultUpdateOptions = {
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
      multipleSelectionEnabled: false
    };
  }

  private getUpdateTool(): 'reshape' | 'transform' | 'move' | null {
    if (this.enableUserEditVertices ||
        this.enableUserEditAddVertices ||
        this.enableUserEditDeleteVertices) return 'reshape';
    if (this.enableUserEditScaling || this.enableUserEditRotating) return 'transform';
    if (this.enableUserEditMove) return 'move';
    return null;
  }

  // ----------------------------------------------------------------
  // PUBLIC: START / CANCEL DRAWING
  // ----------------------------------------------------------------
  async startDrawing(drawGeometryType: string): Promise<void> {
    if (!this.sketchVM) return;
    const tool = this.toDrawTool(drawGeometryType);
    if (!tool) {
      console.error(`Unsupported geometry type: ${drawGeometryType}`);
      return;
    }
    this.sketchVM.cancel();
    this.sketchLayer?.removeAll();
    this.inDrawingMode = true;
    this.sketchVM.create(tool);
  }

  async cancelDrawing(): Promise<void> {
    this.inDrawingMode = false;
    this.sketchVM?.cancel();
    this.sketchLayer?.removeAll();
  }

  private toDrawTool(type: string): DrawTool {
    switch ((type ?? '').toLowerCase()) {
      case 'point':             return 'point';
      case 'multipoint':        return 'multipoint';
      case 'line':
      case 'polyline':
      case 'linestring':        return 'polyline';
      case 'freehand_polyline': return 'freehand_polyline';
      case 'polygon':           return 'polygon';
      case 'freehand_polygon':  return 'freehand_polygon';
      case 'triangle':          return 'triangle';
      case 'arrow':             return 'arrow';
      case 'left_arrow':        return 'left_arrow';
      case 'right_arrow':       return 'right_arrow';
      case 'up_arrow':          return 'up_arrow';
      case 'down_arrow':        return 'down_arrow';
      case 'rectangle':
      case 'extent':            return 'rectangle';
      case 'circle':
      case 'ellipse':           return 'circle';
      default:                  return null;
    }
  }

  // ----------------------------------------------------------------
  // REMOVE BY ID
  // ----------------------------------------------------------------
  async removeById(id: string | number): Promise<void> {
    const fc = this.parseFC(this.geojson);
    if (!fc) return;

    const removed = fc.features.find(f =>
      (f.properties?.[this.uniqueIdPropertyName] ?? f.id) === id
    );
    if (!removed) return;

    fc.features = fc.features.filter(f =>
      (f.properties?.[this.uniqueIdPropertyName] ?? f.id) !== id
    );

    this.geojson = { ...fc };
    this.refreshDisplayLayer();

    this.dispatchEvent(new CustomEvent('userEditItemRemoved', {
      detail: removed, bubbles: true, composed: true
    }));
  }

  // ----------------------------------------------------------------
  // PUBLIC HELPERS
  // ----------------------------------------------------------------
  async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {
    if (!this.view) return;
    const g = this.findDisplayGraphic(id);
    if (!g?.geometry) return;
    if (g.geometry.type === 'point') {
      await this.view.goTo({ target: g.geometry, zoom: zoomLevel });
    } else {
      await this.view.goTo((g.geometry as any).extent ?? g.geometry);
    }
  }

  async openPopupById(id: string | number): Promise<void> {
    if (!this.view) return;
    const g = this.findDisplayGraphic(id);
    if (!g) return;
    const location = this.getPopupCenter(g.geometry);
    if (location) {
      (this.view as any).openPopup?.({ features: [g], location });
    }
  }

  // ----------------------------------------------------------------
  // POPUP TEMPLATE
  // ----------------------------------------------------------------
  private buildPopupTemplate(): void {
    if (!this.infoTemplate) {
      this.popupTemplate = null;
      return;
    }
    if (typeof this.infoTemplate === 'string') {
      this.popupTemplate = new PopupTemplate({ title: 'Details', content: this.infoTemplate });
    } else {
      this.popupTemplate = new PopupTemplate({
        title: this.infoTemplate.title ?? 'Details',
        content: this.infoTemplate.content ?? this.infoTemplate.details ?? ''
      });
    }
  }

  private getPopupCenter(geometry: any): Point | null {
    if (!geometry) return null;
    if (geometry.type === 'point') return geometry as Point;
    return (geometry as any).extent?.center ?? null;
  }

  // ----------------------------------------------------------------
  // SYMBOLS
  // ----------------------------------------------------------------
  private symbolForGeometry(geometryType: string): any {
    if (this.renderer?.type === 'simple' && this.renderer?.symbol) {
      return this.renderer.symbol;
    }
    switch (geometryType) {
      case 'point':
      case 'multipoint':
        return new SimpleMarkerSymbol({ size: 10, outline: { width: 1 } });
      case 'polyline':
        return new SimpleLineSymbol({ width: 2, color: [0, 0, 0, 1] });
      default:
        return new SimpleFillSymbol({
          color: [173, 216, 230, 0.35],
          outline: { color: [0, 0, 0, 1], width: 2 }
        });
    }
  }

  // ----------------------------------------------------------------
  // GEOJSON PERSISTENCE
  // ----------------------------------------------------------------
  private async appendFeature(feature: GeoJsonFeature): Promise<void> {
    const fc = this.parseFC(this.geojson) ?? { type: 'FeatureCollection', features: [] };
    this.geojson = { ...fc, features: [...fc.features, feature] };
    this.refreshDisplayLayer();
  }

  private async updateFeature(updatedFeature: GeoJsonFeature): Promise<void> {
    const fc = this.parseFC(this.geojson);
    if (!fc) return;

    const updatedId =
      updatedFeature.properties?.[this.uniqueIdPropertyName] ?? updatedFeature.id;

    fc.features = fc.features.map(f => {
      const fId = f.properties?.[this.uniqueIdPropertyName] ?? f.id;
      return fId === updatedId ? updatedFeature : f;
    });

    this.geojson = { ...fc };
    this.refreshDisplayLayer();
  }

  private parseFC(
    input: string | GeoJsonFeatureCollection | null | undefined
  ): GeoJsonFeatureCollection | null {
    if (!input) return null;
    try {
      const p = typeof input === 'string' ? JSON.parse(input) : input;
      if (p?.type === 'FeatureCollection' && Array.isArray(p.features)) return p;
    } catch { /* ignore */ }
    return null;
  }

  private graphicToFeature(graphic: Graphic): GeoJsonFeature {
    const properties = { ...(graphic.attributes ?? {}) };
    if (properties[this.uniqueIdPropertyName] == null) {
      properties[this.uniqueIdPropertyName] =
        crypto.randomUUID?.() ?? `id-${Date.now()}`;
    }
    return {
      type: 'Feature',
      geometry: this.arcGisToGeoJson(graphic.geometry),
      properties
    } as GeoJsonFeature;
  }

  private arcGisToGeoJson(geometry: any): GeoJsonGeometry | null {
    const geo = webMercatorUtils.canProject(geometry, { wkid: 4326 } as any)
      ? webMercatorUtils.webMercatorToGeographic(geometry) as Geometry
      : geometry;

    if (geo instanceof Point) {
      return { type: 'Point', coordinates: [geo.longitude ?? geo.x, geo.latitude ?? geo.y] };
    }
    if (geo instanceof Multipoint) {
      return { type: 'MultiPoint', coordinates: geo.points.map(p => [p[0], p[1]]) };
    }
    if (geo instanceof Polyline) {
      const paths = geo.paths ?? [];
      return paths.length === 1
        ? { type: 'LineString',      coordinates: paths[0].map(p => [p[0], p[1]]) }
        : { type: 'MultiLineString', coordinates: paths.map(path => path.map(p => [p[0], p[1]])) };
    }
    if (geo instanceof Polygon) {
      return { type: 'Polygon', coordinates: geo.rings.map(ring => ring.map(p => [p[0], p[1]])) };
    }
    return null;
  }

  private toArcGisGeometry(geometry: GeoJsonGeometry): Geometry | null {
    switch (geometry.type) {
      case 'Point':
        return new Point({ x: geometry.coordinates[0], y: geometry.coordinates[1], spatialReference: { wkid: 4326 } });
      case 'MultiPoint':
        return new Multipoint({ points: geometry.coordinates, spatialReference: { wkid: 4326 } });
      case 'LineString':
        return new Polyline({ paths: [geometry.coordinates], spatialReference: { wkid: 4326 } });
      case 'MultiLineString':
        return new Polyline({ paths: geometry.coordinates, spatialReference: { wkid: 4326 } });
      case 'Polygon': {
        const rings = geometry.coordinates.map(ring => {
          const f = ring[0]; const l = ring[ring.length - 1];
          return (f[0] !== l[0] || f[1] !== l[1]) ? [...ring, [...f]] : ring;
        });
        return new Polygon({ rings, spatialReference: { wkid: 4326 } });
      }
      case 'MultiPolygon': {
        const rings: number[][][] = [];
        for (const poly of geometry.coordinates) {
          for (const ring of poly) {
            const f = ring[0]; const l = ring[ring.length - 1];
            rings.push((f[0] !== l[0] || f[1] !== l[1]) ? [...ring, [...f]] : ring);
          }
        }
        return new Polygon({ rings, spatialReference: { wkid: 4326 } });
      }
      default: return null;
    }
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'arc-geojson-layer': ArcGeoJsonLayer;
  }
}
