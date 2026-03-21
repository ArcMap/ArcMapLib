import { LitElement, html } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';

import Graphic from '@arcgis/core/Graphic';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer';
import PopupTemplate from '@arcgis/core/PopupTemplate';
import SketchViewModel from '@arcgis/core/widgets/Sketch/SketchViewModel';
import Handles from '@arcgis/core/core/Handles';

import Point from '@arcgis/core/geometry/Point';
import Polyline from '@arcgis/core/geometry/Polyline';
import Polygon from '@arcgis/core/geometry/Polygon';
import Multipoint from '@arcgis/core/geometry/Multipoint';
import Extent from '@arcgis/core/geometry/Extent';

import SimpleMarkerSymbol from '@arcgis/core/symbols/SimpleMarkerSymbol';
import SimpleLineSymbol from '@arcgis/core/symbols/SimpleLineSymbol';
import SimpleFillSymbol from '@arcgis/core/symbols/SimpleFillSymbol';

type ArcGISView = __esri.MapView | __esri.SceneView;
type GeometryInput = GeoJSON.Geometry | null | undefined;
type FeatureCollectionInput = GeoJSON.FeatureCollection | string | null | undefined;
type PopupInput =
  | string
  | {
      title?: string;
      content?: string;
      details?: string;
    }
  | null
  | undefined;

type DrawTool =
  | 'point'
  | 'polyline'
  | 'polygon'
  | 'rectangle'
  | 'circle';

interface ArcMapLike extends HTMLElement {
  getViewInstance?: () => Promise<ArcGISView | null> | ArcGISView | null;
  viewOnReady?: () => Promise<void>;
  enableInfoWindow?: (enable: boolean) => void;
  __jsView?: ArcGISView | null;
  view?: ArcGISView | null;
}

@customElement('arc-geojson-layer')
export class ArcGeoJsonLayer extends LitElement {
  /**
   * ============================================================================
   * PUBLIC PROPERTIES
   * ============================================================================
   */

  @property({ attribute: false })
  geojson: FeatureCollectionInput = null;

  @property({ attribute: 'info-template' })
  infoTemplate: PopupInput = null;

  @property({ attribute: 'unique-id-property-name' })
  uniqueIdPropertyName = 'id';

  @property({ attribute: false })
  renderer?: __esri.Renderer;

  @property({ type: Boolean, attribute: 'enable-user-edit', reflect: true })
  enableUserEdit = false;

  @property({ type: Boolean, attribute: 'enable-user-edit-add-vertices', reflect: true })
  enableUserEditAddVertices = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-delete-vertices', reflect: true })
  enableUserEditDeleteVertices = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-move', reflect: true })
  enableUserEditMove = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-remove', reflect: true })
  enableUserEditRemove = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-rotating', reflect: true })
  enableUserEditRotating = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-scaling', reflect: true })
  enableUserEditScaling = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-uniform-scaling', reflect: true })
  enableUserEditUniformScaling = true;

  @property({ type: Boolean, attribute: 'enable-user-edit-vertices', reflect: true })
  enableUserEditVertices = true;

  /**
   * ============================================================================
   * EVENTS
   * ============================================================================
   */

  // Kept as DOM CustomEvents so you can listen from Angular/Vanilla/Lit easily.
  private emitLayerClick(detail: unknown): void {
    this.dispatchEvent(
      new CustomEvent('layerClick', {
        detail,
        bubbles: true,
        composed: true
      })
    );
  }

  private emitDoubleClick(detail: unknown): void {
    this.dispatchEvent(
      new CustomEvent('doubleClick', {
        detail,
        bubbles: true,
        composed: true
      })
    );
  }

  private emitUserDrawItemAdded(detail: unknown): void {
    this.dispatchEvent(
      new CustomEvent('userDrawItemAdded', {
        detail,
        bubbles: true,
        composed: true
      })
    );
  }

  private emitUserEditItemRemoved(detail: unknown): void {
    this.dispatchEvent(
      new CustomEvent('userEditItemRemoved', {
        detail,
        bubbles: true,
        composed: true
      })
    );
  }

