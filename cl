import { LitElement, html } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import type { PropertyValues } from 'lit';

import Graphic from '@arcgis/core/Graphic';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer';
import FeatureLayer from '@arcgis/core/layers/FeatureLayer';
import SketchViewModel from '@arcgis/core/widgets/Sketch/SketchViewModel';
import SimpleRenderer from '@arcgis/core/renderers/SimpleRenderer';
import UniqueValueRenderer from '@arcgis/core/renderers/UniqueValueRenderer';
import ClassBreaksRenderer from '@arcgis/core/renderers/ClassBreaksRenderer';
import SimpleMarkerSymbol from '@arcgis/core/symbols/SimpleMarkerSymbol';
import SimpleLineSymbol from '@arcgis/core/symbols/SimpleLineSymbol';
import SimpleFillSymbol from '@arcgis/core/symbols/SimpleFillSymbol';
import LabelClass from '@arcgis/core/layers/support/LabelClass';
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
type GeometryLayerType = 'point' | 'multipoint' | 'polyline' | 'polygon';
type DrawTool =
  | 'point' | 'multipoint' | 'polyline' | 'polygon'
  | 'rectangle' | 'circle' | 'freehand_polyline' | 'freehand_polygon'
  | 'triangle' | 'arrow' | 'left_arrow' | 'right_arrow'
  | 'up_arrow' | 'down_arrow' | 'extent'
  | null;

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

  @property({ attribute: 'label-json' })
  labelJson: string | object | object[] | undefined = undefined;

  @property({ type: Array, attribute: 'label-color' })
  labelColor: number[] | string = [0, 0, 0, 255];

  @property({ type: Number, attribute: 'label-size' })
  labelSize = 10;

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

  private featureLayers = new Map<GeometryLayerType, FeatureLayer>();
  private sketchLayer: GraphicsLayer | null = null;
  private sketchVM: SketchViewModel | null = null;

  private inDrawingMode = false;
  private editingUniqueId: string | number | null = null;
  private popupTemplate: PopupTemplate | null = null;

  // FIX 1: track whether WE cancelled the SVM so the 'complete' handler ignores it
  private sketchVMCancelledProgrammatically = false;
  // FIX 2: single serialised gate for the dblclick → editor flow
  private editActivationInProgress = false;
  // FIX 3: true while the reshape/transform/move editor is open
  private editorActive = false;

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
    if (changed.has('infoTemplate')) {
      this.updateInfoTemplate(this.infoTemplate);
      this.applyPopupTemplateToAllLayers();
    }

    if (changed.has('renderer')) {
      this.updateRenderer(this.renderer);
    }

    if (
      changed.has('labelJson') ||
      changed.has('labelColor') ||
      changed.has('labelSize')
    ) {
      this.updateLabelJson(this.labelJson);
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

    if (changed.has('geojson')) {
      await this.createOrRefreshFeatureLayers();
    }
  }

  override disconnectedCallback(): void {
    super.disconnectedCallback();
    this.handles.removeAll();
    this.sketchVM?.cancel();
    this.sketchVM?.destroy();
    this.sketchVM = null;

    if (this.view && this.sketchLayer) {
      this.view.map?.remove(this.sketchLayer);
    }
    this.sketchLayer?.destroy();
    this.sketchLayer = null;

    if (this.view) {
      for (const layer of this.featureLayers.values()) {
        this.view.map?.remove(layer);
        layer.destroy();
      }
      this.featureLayers.clear();
    }
  }

  protected override render() {
    return html``;
  }

  // ----------------------------------------------------------------
  // BOOTSTRAP
  // ----------------------------------------------------------------
  private async bootstrap(): Promise<void> {
    if (this.ready) return;

    await this.resolveViewFromAncestor();
    if (!this.view) return;

    this.ensureSketchLayer();
    this.ensureSketchViewModel();

    this.updateInfoTemplate(this.infoTemplate);
    await this.createOrRefreshFeatureLayers();
    this.registerLayerEvents();
    this.syncEditingState();

    this.ready = true;
  }

  private async resolveViewFromAncestor(): Promise<void> {
    this.ancestorMap = this.closest('arc-map') as any;

    if (!this.ancestorMap) {
      console.error('<arc-geojson-layer> must be used inside <arc-map>.');
      return;
    }

    if (typeof this.ancestorMap.getInstance === 'function') {
      this.view = await this.ancestorMap.getInstance();
    } else if (this.ancestorMap?.view) {
      this.view = this.ancestorMap.view;
    }

    if (!this.view) {
      console.error('Could not resolve ArcGIS view from ancestor <arc-map>.');
      return;
    }

    if (typeof (this.view as any).when === 'function') {
      await (this.view as any).when();
    }
  }

  // ----------------------------------------------------------------
  // FEATURE LAYERS
  // ----------------------------------------------------------------
  private async createOrRefreshFeatureLayers(): Promise<void> {
    if (!this.view) return;

    // FIX 4: never wipe layers while the sketch editor is active
    if (this.editorActive) return;

    const featureCollection = this.parseFeatureCollection(this.geojson);
    if (!featureCollection) {
      this.removeAllFeatureLayers();
      return;
    }

    const grouped = this.groupFeaturesByGeometry(featureCollection);

    for (const [type, layer] of this.featureLayers.entries()) {
      if ((grouped.get(type)?.length ?? 0) === 0) {
        this.view.map?.remove(layer);
        layer.destroy();
        this.featureLayers.delete(type);
      }
    }

    for (const [type, features] of grouped.entries()) {
      if (!features.length) continue;

      const graphics = features
        .map((f, i) => this.featureToGraphic(f, i))
        .filter((g): g is Graphic => g !== null);

      if (!graphics.length) continue;

      const fields = this.buildFields(graphics);

      const existingLayer = this.featureLayers.get(type);
      if (existingLayer) {
        this.view.map?.remove(existingLayer);
        existingLayer.destroy();
      }

      const layer = new FeatureLayer({
        source: graphics,
        fields,
        objectIdField: 'OBJECTID',
        geometryType: type,
        spatialReference: { wkid: 4326 },
        outFields: ['*'],
        popupEnabled: true,
        popupTemplate: this.popupTemplate ?? undefined
      });

      this.featureLayers.set(type, layer);
      this.view.map?.add(layer);
    }

    this.applyPopupTemplateToAllLayers();
    this.updateRenderer(this.renderer);
    this.updateLabelJson(this.labelJson);
  }

  private removeAllFeatureLayers(): void {
    if (!this.view) return;
    for (const layer of this.featureLayers.values()) {
      this.view.map?.remove(layer);
      layer.destroy();
    }
    this.featureLayers.clear();
  }

  private parseFeatureCollection(
    input: string | GeoJsonFeatureCollection | null | undefined
  ): GeoJsonFeatureCollection | null {
    if (!input) return null;
    try {
      const parsed = typeof input === 'string' ? JSON.parse(input) : input;
      if (parsed?.type === 'FeatureCollection' && Array.isArray(parsed.features)) {
        return parsed as GeoJsonFeatureCollection;
      }
      console.warn('Invalid geojson input. Expected FeatureCollection.');
    } catch (error) {
      console.error('Failed to parse geojson input.', error);
    }
    return null;
  }

  private groupFeaturesByGeometry(
    fc: GeoJsonFeatureCollection
  ): Map<GeometryLayerType, GeoJsonFeature[]> {
    const map = new Map<GeometryLayerType, GeoJsonFeature[]>([
      ['point', []], ['multipoint', []], ['polyline', []], ['polygon', []]
    ]);

    for (const feature of fc.features ?? []) {
      if (!feature.geometry) continue;
      const layerType = this.geoJsonGeometryTypeToLayerType(feature.geometry.type);
      // FIX 5: was 'if (layerType) continue' — inverted logic skipped valid features
      if (!layerType) continue;
      map.get(layerType)!.push(feature);
    }

    return map;
  }

  private geoJsonGeometryTypeToLayerType(
    geometryType: NonNullable<GeoJsonFeature['geometry']>['type']
  ): GeometryLayerType | null {
    switch (geometryType) {
      case 'Point':           return 'point';
      case 'MultiPoint':      return 'multipoint';
      case 'LineString':
      case 'MultiLineString': return 'polyline';
      case 'Polygon':
      case 'MultiPolygon':    return 'polygon';
      default:                return null;
    }
  }

  private featureToGraphic(feature: GeoJsonFeature, index: number): Graphic | null {
    if (!feature.geometry) return null;

    const geometry = this.toArcGisGeometry(feature.geometry);
    if (!geometry) return null;

    const attributes: Record<string, any> = {
      OBJECTID: index + 1,
      ...(feature.properties ?? {})
    };

    if (attributes[this.uniqueIdPropertyName] == null) {
      attributes[this.uniqueIdPropertyName] = feature.id ?? `${index + 1}`;
    }

    return new Graphic({
      geometry,
      attributes,
      popupTemplate: this.popupTemplate ?? undefined
    });
  }

  private toArcGisGeometry(geometry: GeoJsonGeometry): Geometry | null {
    switch (geometry.type) {
      case 'Point':
        return new Point({
          x: geometry.coordinates[0],
          y: geometry.coordinates[1],
          spatialReference: { wkid: 4326 }
        });

      case 'MultiPoint':
        return new Multipoint({
          points: geometry.coordinates,
          spatialReference: { wkid: 4326 }
        });

      case 'LineString':
        return new Polyline({
          paths: [geometry.coordinates],
          spatialReference: { wkid: 4326 }
        });

      case 'MultiLineString':
        return new Polyline({
          paths: geometry.coordinates,
          spatialReference: { wkid: 4326 }
        });

      case 'Polygon': {
        const rings = geometry.coordinates.map((ring) => {
          if (!Array.isArray(ring) || ring.length < 3) return ring;
          const first = ring[0];
          const last = ring[ring.length - 1];
          return (first[0] !== last[0] || first[1] !== last[1])
            ? [...ring, [...first]] : ring;
        });
        return new Polygon({ rings, spatialReference: { wkid: 4326 } });
      }

      case 'MultiPolygon': {
        const rings: number[][][] = [];
        for (const polygon of geometry.coordinates) {
          for (const ring of polygon) {
            if (!Array.isArray(ring) || ring.length < 3) continue;
            const first = ring[0];
            const last = ring[ring.length - 1];
            rings.push(
              (first[0] !== last[0] || first[1] !== last[1])
                ? [...ring, [...first]] : ring
            );
          }
        }
        return new Polygon({ rings, spatialReference: { wkid: 4326 } });
      }

      default: return null;
    }
  }

  private buildFields(graphics: Graphic[]): any[] {
    const fields: any[] = [{ name: 'OBJECTID', alias: 'OBJECTID', type: 'oid' }];
    const discovered = new Set<string>(['OBJECTID']);

    for (const graphic of graphics) {
      const attrs = graphic.attributes ?? {};
      for (const [key, value] of Object.entries(attrs)) {
        if (discovered.has(key)) continue;
        discovered.add(key);
        let type = 'string';
        if (typeof value === 'number') {
          type = Number.isInteger(value) ? 'integer' : 'double';
        }
        fields.push({ name: key, alias: key, type });
      }
    }

    return fields;
  }

  // ----------------------------------------------------------------
  // SKETCH LAYER + SVM
  // ----------------------------------------------------------------
  private ensureSketchLayer(): void {
    if (!this.view || this.sketchLayer) return;
    this.sketchLayer = new GraphicsLayer({
      id: `${this.id || 'arc-geojson-layer'}-sketch-layer`
    });
    this.view.map?.add(this.sketchLayer);
  }

  private ensureSketchViewModel(): void {
    if (!this.view || !this.sketchLayer || this.sketchVM) return;

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

    // ---- CREATE ----
    this.handles.add(
      this.sketchVM.on('create', async (event: any) => {
        if (event.state !== 'complete' || !event.graphic) return;

        const graphic = event.graphic;
        graphic.popupTemplate = null;
        if (!graphic.attributes) graphic.attributes = {};
        if (graphic.attributes[this.uniqueIdPropertyName] == null) {
          graphic.attributes[this.uniqueIdPropertyName] =
            crypto.randomUUID?.() ?? `id-${Date.now()}`;
        }

        const feature = this.graphicToGeoJsonFeature(graphic);
        await this.appendFeatureToGeoJson(feature);

        this.dispatchEvent(new CustomEvent('userDrawItemAdded', {
          detail: feature, bubbles: true, composed: true
        }));

        this.inDrawingMode = false;
        this.editingUniqueId = null;
        this.sketchLayer?.removeAll();
        this.cancelSketchVM();

        if (this.view && (this.view as any).popupEnabled) {
          this.closePopup();
          this.enableInfoPopupWindow(false);
        }

        console.log('draw complete', feature, this.view);
      }),
      'sketch-create'
    );

    // ---- UPDATE ----
    this.handles.add(
      this.sketchVM.on('update', async (event: any) => {
        if (event.state === 'start') {
          this.editorActive = true;
          this.closePopup();
          return;
        }

        if (event.state !== 'complete') return;

        // FIX 1: ignore 'complete' events we triggered via cancelSketchVM()
        if (this.sketchVMCancelledProgrammatically) return;

        if (!event.graphics?.length) return;

        const graphic = event.graphics[0];
        graphic.popupTemplate = null;
        const feature = this.graphicToGeoJsonFeature(graphic);

        if (this.editingUniqueId != null) {
          (feature.properties as any)[this.uniqueIdPropertyName] = this.editingUniqueId;
          await this.updateGeoJsonWithChanges(feature);
        }

        this.dispatchEvent(new CustomEvent('userEditItemUpdated', {
          detail: feature, bubbles: true, composed: true
        }));

        this.inDrawingMode = false;
        this.sketchVM?.cancel();
        this.sketchLayer?.removeAll();
        this.editingUniqueId = null;

        if (this.view && (this.view as any).popupEnabled) {
          this.closePopup();
          this.enableInfoPopupWindow(false);
        }

        // FIX 3: reset editorActive AFTER everything is fully cleaned up
        this.editorActive = false;

        console.log('update complete', feature);
      }),
      'sketch-update'
    );
  }

  // FIX 1: centralised cancel — sets flag so 'complete' event is ignored
  // when it fires as a side-effect of our own cancel() call.
  private cancelSketchVM(): void {
    if (!this.sketchVM) return;
    this.sketchVMCancelledProgrammatically = true;
    this.sketchVM.cancel();
    setTimeout(() => { this.sketchVMCancelledProgrammatically = false; }, 0);
  }

  // ----------------------------------------------------------------
  // SYNC EDITING STATE
  // ----------------------------------------------------------------
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

  private getUpdateTool(): 'transform' | 'reshape' | 'move' | null {
    if (
      this.enableUserEditVertices ||
      this.enableUserEditAddVertices ||
      this.enableUserEditDeleteVertices
    ) return 'reshape';

    if (this.enableUserEditScaling || this.enableUserEditRotating) return 'transform';
    if (this.enableUserEditMove) return 'move';
    return null;
  }

  // ----------------------------------------------------------------
  // PUBLIC: START / CANCEL DRAWING
  // ----------------------------------------------------------------
  async startDrawing(drawGeometryType: string): Promise<void> {
    if (!this.sketchVM) {
      this.ensureSketchLayer();
      this.ensureSketchViewModel();
    }
    if (!this.sketchVM) return;

    const tool = this.determineSketchCreateTool(drawGeometryType);
    if (!tool) {
      console.error(`Unsupported draw geometry type: ${drawGeometryType}`);
      return;
    }

    this.cancelSketchVM();
    this.sketchLayer?.removeAll();

    if (this.view && (this.view as any).popupEnabled) {
      this.closePopup();
      this.enableInfoPopupWindow(false);
    }

    this.inDrawingMode = true;
    this.sketchVM.create(tool);
    console.log('new change: drawing started', tool);
  }

  async cancelDrawing(): Promise<void> {
    this.inDrawingMode = false;
    this.editingUniqueId = null;
    this.cancelSketchVM();
    this.sketchLayer?.removeAll();

    if (this.view && (this.view as any).popupEnabled) {
      this.closePopup();
      this.enableInfoPopupWindow(false);
    }

    console.log('cancel drawing executed');
  }

  private determineSketchCreateTool(drawGeometryType: string): DrawTool {
    switch ((drawGeometryType ?? '').toLowerCase()) {
      case 'point':             return 'point';
      case 'multipoint':        return 'multipoint';
      case 'line':
      case 'polyline':
      case 'freehand_polyline':
      case 'linestring':        return 'polyline';
      case 'polygon':
      case 'freehand_polygon':
      case 'triangle':
      case 'arrow':
      case 'left_arrow':
      case 'right_arrow':
      case 'up_arrow':
      case 'down_arrow':        return 'polygon';
      case 'rectangle':
      case 'extent':            return 'rectangle';
      case 'circle':
      case 'ellipse':           return 'circle';
      default:                  return null;
    }
  }

  // ----------------------------------------------------------------
  // ACTIVATE EDITOR — called by dblclick handler
  // FIX 2: removed internal editActivationInProgress guard
  // FIX 2: setTimeout(0) gives the sketch layer a real render tick
  //        before sketchVM.update() tries to select the cloned graphic
  // ----------------------------------------------------------------
  private async activateGraphicsEditor(featureGraphic: Graphic): Promise<void> {
    if (!this.enableUserEdit || !this.sketchVM || !this.sketchLayer) return;
    if (this.editorActive) return;

    const uniqueId = featureGraphic.attributes?.[this.uniqueIdPropertyName];
    this.editingUniqueId = uniqueId ?? null;

    this.closePopup();
    this.enableInfoPopupWindow(false);

    this.cancelSketchVM();
    this.sketchLayer.removeAll();

    const clone = featureGraphic.clone();
    clone.popupTemplate = null;
    this.sketchLayer.add(clone);

    const updateTool = this.getUpdateTool();
    if (!updateTool) {
      console.warn(
        'ArcGeoJsonLayer: no update tool configured. ' +
        'Enable at least one of: enableUserEditMove, enableUserEditVertices, ' +
        'enableUserEditScaling, enableUserEditRotating.'
      );
      return;
    }

    // FIX 2: real macrotask tick — Promise.resolve() is NOT enough
    await new Promise<void>((resolve) => setTimeout(resolve, 0));

    this.sketchVM.update([clone], {
      tool: updateTool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
      multipleSelectionEnabled: false
    });
  }

  // ----------------------------------------------------------------
  // EVENTS
  // ----------------------------------------------------------------
  private registerLayerEvents(): void {
    if (!this.view) return;

    this.handles.remove('view-click');
    this.handles.remove('native-dblclick');

    // ---- SINGLE CLICK ----
    this.handles.add(
      this.view.on('click', async (event: any) => {
        if (!this.view || this.inDrawingMode) return;

        const hit = await this.view.hitTest(event);
        const result = (hit.results ?? []).find((r: any) =>
          r?.type === 'graphic' && this.resultBelongsToManagedLayerResult(r)
        ) as any;

        const graphic = result?.graphic as Graphic | undefined;
        const uniqueId = graphic?.attributes?.[this.uniqueIdPropertyName];
        const nativeEvent = event?.native ?? event;

        // ctrl/cmd + click → remove feature
        if (
          this.enableUserEdit &&
          this.enableUserEditRemove &&
          graphic &&
          (nativeEvent?.ctrlKey || nativeEvent?.metaKey)
        ) {
          if (uniqueId !== undefined && uniqueId !== null) {
            await this.removeById(uniqueId);
          }
          this.closePopup();
          return;
        }

        // edit mode: suppress popup on single click
        if (this.enableUserEdit) {
          this.closePopup();
          return;
        }

        // view mode: show popup
        if (graphic) {
          const location = event.mapPoint ?? this.getPopupLocation(graphic.geometry);
          if (location && this.view) {
            (this.view as any).openPopup?.({ features: [graphic], location });
          }
        }

        this.dispatchEvent(new CustomEvent('layerClick', {
          detail: { graphic, uniqueId, attributes: graphic?.attributes ?? {} },
          bubbles: true,
          composed: true
        }));
      }),
      'view-click'
    );

    // ---- NATIVE DBLCLICK ----
    const container = this.view.container as HTMLElement | null;
    if (!container) return;

    // FIX 2: editActivationInProgress guard is HERE (not inside activateGraphicsEditor)
    //        and is reset synchronously in finally — no setTimeout needed for the flag.
    const nativeDblClickHandler = async (event: MouseEvent) => {
      console.log('dblclick', this.view);
      if (!this.view || this.inDrawingMode) return;
      if (this.editActivationInProgress) return;

      event.preventDefault();
      event.stopPropagation();

      const rect = container.getBoundingClientRect();
      const screenPoint = {
        x: event.clientX - rect.left,
        y: event.clientY - rect.top
      };

      console.log('dblclick', screenPoint, event);
      this.closePopup();

      const hit = await this.view.hitTest(screenPoint as any);
      const result = (hit.results ?? []).find((r: any) =>
        r?.type === 'graphic' && this.resultBelongsToManagedLayerResult(r)
      ) as any;

      if (!result?.graphic) return;

      const graphic = result.graphic as Graphic;
      const uniqueId = graphic.attributes?.[this.uniqueIdPropertyName];

      if (this.enableUserEdit) {
        this.editActivationInProgress = true;
        try {
          this.closePopup();
          await this.activateGraphicsEditor(graphic);
        } catch (err) {
          console.error('ArcGeoJsonLayer: editor activation failed', err);
          this.editorActive = false;
        } finally {
          // FIX 2: reset immediately and synchronously
          this.editActivationInProgress = false;
        }
      }

      this.dispatchEvent(new CustomEvent('doubleClick', {
        detail: { graphic, uniqueId, attributes: graphic.attributes ?? {} },
        bubbles: true,
        composed: true
      }));
    };

    container.addEventListener('dblclick', nativeDblClickHandler);

    this.handles.add(
      { remove: () => container.removeEventListener('dblclick', nativeDblClickHandler) },
      'native-dblclick'
    );
  }

  // ----------------------------------------------------------------
  // RESULT BELONGS TO MANAGED LAYER
  // ----------------------------------------------------------------
  private resultBelongsToManagedLayerResult(result: any): boolean {
    const graphic = result?.graphic;
    if (!graphic) return false;

    for (const managed of this.featureLayers.values()) {
      if (managed === graphic.layer) return true;
      if (managed === result?.layer) return true;
      if (graphic?.origin?.layerId && managed.id === graphic.origin.layerId) return true;
    }

    return false;
  }

  // ----------------------------------------------------------------
  // PUBLIC HELPERS
  // ----------------------------------------------------------------
  async findFeatureByUniqueId(uniqueId: string | number): Promise<Graphic | undefined> {
    for (const layer of this.featureLayers.values()) {
      const source = (layer as any).source as any | undefined;
      const graphic = source?.find(
        (g: Graphic) => g.attributes?.[this.uniqueIdPropertyName] === uniqueId
      );
      if (graphic) return graphic;
    }
    return undefined;
  }

  async openPopupById(id: string | number): Promise<void> {
    if (!this.view) return;
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic) {
      console.warn(`No feature found with ${this.uniqueIdPropertyName}=${id}`);
      return;
    }
    const location = this.getPopupLocation(graphic.geometry);
    if (!location) return;
    (this.view as any).openPopup?.({ features: [graphic], location });
  }

  async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {
    if (!this.view) return;
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic || !graphic.geometry) return;

    if (graphic.geometry.type === 'point') {
      await this.view.goTo({ target: graphic.geometry, zoom: zoomLevel });
      return;
    }
    await this.view.goTo(
      ((graphic.geometry as any).extent ?? graphic.geometry) as any
    );
  }

  // ----------------------------------------------------------------
  // POPUP HELPERS
  // ----------------------------------------------------------------
  private getPopupLocation(geometry: any): Point | null {
    if (!geometry) return null;

    switch (geometry.type) {
      case 'point':
        return geometry as Point;

      case 'multipoint': {
        const mp = geometry as Multipoint;
        const first = mp.points?.[0];
        if (!first) return null;
        return new Point({ x: first[0], y: first[1], spatialReference: mp.spatialReference });
      }

      case 'polyline': {
        const line = geometry as Polyline;
        const path = line.paths?.[0];
        if (!path?.length) return null;
        const mid = path[Math.floor(path.length / 2)];
        return new Point({ x: mid[0], y: mid[1], spatialReference: line.spatialReference });
      }

      case 'polygon':
        return (geometry as Polygon).extent?.center ?? null;

      case 'extent':
        return (geometry as any).center ?? null;

      default:
        return (geometry as any)?.extent?.center ?? null;
    }
  }

  private closePopup(): void {
    console.log(this.view, 'view in closepopup');
    console.log((this.view as any)?.popup, 'popup in closepopup');
    console.log(this.inDrawingMode, 'inDrawingMode in closepopup');
    this.ancestorMap?.closePopup?.();
  }

  // ----------------------------------------------------------------
  // INFO TEMPLATE
  // ----------------------------------------------------------------
  private updateInfoTemplate(newInfoTemplate: PopupInput): void {
    if (!newInfoTemplate) {
      this.popupTemplate = null;
      this.applyPopupTemplateToAllLayers();
      return;
    }

    if (typeof newInfoTemplate === 'string') {
      this.popupTemplate = new PopupTemplate({ title: 'Details', content: newInfoTemplate });
    } else {
      this.popupTemplate = new PopupTemplate({
        title: newInfoTemplate.title ?? 'Details',
        content: newInfoTemplate.content ?? newInfoTemplate.details ?? ''
      });
    }

    this.applyPopupTemplateToAllLayers();
  }

  private applyPopupTemplateToAllLayers(): void {
    for (const layer of this.featureLayers.values()) {
      layer.popupTemplate = this.popupTemplate ?? undefined;
    }
  }

  private enableInfoPopupWindow(enable: boolean): void {
    console.log(enable, this.inDrawingMode, 'enableInfoPopupWindow');
    if (!this.view) return;
    const allowPopup = enable && !this.inDrawingMode;
    if (!allowPopup && (this.view as any).popup) {
      this.closePopup();
    }
  }

  // ----------------------------------------------------------------
  // RENDERER
  // ----------------------------------------------------------------
  private updateRenderer(newRenderer: any | null): void {
    for (const [type, layer] of this.featureLayers.entries()) {
      if (newRenderer) {
        const rt = newRenderer?.type;
        if (rt === 'simple' && this.isRendererCompatible(type, newRenderer)) {
          layer.renderer = new SimpleRenderer(newRenderer);
          continue;
        }
        if (rt === 'unique-value') {
          layer.renderer = new UniqueValueRenderer(newRenderer);
          continue;
        }
        if (rt === 'class-breaks') {
          layer.renderer = new ClassBreaksRenderer(newRenderer);
          continue;
        }
      }
      layer.renderer = this.createDefaultRenderer(type);
    }
  }

  private isRendererCompatible(type: GeometryLayerType, renderer: any): boolean {
    const symbolType = renderer?.symbol?.type;
    if (type === 'point' || type === 'multipoint') return symbolType === 'simple-marker';
    if (type === 'polyline') return symbolType === 'simple-line';
    if (type === 'polygon')  return symbolType === 'simple-fill';
    return false;
  }

  private createDefaultRenderer(type: GeometryLayerType): SimpleRenderer {
    if (type === 'point' || type === 'multipoint') {
      return new SimpleRenderer({
        symbol: new SimpleMarkerSymbol({ size: 12, outline: { width: 1 } })
      });
    }
    if (type === 'polyline') {
      return new SimpleRenderer({ symbol: new SimpleLineSymbol({ width: 8 }) });
    }
    return new SimpleRenderer({
      symbol: new SimpleFillSymbol({ color: [0, 122, 255, 0.12], outline: { width: 2 } })
    });
  }

  // ----------------------------------------------------------------
  // LABELS
  // ----------------------------------------------------------------
  private updateLabelJson(
    newLabelJsonArg: string | object | object[] | undefined
  ): void {
    if (!newLabelJsonArg) {
      for (const layer of this.featureLayers.values()) {
        layer.labelingInfo = [];
        layer.labelsVisible = false;
      }
      return;
    }

    const parsed =
      typeof newLabelJsonArg === 'string'
        ? JSON.parse(newLabelJsonArg)
        : newLabelJsonArg;

    const labelingInfo = Array.isArray(parsed)
      ? parsed.map((item: any) => new LabelClass(item as any))
      : [new LabelClass(parsed as any)];

    for (const layer of this.featureLayers.values()) {
      layer.labelingInfo = labelingInfo as any;
      layer.labelsVisible = true;
    }
  }

  // ----------------------------------------------------------------
  // REMOVE BY ID
  // ----------------------------------------------------------------
  async removeById(id: string | number): Promise<void> {
    const feature = await this.findFeatureByUniqueId(id);
    if (!feature) return;

    await this.removeFromGeoJson(feature);

    this.dispatchEvent(new CustomEvent('userEditItemRemoved', {
      detail: this.graphicToGeoJsonFeature(feature),
      bubbles: true,
      composed: true
    }));

    if ((this.view as any)?.popup?.visible) {
      this.closePopup();
    }
  }

  // ----------------------------------------------------------------
  // GEOJSON PERSISTENCE
  // ----------------------------------------------------------------
  private graphicToGeoJsonFeature(graphic: Graphic): GeoJsonFeature {
    const properties = { ...(graphic.attributes ?? {}) };
    delete properties.OBJECTID;

    if (properties[this.uniqueIdPropertyName] == null) {
      properties[this.uniqueIdPropertyName] =
        crypto.randomUUID?.() ?? `id-${Date.now()}`;
    }

    return {
      type: 'Feature',
      geometry: this.arcGisGeometryToGeoJson(graphic.geometry),
      properties
    } as GeoJsonFeature;
  }

  private arcGisGeometryToGeoJson(geometry: any): GeoJsonGeometry | null {
    const geographicGeometry =
      webMercatorUtils.canProject(geometry, { wkid: 4326 } as any)
        ? (webMercatorUtils.webMercatorToGeographic(geometry) as Geometry)
        : geometry;

    if (geographicGeometry instanceof Point) {
      return {
        type: 'Point',
        coordinates: [
          geographicGeometry.longitude ?? geographicGeometry.x,
          geographicGeometry.latitude ?? geographicGeometry.y
        ]
      };
    }

    if (geographicGeometry instanceof Multipoint) {
      return {
        type: 'MultiPoint',
        coordinates: geographicGeometry.points.map((p) => [p[0], p[1]])
      };
    }

    if (geographicGeometry instanceof Polyline) {
      const paths = geographicGeometry.paths ?? [];
      if (paths.length === 1) {
        return {
          type: 'LineString',
          coordinates: paths[0].map((p) => [p[0], p[1]])
        };
      }
      return {
        type: 'MultiLineString',
        coordinates: paths.map((path) => path.map((p) => [p[0], p[1]]))
      };
    }

    if (geographicGeometry instanceof Polygon) {
      return {
        type: 'Polygon',
        coordinates: geographicGeometry.rings.map((ring) =>
          ring.map((p) => [p[0], p[1]])
        )
      };
    }

    return null;
  }

  private async appendFeatureToGeoJson(feature: GeoJsonFeature): Promise<void> {
    const current =
      typeof this.geojson === 'string'
        ? JSON.parse(this.geojson)
        : (this.geojson ?? { type: 'FeatureCollection', features: [] });

    if (!current.features || !Array.isArray(current.features)) {
      current.features = [];
    }

    current.features.push(feature);
    this.geojson = current;
    await this.createOrRefreshFeatureLayers();
  }

  private async updateGeoJsonWithChanges(
    updatedFeature: GeoJsonFeature
  ): Promise<void> {
    const fc = this.parseFeatureCollection(this.geojson);
    if (!fc) return;

    const updatedId =
      updatedFeature.properties?.[this.uniqueIdPropertyName] ?? updatedFeature.id;

    fc.features = fc.features.map((feature) => {
      const featureId =
        feature.properties?.[this.uniqueIdPropertyName] ?? feature.id;
      return featureId === updatedId ? updatedFeature : feature;
    });

    this.geojson = fc;
    await this.createOrRefreshFeatureLayers();
  }

  private async removeFromGeoJson(featureGraphic: Graphic): Promise<void> {
    const fc = this.parseFeatureCollection(this.geojson);
    if (!fc) return;

    const removeId = featureGraphic.attributes?.[this.uniqueIdPropertyName];

    fc.features = fc.features.filter((feature) => {
      const featureId =
        feature.properties?.[this.uniqueIdPropertyName] ?? feature.id;
      return featureId !== removeId;
    });

    this.geojson = fc;
    await this.createOrRefreshFeatureLayers();
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'arc-geojson-layer': ArcGeoJsonLayer;
  }
}
