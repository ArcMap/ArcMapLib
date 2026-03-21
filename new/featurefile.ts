from pathlib import Path

content = """import { LitElement, nothing } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';

import Handles from '@arcgis/core/core/Handles';
import Graphic from '@arcgis/core/Graphic';
import FeatureLayer from '@arcgis/core/layers/FeatureLayer';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer';
import PopupTemplate from '@arcgis/core/PopupTemplate';
import SketchViewModel from '@arcgis/core/widgets/Sketch/SketchViewModel';

import MapView from '@arcgis/core/views/MapView';
import SceneView from '@arcgis/core/views/SceneView';

import Point from '@arcgis/core/geometry/Point';
import Polyline from '@arcgis/core/geometry/Polyline';
import Polygon from '@arcgis/core/geometry/Polygon';
import Multipoint from '@arcgis/core/geometry/Multipoint';
import Extent from '@arcgis/core/geometry/Extent';
import Geometry from '@arcgis/core/geometry/Geometry';

import SimpleRenderer from '@arcgis/core/renderers/SimpleRenderer';
import UniqueValueRenderer from '@arcgis/core/renderers/UniqueValueRenderer';
import ClassBreaksRenderer from '@arcgis/core/renderers/ClassBreaksRenderer';

import SimpleMarkerSymbol from '@arcgis/core/symbols/SimpleMarkerSymbol';
import SimpleLineSymbol from '@arcgis/core/symbols/SimpleLineSymbol';
import SimpleFillSymbol from '@arcgis/core/symbols/SimpleFillSymbol';

import LabelClass from '@arcgis/core/layers/support/LabelClass';

type ArcGISView = MapView | SceneView;
type DrawTool = 'point' | 'polyline' | 'polygon' | 'rectangle' | 'circle';
type GeometryLayerType = 'point' | 'multipoint' | 'polyline' | 'polygon';

interface UpMapLike extends HTMLElement {
  getViewInstance?: () => Promise<ArcGISView | null> | ArcGISView | null;
  viewOnReady?: () => Promise<void>;
  enableInfoWindow?: (enable: boolean) => void;
  _jsView?: ArcGISView | null;
  view?: ArcGISView | null;
}

interface GeoJsonFeature {
  type: 'Feature';
  id?: string | number;
  geometry: {
    type:
      | 'Point'
      | 'MultiPoint'
      | 'LineString'
      | 'MultiLineString'
      | 'Polygon'
      | 'MultiPolygon';
    coordinates: any;
  } | null;
  properties?: Record<string, any>;
}

interface GeoJsonFeatureCollection {
  type: 'FeatureCollection';
  features: GeoJsonFeature[];
}

type PopupInput =
  | string
  | {
      title?: string;
      content?: string;
      details?: string;
    }
  | null
  | undefined;

/**
 * ============================================================================
 * NEW CHANGE:
 * Full LitElement + ArcGIS 5.x UP-GEOJSON-LAYER
 *
 * Main architecture:
 * - FeatureLayer(s) = persistent rendered data layer(s)
 * - GraphicsLayer = temporary sketch/edit workbench
 *
 * This file intentionally marks important migrated areas with:
 *   NEW CHANGE START / NEW CHANGE END
 * ============================================================================
 */
@customElement('up-geojson-layer')
export class UpGeoJsonLayer extends LitElement {
  createRenderRoot() {
    return this;
  }

  render() {
    return nothing;
  }

  @property({ attribute: false })
  geojson: string | GeoJsonFeatureCollection | null = null;

  @property({ attribute: 'info-template' })
  infoTemplate: PopupInput = null;

  @property({ attribute: false })
  renderer?: any;

  @property({ attribute: 'label-json' })
  labelJson?: string | object | object[];

  @property({ attribute: 'label-color', attribute: false })
  labelColor: number[] | string = [0, 0, 0, 255];

  @property({ type: Number, attribute: 'label-size' })
  labelSize = 10;

  @property({ attribute: 'unique-id-property-name' })
  uniqueIdPropertyName = 'id';

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

  @state()
  private ready = false;

  private ancestorMap: UpMapLike | null = null;
  private view: ArcGISView | null = null;
  private handles = new Handles();

  private featureLayers = new Map<GeometryLayerType, FeatureLayer>();
  private sketchLayer: GraphicsLayer | null = null;
  private sketchVM: SketchViewModel | null = null;

  private inDrawingMode = false;
  private editingUniqueId: string | number | null = null;
  private popupTemplate: PopupTemplate | null = null;
  private suppressGeoJsonUpdate = false;

  override connectedCallback(): void {
    super.connectedCallback();
    void this.bootstrap();
  }

  override async firstUpdated(): Promise<void> {
    await this.bootstrap();
  }

  override async updated(changed: Map<string, unknown>): Promise<void> {
    if (changed.has('infoTemplate')) {
      this.updateInfoTemplate(this.infoTemplate);
      this.applyPopupTemplateToAllLayers();
    }

    // ===== NEW CHANGE: renderer support start =====
    if (changed.has('renderer')) {
      this.updateRenderer(this.renderer);
    }
    // ===== NEW CHANGE: renderer support end =====

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

    if (changed.has('geojson') && !this.suppressGeoJsonUpdate) {
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
    }
    this.featureLayers.clear();

    this.view = null;
    this.ancestorMap = null;
  }

  // ============================================================================
  // NEW CHANGE START: resolve ancestor UPMap + view
  // ============================================================================

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
    this.ancestorMap = this.closest('up-map') as UpMapLike | null;

    if (!this.ancestorMap) {
      console.error('<up-geojson-layer> must be used inside <up-map>.');
      return;
    }

    if (typeof this.ancestorMap.viewOnReady === 'function') {
      await this.ancestorMap.viewOnReady();
    }

    if (typeof this.ancestorMap.getViewInstance === 'function') {
      this.view = await this.ancestorMap.getViewInstance();
    } else if (this.ancestorMap._jsView) {
      this.view = this.ancestorMap._jsView;
    } else if (this.ancestorMap.view) {
      this.view = this.ancestorMap.view;
    }

    if (!this.view) {
      console.error('Could not resolve ArcGIS view from ancestor <up-map>.');
    } else if (typeof this.view.when === 'function') {
      await this.view.when();
    }
  }

  // ============================================================================
  // NEW CHANGE END
  // ============================================================================

  private async createOrRefreshFeatureLayers(): Promise<void> {
    if (!this.view) return;

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
        .map((feature, index) => this.featureToGraphic(feature, index))
        .filter((g): g is Graphic => !!g);

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

    await this.zoomToAllFeatures();
  }

  private removeAllFeatureLayers(): void {
    if (!this.view) return;
    for (const layer of this.featureLayers.values()) {
      this.view.map?.remove(layer);
      layer.destroy();
    }
    this.featureLayers.clear();
  }

  private parseFeatureCollection(input: string | GeoJsonFeatureCollection | null): GeoJsonFeatureCollection | null {
    if (!input) return null;

    try {
      const parsed = typeof input === 'string' ? JSON.parse(input) : input;
      if (parsed?.type === 'FeatureCollection' && Array.isArray(parsed.features)) {
        return parsed as GeoJsonFeatureCollection;
      }
      console.warn('Invalid geojson input. Expected FeatureCollection.');
      return null;
    } catch (error) {
      console.error('Failed to parse geojson input.', error);
      return null;
    }
  }

  private groupFeaturesByGeometry(fc: GeoJsonFeatureCollection): Map<GeometryLayerType, GeoJsonFeature[]> {
    const map = new Map<GeometryLayerType, GeoJsonFeature[]>([
      ['point', []],
      ['multipoint', []],
      ['polyline', []],
      ['polygon', []]
    ]);

    for (const feature of fc.features ?? []) {
      if (!feature.geometry) continue;

      const layerType = this.geoJsonGeometryTypeToLayerType(feature.geometry.type);
      if (!layerType) continue;

      map.get(layerType)?.push(feature);
    }

    return map;
  }

  private geoJsonGeometryTypeToLayerType(
    geometryType: GeoJsonFeature['geometry']['type']
  ): GeometryLayerType | null {
    switch (geometryType) {
      case 'Point':
        return 'point';
      case 'MultiPoint':
        return 'multipoint';
      case 'LineString':
      case 'MultiLineString':
        return 'polyline';
      case 'Polygon':
      case 'MultiPolygon':
        return 'polygon';
      default:
        return null;
    }
  }

  private featureToGraphic(feature: GeoJsonFeature, index: number): Graphic | null {
    if (!feature.geometry) return null;

    const geometry = this.toArcGisGeometry(feature.geometry);
    if (!geometry) return null;

    const attributes = {
      OBJECTID: index + 1,
      ...(feature.properties ?? {})
    };

    if (attributes[this.uniqueIdPropertyName] == null) {
      attributes[this.uniqueIdPropertyName] = feature.id ?? `${index + 1}`;
    }

    return new Graphic({
      geometry,
      attributes
    });
  }

  private toArcGisGeometry(
    geometry: NonNullable<GeoJsonFeature['geometry']>
  ): Geometry | null {
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

      case 'Polygon':
        return new Polygon({
          rings: geometry.coordinates,
          spatialReference: { wkid: 4326 }
        });

      case 'MultiPolygon': {
        const rings: number[][][] = [];
        for (const polygon of geometry.coordinates) {
          rings.push(...polygon);
        }
        return new Polygon({
          rings,
          spatialReference: { wkid: 4326 }
        });
      }

      default:
        return null;
    }
  }

  private buildFields(graphics: Graphic[]): __esri.FieldProperties[] {
    const fields: __esri.FieldProperties[] = [
      { name: 'OBJECTID', alias: 'OBJECTID', type: 'oid' }
    ];

    const discovered = new Set<string>(['OBJECTID']);

    for (const graphic of graphics) {
      const attrs = graphic.attributes ?? {};
      for (const [key, value] of Object.entries(attrs)) {
        if (discovered.has(key)) continue;
        discovered.add(key);

        let type: __esri.FieldProperties['type'] = 'string';
        if (typeof value === 'number') {
          type = Number.isInteger(value) ? 'integer' : 'double';
        }

        fields.push({
          name: key,
          alias: key,
          type
        });
      }
    }

    return fields;
  }

  // ============================================================================
  // NEW CHANGE START: popup / click / unique-id for ANY geometry
  // ============================================================================

  private registerLayerEvents(): void {
    if (!this.view) return;

    this.handles.remove('view-click');
    this.handles.remove('view-dblclick');

    this.handles.add(
      this.view.on('click', async (event: __esri.ViewClickEvent) => {
        if (!this.view || this.inDrawingMode) return;

        const hit = await this.view.hitTest(event);

        const result = (hit.results ?? []).find((r: any) => {
          return r?.type === 'graphic' && this.resultBelongsToManagedLayer(r.graphic);
        }) as any;

        if (!result?.graphic) return;

        const graphic = result.graphic as Graphic;
        const uniqueId = graphic.attributes?.[this.uniqueIdPropertyName];

        const nativeEvent = (event as any).native ?? (event as any);
        if (
          this.enableUserEdit &&
          this.enableUserEditRemove &&
          (nativeEvent?.ctrlKey || nativeEvent?.metaKey)
        ) {
          if (uniqueId !== undefined && uniqueId !== null) {
            await this.removeById(uniqueId);
          }
          return;
        }

        if (this.enableUserEdit) {
          await this.activateGraphicsEditor(graphic);
        }

        if (uniqueId !== undefined && uniqueId !== null) {
          await this.openPopup(uniqueId);
        } else {
          const location = this.getPopupLocation(graphic.geometry);
          if (location && this.view.popup && this.popupTemplate) {
            this.view.popup.open({
              features: [graphic],
              location
            });
          }
        }

        this.dispatchEvent(
          new CustomEvent('layerClick', {
            detail: {
              graphic,
              uniqueId,
              attributes: graphic.attributes ?? {}
            },
            bubbles: true,
            composed: true
          })
        );
      }),
      'view-click'
    );

    this.handles.add(
      this.view.on('double-click', async (event: __esri.ViewDoubleClickEvent) => {
        if (!this.view) return;

        const hit = await this.view.hitTest(event);

        const result = (hit.results ?? []).find((r: any) => {
          return r?.type === 'graphic' && this.resultBelongsToManagedLayer(r.graphic);
        }) as any;

        if (!result?.graphic) return;

        this.dispatchEvent(
          new CustomEvent('doubleClick', {
            detail: {
              graphic: result.graphic,
              attributes: result.graphic.attributes ?? {}
            },
            bubbles: true,
            composed: true
          })
        );
      }),
      'view-dblclick'
    );
  }

  private resultBelongsToManagedLayer(graphic: Graphic): boolean {
    const layer = graphic.layer as FeatureLayer | undefined;
    if (!layer) return false;

    for (const managed of this.featureLayers.values()) {
      if (managed === layer) return true;
    }

    return false;
  }

  private updateInfoTemplate(newInfoTemplate: PopupInput): void {
    if (!newInfoTemplate) {
      this.popupTemplate = null;
      this.applyPopupTemplateToAllLayers();
      return;
    }

    if (typeof newInfoTemplate === 'string') {
      this.popupTemplate = new PopupTemplate({
        title: 'Details',
        content: newInfoTemplate
      });
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

  async findFeatureByUniqueId(uniqueId: string | number): Promise<Graphic | undefined> {
    for (const layer of this.featureLayers.values()) {
      const source = (layer as any).source as __esri.Collection<Graphic> | undefined;
      const graphic = source?.find((g: Graphic) => {
        return g.attributes?.[this.uniqueIdPropertyName] === uniqueId;
      });

      if (graphic) return graphic;
    }

    return undefined;
  }

  async openPopup(id: string | number): Promise<void> {
    if (!this.view) return;

    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic) {
      console.warn(`No feature found with ${this.uniqueIdPropertyName}=${id}`);
      return;
    }

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
    if (!graphic || !graphic.geometry) return;

    if (graphic.geometry.type === 'point') {
      await this.view.goTo({
        target: graphic.geometry,
        zoom: zoomLevel
      });
      return;
    }

    await this.view.goTo((graphic.geometry as any).extent ?? graphic.geometry);
  }

  private getPopupLocation(geometry: Geometry): Point | null {
    if (!geometry) return null;

    switch (geometry.type) {
      case 'point':
        return geometry as Point;

      case 'multipoint': {
        const mp = geometry as Multipoint;
        const first = mp.points?.[0];
        if (!first) return null;
        return new Point({
          x: first[0],
          y: first[1],
          spatialReference: mp.spatialReference
        });
      }

      case 'polyline': {
        const line = geometry as Polyline;
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
        const polygon = geometry as Polygon;
        return polygon.extent?.center ?? null;
      }

      case 'extent': {
        const extent = geometry as Extent;
        return extent.center ?? null;
      }

      default:
        return (geometry as any).extent?.center ?? null;
    }
  }

  // ============================================================================
  // NEW CHANGE END
  // ============================================================================

  // ============================================================================
  // NEW CHANGE START: renderer support
  // ============================================================================

  private updateRenderer(newRenderer?: any | null): void {
    for (const [type, layer] of this.featureLayers.entries()) {
      if (newRenderer) {
        const rendererType = newRenderer?.type;

        if (rendererType === 'simple' && this.isRendererCompatible(type, newRenderer)) {
          layer.renderer = new SimpleRenderer(newRenderer);
          continue;
        }

        if (rendererType === 'unique-value') {
          layer.renderer = new UniqueValueRenderer(newRenderer);
          continue;
        }

        if (rendererType === 'class-breaks') {
          layer.renderer = new ClassBreaksRenderer(newRenderer);
          continue;
        }
      }

      layer.renderer = this.createDefaultRenderer(type);
    }
  }

  private isRendererCompatible(type: GeometryLayerType, renderer: any): boolean {
    const symbolType = renderer?.symbol?.type;

    if (type === 'point' || type === 'multipoint') {
      return symbolType === 'simple-marker';
    }

    if (type === 'polyline') {
      return symbolType === 'simple-line';
    }

    if (type === 'polygon') {
      return symbolType === 'simple-fill';
    }

    return false;
  }

  private createDefaultRenderer(type: GeometryLayerType) {
    if (type === 'point' || type === 'multipoint') {
      return new SimpleRenderer({
        symbol: new SimpleMarkerSymbol({
          size: 10,
          outline: { width: 1 }
        })
      });
    }

    if (type === 'polyline') {
      return new SimpleRenderer({
        symbol: new SimpleLineSymbol({
          width: 2
        })
      });
    }

    return new SimpleRenderer({
      symbol: new SimpleFillSymbol({
        color: [0, 122, 255, 0.15],
        outline: { width: 2 }
      })
    });
  }

  // ============================================================================
  // NEW CHANGE END
  // ============================================================================

  private updateLabelJson(newLabelJsonArg: string | object | object[] | undefined): void {
    if (!newLabelJsonArg) {
      for (const layer of this.featureLayers.values()) {
        layer.labelingInfo = [];
        layer.labelsVisible = false;
      }
      return;
    }

    const parsed = typeof newLabelJsonArg === 'string'
      ? JSON.parse(newLabelJsonArg)
      : newLabelJsonArg;

    const labelingInfo = Array.isArray(parsed)
      ? parsed.map((item) => new LabelClass(item as any))
      : [new LabelClass(parsed as any)];

    for (const layer of this.featureLayers.values()) {
      layer.labelingInfo = labelingInfo as any;
      layer.labelsVisible = true;
    }
  }

  // ============================================================================
  // SKETCH / EDIT WORKBENCH (GraphicsLayer only)
  // ============================================================================

  private ensureSketchLayer(): void {
    if (!this.view || this.sketchLayer) return;

    this.sketchLayer = new GraphicsLayer({
      id: `${this.id || 'up-geojson-layer'}-sketch-layer`
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

    this.handles.add(
      this.sketchVM.on('create', (event) => {
        if (event.state !== 'complete' || !event.graphic) return;

        this.inDrawingMode = false;
        this.enableInfoPopupWindow(true);

        const feature = this.graphicToGeoJsonFeature(event.graphic);
        this.appendFeatureToGeoJson(feature);

        this.dispatchEvent(
          new CustomEvent('userDrawItemAdded', {
            detail: feature,
            bubbles: true,
            composed: true
          })
        );

        this.sketchLayer?.removeAll();
      }),
      'sketch-create'
    );

    this.handles.add(
      this.sketchVM.on('update', (event) => {
        if (event.state !== 'complete' || !event.graphics?.length) return;

        this.inDrawingMode = false;
        this.enableInfoPopupWindow(true);

        const graphic = event.graphics[0];
        const feature = this.graphicToGeoJsonFeature(graphic);

        if (this.editingUniqueId != null) {
          (feature.properties as any)[this.uniqueIdPropertyName] = this.editingUniqueId;
          this.updateGeoJsonWithChanges(feature);
        }

        this.dispatchEvent(
          new CustomEvent('userEditItemUpdated', {
            detail: feature,
            bubbles: true,
            composed: true
          })
        );

        this.sketchLayer?.removeAll();
        this.editingUniqueId = null;
      }),
      'sketch-update'
    );
  }

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

    this.inDrawingMode = true;
    this.enableInfoPopupWindow(false);

    this.sketchLayer?.removeAll();
    this.sketchVM.create(tool);
  }

  async cancelDrawing(): Promise<void> {
    this.inDrawingMode = false;
    this.editingUniqueId = null;
    this.sketchVM?.cancel();
    this.sketchLayer?.removeAll();
    this.enableInfoPopupWindow(true);
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

  private async activateGraphicsEditor(featureGraphic: Graphic): Promise<void> {
    if (!this.enableUserEdit || !this.sketchVM || !this.sketchLayer) return;

    const uniqueId = featureGraphic.attributes?.[this.uniqueIdPropertyName];
    this.editingUniqueId = uniqueId ?? null;

    this.sketchLayer.removeAll();

    const clone = featureGraphic.clone();
    this.sketchLayer.add(clone);

    const updateTool = this.getUpdateTool();
    if (!updateTool) return;

    this.enableInfoPopupWindow(false);
    this.sketchVM.update([clone], {
      tool: updateTool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
      multipleSelectionEnabled: false
    });
  }

  private getUpdateTool(): 'transform' | 'reshape' | 'move' | null {
    if (this.enableUserEditVertices || this.enableUserEditAddVertices || this.enableUserEditDeleteVertices) {
      return 'reshape';
    }

    if (this.enableUserEditScaling || this.enableUserEditRotating) {
      return 'transform';
    }

    if (this.enableUserEditMove) {
      return 'move';
    }

    return null;
  }

  async removeById(id: string | number): Promise<void> {
    const feature = await this.findFeatureByUniqueId(id);
    if (!feature) return;

    this.removeFromGeoJson(feature);

    this.dispatchEvent(
      new CustomEvent('userEditItemRemoved', {
        detail: this.graphicToGeoJsonFeature(feature),
        bubbles: true,
        composed: true
      })
    );

    if (this.view?.popup?.visible) {
      this.view.popup.close();
    }
  }

  private appendFeatureToGeoJson(feature: GeoJSON.Feature): void {
    const fc = this.parseFeatureCollection(this.geojson);
    if (!fc) return;

    fc.features.push(feature as any);

    this.suppressGeoJsonUpdate = true;
    this.geojson = fc;
    this.suppressGeoJsonUpdate = false;

    void this.createOrRefreshFeatureLayers();
  }

  private updateGeoJsonWithChanges(updatedFeature: GeoJSON.Feature): void {
    const fc = this.parseFeatureCollection(this.geojson);
    if (!fc) return;

    const updatedId = (updatedFeature.properties as any)?.[this.uniqueIdPropertyName];

    fc.features = fc.features.map((feature) => {
      const featureId =
        feature.properties?.[this.uniqueIdPropertyName] ??
        feature.id;

      return featureId === updatedId
        ? (updatedFeature as any)
        : feature;
    });

    this.suppressGeoJsonUpdate = true;
    this.geojson = fc;
    this.suppressGeoJsonUpdate = false;

    void this.createOrRefreshFeatureLayers();
  }

  private removeFromGeoJson(featureGraphic: Graphic): void {
    const fc = this.parseFeatureCollection(this.geojson);
    if (!fc) return;

    const removeId = featureGraphic.attributes?.[this.uniqueIdPropertyName];

    fc.features = fc.features.filter((feature) => {
      const featureId =
        feature.properties?.[this.uniqueIdPropertyName] ??
        feature.id;
      return featureId !== removeId;
    });

    this.suppressGeoJsonUpdate = true;
    this.geojson = fc;
    this.suppressGeoJsonUpdate = false;

    void this.createOrRefreshFeatureLayers();
  }

  private graphicToGeoJsonFeature(graphic: Graphic): GeoJSON.Feature {
    return {
      type: 'Feature',
      geometry: this.arcGisGeometryToGeoJson(graphic.geometry),
      properties: { ...(graphic.attributes ?? {}) }
    };
  }

  private arcGisGeometryToGeoJson(geometry: Geometry): GeoJSON.Geometry {
    switch (geometry.type) {
      case 'point': {
        const g = geometry as Point;
        return { type: 'Point', coordinates: [g.x, g.y] };
      }
      case 'multipoint': {
        const g = geometry as Multipoint;
        return { type: 'MultiPoint', coordinates: g.points as any };
      }
      case 'polyline': {
        const g = geometry as Polyline;
        if ((g.paths?.length ?? 0) > 1) {
          return { type: 'MultiLineString', coordinates: g.paths as any };
        }
        return { type: 'LineString', coordinates: (g.paths?.[0] ?? []) as any };
      }
      case 'polygon': {
        const g = geometry as Polygon;
        return { type: 'Polygon', coordinates: g.rings as any };
      }
      case 'extent': {
        const g = geometry as Extent;
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
        throw new Error(`Unsupported geometry type: ${(geometry as any).type}`);
    }
  }

  private enableInfoPopupWindow(enable: boolean): void {
    if (typeof this.ancestorMap?.enableInfoWindow === 'function') {
      this.ancestorMap.enableInfoWindow(enable && !this.inDrawingMode);
    }
  }

  private async zoomToAllFeatures(): Promise<void> {
    if (!this.view) return;

    const allGraphics: Graphic[] = [];
    for (const layer of this.featureLayers.values()) {
      const source = (layer as any).source as __esri.Collection<Graphic> | undefined;
      if (source) {
        allGraphics.push(...source.toArray());
      }
    }

    if (!allGraphics.length) return;

    try {
      await this.view.goTo(allGraphics);
    } catch (error) {
      console.warn('goTo(allGraphics) failed.', error);
    }
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'up-geojson-layer': UpGeoJsonLayer;
  }
}
"""
Path('/mnt/data/up-geojson-layer-featurelayer-graphicslayer-skeleton.ts').write_text(content, encoding='utf-8')
print('saved')