  private emitUserEditItemUpdated(detail: unknown): void {
    this.dispatchEvent(
      new CustomEvent('userEditItemUpdated', {
        detail,
        bubbles: true,
        composed: true
      })
    );
  }

  /**
   * ============================================================================
   * INTERNAL STATE
   * ============================================================================
   */

  @state()
  private ready = false;

  private ancestorMap: ArcMapLike | null = null;
  private view: ArcGISView | null = null;
  private graphicsLayer: GraphicsLayer | null = null;
  private sketchVM: SketchViewModel | null = null;
  private popupTemplate: PopupTemplate | null = null;
  private handles = new Handles();

  private inDrawingMode = false;
  private suppressGeoJsonWatch = false;
  private clickedGraphic: __esri.Graphic | null = null;

  /**
   * ============================================================================
   * LIFECYCLE
   * ============================================================================
   */

  render() {
    return html``;
  }

  protected createRenderRoot() {
    return this;
  }

  connectedCallback(): void {
    super.connectedCallback();
    void this.bootstrap();
  }

  disconnectedCallback(): void {
    super.disconnectedCallback();
    this.handles.removeAll();
    this.sketchVM?.cancel();
    this.sketchVM?.destroy();
    this.sketchVM = null;

    if (this.view && this.graphicsLayer) {
      this.view.map?.remove(this.graphicsLayer);
    }

    this.graphicsLayer?.destroy();
    this.graphicsLayer = null;
    this.view = null;
    this.ancestorMap = null;
  }

  protected async firstUpdated(): Promise<void> {
    await this.bootstrap();
  }

  protected async updated(changed: Map<string, unknown>): Promise<void> {
    if (changed.has('infoTemplate')) {
      this.updatePopupTemplate(this.infoTemplate);
      this.applyPopupTemplateToGraphics();
    }

    if (changed.has('renderer')) {
      this.applyRenderer();
    }

    if (changed.has('geojson') && !this.suppressGeoJsonWatch) {
      await this.renderGeoJson();
    }

    if (
      changed.has('enableUserEdit') ||
      changed.has('enableUserEditAddVertices') ||
      changed.has('enableUserEditDeleteVertices') ||
      changed.has('enableUserEditMove') ||
      changed.has('enableUserEditRemove') ||
      changed.has('enableUserEditRotating') ||
      changed.has('enableUserEditScaling') ||
      changed.has('enableUserEditUniformScaling') ||
      changed.has('enableUserEditVertices')
    ) {
      this.syncEditingState();
    }
  }

  /**
   * ============================================================================
   * NEW CHANGE START: ancestor <arc-map> + view resolution
   * - This is the most important part for your project because your view lives in
   *   the parent UPMap component.
   * - If view is null, nothing else will work.
   * ============================================================================
   */

  private async bootstrap(): Promise<void> {
    if (this.ready) return;

    await this.resolveViewFromAncestor();
    if (!this.view) return;

    this.ensureGraphicsLayer();
    this.ensureSketchViewModel();
    this.updatePopupTemplate(this.infoTemplate);
    this.applyRenderer();
    this.registerLayerEvents();
    await this.renderGeoJson();
    this.syncEditingState();

    this.ready = true;
  }

  private async resolveViewFromAncestor(): Promise<void> {
    this.ancestorMap = this.closest('arc-map') as ArcMapLike | null;

    if (!this.ancestorMap) {
      console.warn('<arc-geojson-layer> must be used inside <arc-map>.');
      return;
    }

    // 1. Wait if parent exposes "viewOnReady"
    if (typeof this.ancestorMap.viewOnReady === 'function') {
      try {
        await this.ancestorMap.viewOnReady();
      } catch (error) {
        console.warn('viewOnReady() failed on ancestor arc-map.', error);
      }
    }

    // 2. getViewInstance() is preferred if your UPMap exposes it
    if (typeof this.ancestorMap.getViewInstance === 'function') {
      const maybeView = await this.ancestorMap.getViewInstance();
      if (maybeView) {
        this.view = maybeView;
        return;
      }
    }

    // 3. Fallbacks for common custom element patterns
    if (this.ancestorMap.__jsView) {
      this.view = this.ancestorMap.__jsView;
      return;
    }

    if (this.ancestorMap.view) {
      this.view = this.ancestorMap.view;
      return;
    }

    console.warn('Unable to resolve ArcGIS view from ancestor <arc-map>.');
  }

  /**
   * ============================================================================
   * NEW CHANGE END
   * ============================================================================
   */

  /**
   * ============================================================================
   * LAYER / SKETCH SETUP
   * ============================================================================
   */

  private ensureGraphicsLayer(): void {
    if (!this.view || this.graphicsLayer) return;

    this.graphicsLayer = new GraphicsLayer({
      id: this.id || `arc-geojson-layer-${crypto.randomUUID?.() ?? Date.now()}`
    });

    this.view.map?.add(this.graphicsLayer);
  }

  private ensureSketchViewModel(): void {
    if (!this.view || !this.graphicsLayer || this.sketchVM) return;

    this.sketchVM = new SketchViewModel({
      view: this.view,
      layer: this.graphicsLayer,
      defaultUpdateOptions: {
        enableRotation: this.enableUserEditRotating,
        enableScaling: this.enableUserEditScaling,
        preserveAspectRatio: this.enableUserEditUniformScaling,
        toggleToolOnClick: false,
        multipleSelectionEnabled: false
      }
    });

    this.handles.add(
      this.sketchVM.on('create', (event) => {
        if (event.state !== 'complete' || !event.graphic) return;

        this.inDrawingMode = false;
        this.applyPopupTemplateToGraphic(event.graphic);
        this.ensureUniqueId(event.graphic);
        this.emitUserDrawItemAdded(this.graphicToFeature(event.graphic));
        this.syncGeoJsonFromLayer();
        this.enableInfoPopupWindow(true);
      }),
      'sketch-create'
    );

    this.handles.add(
      this.sketchVM.on('update', (event) => {
        if (event.state !== 'complete' || !event.graphics?.length) return;

        const graphic = event.graphics[0];
        this.applyPopupTemplateToGraphic(graphic);
        this.ensureUniqueId(graphic);
        this.emitUserEditItemUpdated(this.graphicToFeature(graphic));
        this.syncGeoJsonFromLayer();
        this.enableInfoPopupWindow(true);
      }),
      'sketch-update'
    );
  }

  /**
   * ============================================================================
   * NEW CHANGE START: generic popup handling for ANY geometry type
   * ============================================================================
   */

  private registerLayerEvents(): void {
    if (!this.view || !this.graphicsLayer) return;

    this.handles.remove('layer-click');

    this.handles.add(
      this.view.on('click', async (event: __esri.ViewClickEvent) => {
        if (!this.view || !this.graphicsLayer) return;
        if (this.inDrawingMode) return;

        const hit = await this.view.hitTest(event);

        const result = (hit.results ?? []).find((r: any) => {
          return r?.type === 'graphic' && r.graphic?.layer === this.graphicsLayer;
        }) as any;

        if (!result?.graphic) return;

        const graphic = result.graphic as __esri.Graphic;
        this.clickedGraphic = graphic;

        if (this.enableUserEdit) {
          this.activateGraphicEditor(graphic);
        }

        this.applyPopupTemplateToGraphic(graphic);

        const uniqueId = graphic.attributes?.[this.uniqueIdPropertyName];
        const location = event.mapPoint ?? this.getPopupLocation(graphic.geometry);

        if (this.view.popup && graphic.popupTemplate && location) {
          this.view.popup.open({
            features: [graphic],
            location
          });
        }

        this.emitLayerClick({
          graphic,
          uniqueId,
          attributes: graphic.attributes ?? {}
        });
      }),
      'layer-click'
    );

    this.handles.remove('layer-dblclick');

    this.handles.add(
      this.view.on('double-click', async (event: __esri.ViewDoubleClickEvent) => {
        if (!this.view || !this.graphicsLayer) return;

        const hit = await this.view.hitTest(event);

        const result = (hit.results ?? []).find((r: any) => {
          return r?.type === 'graphic' && r.graphic?.layer === this.graphicsLayer;
        }) as any;

        if (!result?.graphic) return;

        this.emitDoubleClick({
          graphic: result.graphic,
          attributes: result.graphic.attributes ?? {}
        });
      }),
      'layer-dblclick'
    );
  }

  private getPopupLocation(geometry: __esri.Geometry): __esri.Point | null {
    if (!geometry) return null;

    switch (geometry.type) {
      case 'point':
        return geometry as __esri.Point;

      case 'multipoint': {
        const mp = geometry as __esri.Multipoint;
        const first = mp.points?.[0];
        if (!first) return null;
        return new Point({
          x: first[0],
          y: first[1],
          spatialReference: mp.spatialReference
        });
      }

      case 'polyline': {
        const line = geometry as __esri.Polyline;
        const path = line.paths?.[0];
        if (!path?.length) return null;
        const mid = path[Math.floor(path.length / 2)];
        return new Point({
          x: mid[0],
          y: mid[1],
          spatialReference: line.spatialReference
        });
      }

      case 'polygon': {
        const polygon = geometry as __esri.Polygon;
        return polygon.extent?.center ?? null;
      }

      case 'extent': {
        const extent = geometry as __esri.Extent;
        return extent.center ?? null;
      }

      default:
        return (geometry as any).extent?.center ?? null;
    }
  }

  /**
   * ============================================================================
   * NEW CHANGE END
   * ============================================================================
   */

  /**
   * ============================================================================
   * POPUP TEMPLATE
   * ============================================================================
   */

  private updatePopupTemplate(input: PopupInput): void {
    if (!input) {
      this.popupTemplate = null;
      return;
    }

    if (typeof input === 'string') {
      this.popupTemplate = new PopupTemplate({
        title: 'Details',
        content: input
      });
      return;
    }

    this.popupTemplate = new PopupTemplate({
      title: input.title ?? 'Details',
      content: input.content ?? input.details ?? ''
    });
  }

  private applyPopupTemplateToGraphics(): void {
    if (!this.graphicsLayer) return;
    this.graphicsLayer.graphics.forEach((g) => this.applyPopupTemplateToGraphic(g));
  }

  private applyPopupTemplateToGraphic(graphic: __esri.Graphic): void {
    if (!graphic || !this.popupTemplate) return;
    graphic.popupTemplate = this.popupTemplate;
  }

  private enableInfoPopupWindow(enable: boolean): void {
    if (this.ancestorMap?.enableInfoWindow) {
      this.ancestorMap.enableInfoWindow(enable && !this.inDrawingMode);
    }
  }

  /**
   * ============================================================================
   * RENDERER / SYMBOLS
   * ============================================================================
   */

  private applyRenderer(): void {
    if (!this.graphicsLayer) return;
    if (this.renderer) {
      (this.graphicsLayer as any).renderer = this.renderer;
    }
  }

  private createDefaultSymbol(geometryType: string): __esri.Symbol {
    switch (geometryType) {
      case 'point':
      case 'multipoint':
        return new SimpleMarkerSymbol({
          size: 10,
          outline: { width: 1 }
        });

      case 'polyline':
        return new SimpleLineSymbol({
          width: 2
        });

      default:
        return new SimpleFillSymbol({
          outline: { width: 2 }
        });
    }
  }

  /**
   * ============================================================================
   * GEOJSON -> GRAPHICS
   * ============================================================================
   */

  private async renderGeoJson(): Promise<void> {
    if (!this.graphicsLayer) return;

    const fc = this.parseFeatureCollection(this.geojson);
    this.graphicsLayer.removeAll();

    if (!fc?.features?.length) return;

    for (const feature of fc.features) {
      const geometry = this.geoJsonGeometryToArcGis(feature.geometry);
      if (!geometry) continue;

      const graphic = new Graphic({
        geometry,
        attributes: { ...(feature.properties ?? {}) },
        symbol: this.createDefaultSymbol(geometry.type)
      });

      this.ensureUniqueId(graphic);
      this.applyPopupTemplateToGraphic(graphic);
      this.graphicsLayer.add(graphic);
    }
  }

  private parseFeatureCollection(input: FeatureCollectionInput): GeoJSON.FeatureCollection | null {
    if (!input) return null;

    try {
      const parsed = typeof input === 'string' ? JSON.parse(input) : input;
      if (parsed?.type === 'FeatureCollection' && Array.isArray(parsed.features)) {
        return parsed as GeoJSON.FeatureCollection;
      }

      console.warn('Invalid geojson input. Expected FeatureCollection.');
      return null;
    } catch (error) {
      console.warn('Unable to parse geojson input.', error);
      return null;
    }
  }

  private geoJsonGeometryToArcGis(geometry: GeometryInput): __esri.Geometry | null {
    if (!geometry) return null;

    switch (geometry.type) {
      case 'Point':
        return new Point({
          x: geometry.coordinates[0],
          y: geometry.coordinates[1],
          spatialReference: { wkid: 4326 }
        });

      case 'MultiPoint':
        return new Multipoint({
          points: geometry.coordinates as number[][],
          spatialReference: { wkid: 4326 }
        });

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
        const rings: number[][][] = [];
        for (const polygon of geometry.coordinates as number[][][][]) {
          rings.push(...polygon);
        }
        return new Polygon({
          rings,
          spatialReference: { wkid: 4326 }
        });
      }

      default:
        console.warn('Unsupported GeoJSON geometry type:', (geometry as GeoJSON.Geometry).type);
        return null;
    }
  }

  /**
   * ============================================================================
   * GRAPHICS -> GEOJSON
   * ============================================================================
   */

  private syncGeoJsonFromLayer(): void {
    if (!this.graphicsLayer) return;

    const features = this.graphicsLayer.graphics.toArray().map((graphic) => this.graphicToFeature(graphic));

    const fc: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features
    };

    this.suppressGeoJsonWatch = true;
    this.geojson = fc;
    this.suppressGeoJsonWatch = false;
  }

  private graphicToFeature(graphic: __esri.Graphic): GeoJSON.Feature {
    return {
      type: 'Feature',
      geometry: this.arcGisGeometryToGeoJson(graphic.geometry),
      properties: { ...(graphic.attributes ?? {}) }
    };
  }

  private arcGisGeometryToGeoJson(geometry: __esri.Geometry): GeoJSON.Geometry {
    switch (geometry.type) {
      case 'point': {
        const g = geometry as __esri.Point;
        return {
          type: 'Point',
          coordinates: [g.longitude ?? g.x, g.latitude ?? g.y]
        };
      }

      case 'multipoint': {
        const g = geometry as __esri.Multipoint;
        return {
          type: 'MultiPoint',
          coordinates: g.points as number[][]
        };
      }

      case 'polyline': {
        const g = geometry as __esri.Polyline;
        if ((g.paths?.length ?? 0) > 1) {
          return {
            type: 'MultiLineString',
            coordinates: g.paths as number[][][]
          };
        }
        return {
          type: 'LineString',
          coordinates: (g.paths?.[0] ?? []) as number[][]
        };
      }

      case 'polygon': {
        const g = geometry as __esri.Polygon;
        return {
          type: 'Polygon',
          coordinates: g.rings as number[][][]
        };
      }

      case 'extent': {
        const g = geometry as __esri.Extent;
        return {
          type: 'Polygon',
          coordinates: [[
            [g.xmin, g.ymin],
            [g.xmax, g.ymin],
            [g.xmax, g.ymax],
            [g.xmin, g.ymax],
            [g.xmin, g.ymin]
          ]]
        };
      }

      default:
        throw new Error(`Unsupported ArcGIS geometry type: ${(geometry as any).type}`);
    }
  }

  /**
   * ============================================================================
   * UNIQUE ID SUPPORT
   * ============================================================================
   */

  private ensureUniqueId(graphic: __esri.Graphic): void {
    if (!graphic.attributes) graphic.attributes = {};
    const existing = graphic.attributes[this.uniqueIdPropertyName];
    if (existing !== undefined && existing !== null && existing !== '') return;

    graphic.attributes[this.uniqueIdPropertyName] =
      crypto.randomUUID?.() ?? `id-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
  }

  async findFeatureByUniqueId(uniqueId: string | number): Promise<__esri.Graphic | undefined> {
    return this.graphicsLayer?.graphics.find((graphic) => {
      return graphic.attributes?.[this.uniqueIdPropertyName] === uniqueId;
    });
  }

  async openPopup(id: string | number): Promise<void> {
    if (!this.view) return;

    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic) {
      console.warn(`No feature found with ${this.uniqueIdPropertyName}=${id}`);
      return;
    }

    this.applyPopupTemplateToGraphic(graphic);

    const location = this.getPopupLocation(graphic.geometry);
    if (!location) return;

    this.view.popup.open({
      features: [graphic],
      location
    });
  }

  async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {
    if (!this.view) return;

    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic) {
      console.warn(`No feature found with ${this.uniqueIdPropertyName}=${id}`);
      return;
    }

    const geometry = graphic.geometry;
    if (!geometry) return;

    if (geometry.type === 'point') {
      await this.view.goTo({ target: geometry, zoom: zoomLevel });
      return;
    }

    await this.view.goTo(geometry);
  }

  /**
   * ============================================================================
   * NEW CHANGE START: create / edit / remove / vertices / scaling / rotate
   * - This replaces old Stencil edit toolbar logic with SketchViewModel.
   * ============================================================================
   */

  private syncEditingState(): void {
    if (!this.sketchVM) return;

    this.sketchVM.defaultUpdateOptions = {
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
      multipleSelectionEnabled: false
    };
  }

  private activateGraphicEditor(graphic: __esri.Graphic): void {
    if (!this.sketchVM || !this.enableUserEdit) return;

    const tool = this.getUpdateTool();
    if (!tool) return;

    this.sketchVM.update([graphic], {
      tool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
      multipleSelectionEnabled: false
    });
  }

  private getUpdateTool(): 'transform' | 'reshape' | 'move' | null {
    if (this.enableUserEditMove && !this.enableUserEditVertices) return 'move';
    if (this.enableUserEditVertices) return 'reshape';
    if (this.enableUserEditScaling || this.enableUserEditRotating) return 'transform';
    if (this.enableUserEditMove) return 'move';
    return null;
  }

  async startDrawing(drawGeometryType: string): Promise<void> {
    if (!this.sketchVM || !this.graphicsLayer) return;

    const tool = this.determineSketchCreateTool(drawGeometryType);
    if (!tool) {
      console.error(`Unsupported draw geometry type: ${drawGeometryType}`);
      return;
    }

    this.inDrawingMode = true;
    this.enableInfoPopupWindow(false);
    this.sketchVM.create(tool);
  }

  async cancelDrawing(): Promise<void> {
    this.inDrawingMode = false;
    this.sketchVM?.cancel();
    this.enableInfoPopupWindow(true);
  }

  async removeById(id: string | number): Promise<void> {
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic || !this.graphicsLayer) return;

    this.graphicsLayer.remove(graphic);
    this.emitUserEditItemRemoved(this.graphicToFeature(graphic));
    this.syncGeoJsonFromLayer();

    if (this.view?.popup?.visible) {
      this.view.popup.close();
    }
  }

  private determineSketchCreateTool(drawGeometryType: string): DrawTool | null {
    switch ((drawGeometryType ?? '').toLowerCase()) {
      case 'point':
        return 'point';

      case 'line':
      case 'polyline':
      case 'freehand_polyline':
        return 'polyline';

      case 'polygon':
      case 'freehand_polygon':
      case 'triangle':
      case 'arrow':
      case 'left_arrow':
      case 'right_arrow':
      case 'up_arrow':
      case 'down_arrow':
        return 'polygon';

      case 'rectangle':
      case 'extent':
        return 'rectangle';

      case 'circle':
      case 'ellipse':
        return 'circle';

      default:
        return null;
    }
  }

  /**
   * ============================================================================
   * NEW CHANGE END
   * ============================================================================
   */
}

declare global {
  interface HTMLElementTagNameMap {
    'arc-geojson-layer': ArcGeoJsonLayer;
  }
}
