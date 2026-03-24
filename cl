import { LitElement, html } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import type { PropertyValues } from 'lit';

import Graphic from '@arcgis/core/Graphic';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer';
import SketchViewModel from '@arcgis/core/widgets/Sketch/SketchViewModel';

import Point from '@arcgis/core/geometry/Point';
import Multipoint from '@arcgis/core/geometry/Multipoint';
import Polyline from '@arcgis/core/geometry/Polyline';
import Polygon from '@arcgis/core/geometry/Polygon';
import type Geometry from '@arcgis/core/geometry/Geometry';
import type MapView from '@arcgis/core/views/MapView';

type GeoJsonPoint = {
  type: 'Point';
  coordinates: number[];
};

type GeoJsonMultiPoint = {
  type: 'MultiPoint';
  coordinates: number[][];
};

type GeoJsonLineString = {
  type: 'LineString';
  coordinates: number[][];
};

type GeoJsonMultiLineString = {
  type: 'MultiLineString';
  coordinates: number[][][];
};

type GeoJsonPolygon = {
  type: 'Polygon';
  coordinates: number[][][];
};

type GeoJsonMultiPolygon = {
  type: 'MultiPolygon';
  coordinates: number[][][][];
};

type GeoJsonGeometry =
  | GeoJsonPoint
  | GeoJsonMultiPoint
  | GeoJsonLineString
  | GeoJsonMultiLineString
  | GeoJsonPolygon
  | GeoJsonMultiPolygon;

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

type InfoTemplateLike =
  | null
  | {
      title?: string;
      content?: string;
    };

type UpdateTool = 'transform' | 'reshape' | 'move' | null;

@customElement('arc-geojson-layer')
export class ArcGeoJsonLayer extends LitElement {
  // ------------------------------------------------------------------
  // PUBLIC API
  // ------------------------------------------------------------------
  @property({ type: Object })
  geojson: GeoJsonFeatureCollection = {
    type: 'FeatureCollection',
    features: []
  };

  @property({ type: Object })
  infoTemplate: InfoTemplateLike = null;

  @property({ type: Object })
  renderer: any = null;

  @property({ type: String })
  uniqueIdPropertyName = 'id';

  @property({ type: Boolean })
  enableUserEdit = false;

  @property({ type: Boolean })
  enableUserEditMove = false;

  @property({ type: Boolean })
  enableUserEditVertices = false;

  @property({ type: Boolean })
  enableUserEditAddVertices = false;

  @property({ type: Boolean })
  enableUserEditDeleteVertices = false;

  @property({ type: Boolean })
  enableUserEditScaling = false;

  @property({ type: Boolean })
  enableUserEditUniformScaling = false;

  @property({ type: Boolean })
  enableUserEditRotating = false;

  @property({ type: Boolean })
  enableUserEditRemove = false;

  @property({ type: String })
  name = 'Arc GeoJSON Layer';

  // ------------------------------------------------------------------
  // INTERNAL STATE
  // ------------------------------------------------------------------
  @state()
  private view: MapView | null = null;

  private displayLayer: GraphicsLayer | null = null;
  private sketchLayer: GraphicsLayer | null = null;
  private sketchVM: SketchViewModel | null = null;

  private inDrawingMode = false;
  private editingUniqueId: string | number | null = null;

  private suppressMapInteractionUntil = 0;
  private editActivationInProgress = false;
  private editorActive = false;
  private sketchVMCancelledProgrammatically = false;

  private handles = new Map<string, Array<{ remove: () => void }>>();

  // ------------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------------
  connectedCallback(): void {
    super.connectedCallback();
    queueMicrotask(() => {
      this.bootstrap().catch((error) => {
        console.error('ArcGeoJsonLayer bootstrap failed', error);
      });
    });
  }

  disconnectedCallback(): void {
    super.disconnectedCallback();

    this.removeHandlesByKey('view-click');
    this.removeHandlesByKey('native-dblclick');
    this.removeHandlesByKey('sketch-create');
    this.removeHandlesByKey('sketch-update');

    this.cancelSketchVM();
    this.sketchLayer?.removeAll();
  }

  protected updated(changed: PropertyValues<this>): void {
    if (changed.has('geojson') || changed.has('infoTemplate') || changed.has('renderer')) {
      void this.refreshDisplayLayer();
    }

    if (
      changed.has('enableUserEditMove') ||
      changed.has('enableUserEditVertices') ||
      changed.has('enableUserEditAddVertices') ||
      changed.has('enableUserEditDeleteVertices') ||
      changed.has('enableUserEditScaling') ||
      changed.has('enableUserEditUniformScaling') ||
      changed.has('enableUserEditRotating')
    ) {
      this.syncEditingState();
    }

    if (changed.has('enableUserEdit')) {
      this.enableInfoPopupWindow(true);
    }
  }

  protected render() {
    return html``;
  }

  // ------------------------------------------------------------------
  // BOOTSTRAP
  // ------------------------------------------------------------------
  private async bootstrap(): Promise<void> {
    this.view = this.resolveAncestorMapView();

    if (!this.view) {
      console.warn('ArcGeoJsonLayer: no MapView found on ancestor map component');
      return;
    }

    this.ensureDisplayLayer();
    this.ensureSketchLayer();
    this.ensureSketchViewModel();
    this.registerLayerEvents();

    await this.refreshDisplayLayer();
  }

  private resolveAncestorMapView(): MapView | null {
    let node: any = this;

    while (node) {
      const parent = node.parentNode ?? node.host ?? null;
      if (!parent) break;

      if ((parent as any).view) {
        return (parent as any).view as MapView;
      }

      node = parent;
    }

    return null;
  }

  // ------------------------------------------------------------------
  // HANDLE HELPERS
  // ------------------------------------------------------------------
  private addHandle(handle: { remove: () => void }, key: string): void {
    const list = this.handles.get(key) ?? [];
    list.push(handle);
    this.handles.set(key, list);
  }

  private removeHandlesByKey(key: string): void {
    const list = this.handles.get(key) ?? [];
    for (const handle of list) {
      try {
        handle.remove();
      } catch {
        // ignore
      }
    }
    this.handles.delete(key);
  }

  // ------------------------------------------------------------------
  // CANCEL HELPER
  // ------------------------------------------------------------------
  private cancelSketchVM(): void {
    if (!this.sketchVM) return;
    this.sketchVMCancelledProgrammatically = true;
    this.sketchVM.cancel();
    setTimeout(() => {
      this.sketchVMCancelledProgrammatically = false;
    }, 0);
  }

  // ------------------------------------------------------------------
  // LAYERS
  // ------------------------------------------------------------------
  private ensureDisplayLayer(): void {
    if (!this.view || this.displayLayer) return;

    this.displayLayer = new GraphicsLayer({
      title: this.name,
      listMode: 'show'
    });

    this.view.map.add(this.displayLayer);
  }

  private ensureSketchLayer(): void {
    if (!this.view || this.sketchLayer) return;

    this.sketchLayer = new GraphicsLayer({
      title: `${this.name} - sketch`,
      listMode: 'hide'
    });

    this.view.map.add(this.sketchLayer);
  }

  private async refreshDisplayLayer(): Promise<void> {
    if (!this.view) return;

    this.ensureDisplayLayer();
    if (!this.displayLayer) return;

    if (this.editorActive) return;

    this.displayLayer.removeAll();

    const features = this.getFeatureCollection().features;
    const graphics: Graphic[] = [];

    for (const feature of features) {
      const graphic = this.featureToGraphic(feature);
      if (graphic) {
        graphics.push(graphic);
      }
    }

    if (graphics.length) {
      this.displayLayer.addMany(graphics);
    }
  }

  // ------------------------------------------------------------------
  // POPUP HELPERS
  // ------------------------------------------------------------------
  private shouldSuppressMapInteraction(): boolean {
    return Date.now() < this.suppressMapInteractionUntil;
  }

  private closeMapPopup(): void {
    const popup = (this.view as any)?.popup;
    if (!popup) return;

    if (typeof popup.close === 'function') {
      popup.close();
    } else {
      popup.visible = false;
      if ('features' in popup) {
        popup.features = [];
      }
    }
  }

  private openMapPopup(graphic: Graphic, location: Point): void {
    const popup = (this.view as any)?.popup;
    if (!popup) return;

    if (typeof popup.open === 'function') {
      popup.open({
        features: [graphic],
        location
      });
    }
  }

  private enableInfoPopupWindow(enable: boolean): void {
    if (!this.view) return;

    const allowPopup =
      enable &&
      !this.enableUserEdit &&
      !this.inDrawingMode &&
      !this.editorActive;

    if (!allowPopup) {
      this.closeMapPopup();
    }
  }

  // ------------------------------------------------------------------
  // EDITING STATE
  // ------------------------------------------------------------------
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

  private getUpdateTool(): UpdateTool {
    if (
      this.enableUserEditVertices ||
      this.enableUserEditAddVertices ||
      this.enableUserEditDeleteVertices
    ) {
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

  // ------------------------------------------------------------------
  // DRAW / EDIT ENTRY
  // ------------------------------------------------------------------
  async startDrawing(drawGeometryType: string): Promise<void> {
    if (!this.sketchVM) {
      this.ensureSketchLayer();
      this.ensureSketchViewModel();
    }
    if (!this.sketchVM || !this.sketchLayer) return;

    const tool = this.determineSketchCreateTool(drawGeometryType);
    if (!tool) {
      console.error(`Unsupported draw geometry type: ${drawGeometryType}`);
      return;
    }

    this.cancelSketchVM();
    this.sketchLayer.removeAll();

    this.closeMapPopup();

    this.inDrawingMode = true;
    this.editingUniqueId = null;
    this.editorActive = false;

    this.enableInfoPopupWindow(false);

    this.sketchVM.create(tool);
  }

  async cancelDrawing(): Promise<void> {
    this.inDrawingMode = false;
    this.editingUniqueId = null;
    this.editorActive = false;

    this.cancelSketchVM();
    this.sketchLayer?.removeAll();

    this.closeMapPopup();
    this.enableInfoPopupWindow(true);
  }

  private async activateGraphicsEditor(featureGraphic: Graphic): Promise<void> {
    if (!this.enableUserEdit || !this.sketchVM || !this.sketchLayer) return;
    if (this.editorActive) return;

    const uniqueId = featureGraphic.attributes?.[this.uniqueIdPropertyName];
    this.editingUniqueId = uniqueId ?? null;

    this.closeMapPopup();
    this.enableInfoPopupWindow(false);

    this.cancelSketchVM();
    this.sketchLayer.removeAll();

    const editGraphic = featureGraphic.clone();
    editGraphic.popupTemplate = null;

    this.sketchLayer.add(editGraphic);

    this.syncEditingState();

    const updateTool = this.getUpdateTool();
    if (!updateTool) {
      console.warn(
        'ArcGeoJsonLayer: No update tool configured. ' +
        'Enable at least one of: enableUserEditMove, enableUserEditVertices, ' +
        'enableUserEditScaling, enableUserEditRotating.'
      );
      return;
    }

    // Give the graphics layer a full render tick before sketchVM.update() picks up the graphic
    await new Promise<void>((resolve) => setTimeout(resolve, 0));

    this.editorActive = true;

    this.sketchVM.update([editGraphic], {
      tool: updateTool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
      multipleSelectionEnabled: false
    });
  }

  // ------------------------------------------------------------------
  // SKETCH VM
  // ------------------------------------------------------------------
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

    this.addHandle(
      this.sketchVM.on('create', async (event: any) => {
        if (event.state !== 'complete' || !event.graphic) return;

        const createdGraphic = event.graphic;
        createdGraphic.popupTemplate = null;

        if (!createdGraphic.attributes) {
          createdGraphic.attributes = {};
        }

        if (
          createdGraphic.attributes[this.uniqueIdPropertyName] === undefined ||
          createdGraphic.attributes[this.uniqueIdPropertyName] === null
        ) {
          createdGraphic.attributes[this.uniqueIdPropertyName] =
            crypto.randomUUID?.() ?? `id-${Date.now()}`;
        }

        const feature = this.graphicToGeoJsonFeature(createdGraphic);
        await this.appendFeatureToGeoJson(feature);

        this.dispatchEvent(
          new CustomEvent('userDrawItemAdded', {
            detail: feature,
            bubbles: true,
            composed: true
          })
        );

        this.inDrawingMode = false;
        this.editingUniqueId = null;
        this.editorActive = false;

        this.cancelSketchVM();
        this.sketchLayer?.removeAll();

        this.closeMapPopup();
        this.enableInfoPopupWindow(true);

        this.suppressMapInteractionUntil = Date.now() + 80;

        await this.refreshDisplayLayer();
      }),
      'sketch-create'
    );

    this.addHandle(
      this.sketchVM.on('update', async (event: any) => {
        if (event.state === 'start') {
          this.editorActive = true;
          this.closeMapPopup();
          return;
        }

        if (event.state !== 'complete') return;

        // Ignore complete events we triggered ourselves via cancelSketchVM()
        if (this.sketchVMCancelledProgrammatically) return;

        if (!event.graphics?.length) return;

        const updatedGraphic = event.graphics[0];
        updatedGraphic.popupTemplate = null;

        const feature = this.graphicToGeoJsonFeature(updatedGraphic);

        if (this.editingUniqueId != null) {
          (feature.properties as any)[this.uniqueIdPropertyName] = this.editingUniqueId;
          await this.updateGeoJsonWithChanges(feature);
        }

        this.dispatchEvent(
          new CustomEvent('userEditItemUpdated', {
            detail: feature,
            bubbles: true,
            composed: true
          })
        );

        this.inDrawingMode = false;
        this.editingUniqueId = null;
        this.editorActive = false;

        this.cancelSketchVM();
        this.sketchLayer?.removeAll();

        this.closeMapPopup();
        this.enableInfoPopupWindow(true);

        this.suppressMapInteractionUntil = Date.now() + 80;

        await this.refreshDisplayLayer();
      }),
      'sketch-update'
    );
  }

  // ------------------------------------------------------------------
  // EVENTS
  // ------------------------------------------------------------------
  private registerLayerEvents(): void {
    if (!this.view) return;

    this.removeHandlesByKey('view-click');
    this.removeHandlesByKey('native-dblclick');

    this.addHandle(
      this.view.on('click', async (event: any) => {
        if (!this.view || this.inDrawingMode || this.editorActive) return;
        if (this.shouldSuppressMapInteraction()) return;

        const nativeEvent = event?.native ?? event;

        if (this.enableUserEdit) {
          const hitForRemove = await this.view.hitTest(event);
          const removeResult = (hitForRemove.results ?? []).find((r: any) =>
            this.resultBelongsToManagedLayerResult(r)
          ) as any;

          if (
            removeResult?.graphic &&
            this.enableUserEditRemove &&
            (nativeEvent?.ctrlKey || nativeEvent?.metaKey)
          ) {
            const uniqueId =
              removeResult.graphic.attributes?.[this.uniqueIdPropertyName];

            if (uniqueId !== undefined && uniqueId !== null) {
              await this.removeById(uniqueId);
            }
          }

          this.closeMapPopup();
          return;
        }

        const hit = await this.view.hitTest(event);

        const result = (hit.results ?? []).find((r: any) =>
          this.resultBelongsToManagedLayerResult(r)
        ) as any;

        if (!result?.graphic) {
          this.closeMapPopup();
          return;
        }

        const graphic = result.graphic as Graphic;
        const uniqueId = graphic.attributes?.[this.uniqueIdPropertyName];
        const location = event.mapPoint ?? this.getPopupLocation(graphic.geometry);

        if (location) {
          this.openMapPopup(graphic, location);
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

    const container = this.view.container as HTMLElement | null;
    if (!container) return;

    const nativeDblClickHandler = async (evt: MouseEvent) => {
      if (!this.view || this.inDrawingMode || this.editorActive) return;
      if (this.shouldSuppressMapInteraction()) return;
      if (this.editActivationInProgress) return;

      evt.preventDefault();
      evt.stopPropagation();

      const rect = container.getBoundingClientRect();
      const screenPoint = {
        x: evt.clientX - rect.left,
        y: evt.clientY - rect.top
      };

      const hit = await this.view.hitTest(screenPoint as any);

      const result = (hit.results ?? []).find((r: any) =>
        this.resultBelongsToManagedLayerResult(r)
      ) as any;

      if (!result?.graphic) {
        this.closeMapPopup();
        return;
      }

      const graphic = result.graphic as Graphic;
      const uniqueId = graphic.attributes?.[this.uniqueIdPropertyName];

      if (this.enableUserEdit) {
        this.editActivationInProgress = true;
        try {
          this.closeMapPopup();
          await this.activateGraphicsEditor(graphic);
        } catch (err) {
          console.error('ArcGeoJsonLayer: editor activation failed', err);
          this.editorActive = false;
        } finally {
          this.editActivationInProgress = false;
        }
      } else {
        const location = this.getPopupLocation(graphic.geometry);
        if (location) {
          this.openMapPopup(graphic, location);
        }
      }

      this.dispatchEvent(
        new CustomEvent('doubleClick', {
          detail: {
            graphic,
            uniqueId,
            attributes: graphic.attributes ?? {}
          },
          bubbles: true,
          composed: true
        })
      );
    };

    container.addEventListener('dblclick', nativeDblClickHandler);

    this.addHandle(
      {
        remove: () => container.removeEventListener('dblclick', nativeDblClickHandler)
      },
      'native-dblclick'
    );
  }

  // ------------------------------------------------------------------
  // PUBLIC HELPERS
  // ------------------------------------------------------------------
  async zoomTo(id?: string | number, zoom?: number): Promise<void> {
    if (!this.view || !this.displayLayer) return;

    const graphic = this.findDisplayGraphicById(id);
    if (!graphic) return;

    if (zoom != null && graphic.geometry.type === 'point') {
      await this.view.goTo({
        target: graphic.geometry,
        zoom
      });
      return;
    }

    await this.view.goTo(graphic);
  }

  async openPopupById(id: string | number): Promise<void> {
    if (!this.view || !this.displayLayer) return;

    const graphic = this.findDisplayGraphicById(id);
    if (!graphic) return;

    const location = this.getPopupLocation(graphic.geometry);
    if (!location) return;

    this.openMapPopup(graphic, location);
  }

  // ------------------------------------------------------------------
  // GRAPHIC LOOKUP
  // ------------------------------------------------------------------
  private findDisplayGraphicById(id?: string | number): Graphic | null {
    if (!this.displayLayer || id === undefined || id === null) return null;

    const graphics = this.displayLayer.graphics.toArray();
    return (
      graphics.find(
        (g) => g.attributes?.[this.uniqueIdPropertyName] === id
      ) ?? null
    );
  }

  private resultBelongsToManagedLayerResult(result: any): boolean {
    return result?.type === 'graphic' && result?.graphic?.layer === this.displayLayer;
  }

  // ------------------------------------------------------------------
  // GEOJSON ACCESS
  // ------------------------------------------------------------------
  private getFeatureCollection(): GeoJsonFeatureCollection {
    if (!this.geojson || this.geojson.type !== 'FeatureCollection') {
      return {
        type: 'FeatureCollection',
        features: []
      };
    }

    return this.geojson;
  }

  private async appendFeatureToGeoJson(feature: GeoJsonFeature): Promise<void> {
    const fc = this.getFeatureCollection();
    this.geojson = {
      ...fc,
      features: [...fc.features, feature]
    };
  }

  private async updateGeoJsonWithChanges(feature: GeoJsonFeature): Promise<void> {
    const fc = this.getFeatureCollection();
    const featureId =
      feature.properties?.[this.uniqueIdPropertyName] ?? feature.id;

    this.geojson = {
      ...fc,
      features: fc.features.map((f) => {
        const currentId = f.properties?.[this.uniqueIdPropertyName] ?? f.id;
        return currentId === featureId ? feature : f;
      })
    };
  }

  private async removeById(id: string | number): Promise<void> {
    const fc = this.getFeatureCollection();

    const removed = fc.features.find((f) => {
      const currentId = f.properties?.[this.uniqueIdPropertyName] ?? f.id;
      return currentId === id;
    });

    this.geojson = {
      ...fc,
      features: fc.features.filter((f) => {
        const currentId = f.properties?.[this.uniqueIdPropertyName] ?? f.id;
        return currentId !== id;
      })
    };

    await this.refreshDisplayLayer();
    this.closeMapPopup();

    if (removed) {
      this.dispatchEvent(
        new CustomEvent('userEditItemRemoved', {
          detail: removed,
          bubbles: true,
          composed: true
        })
      );
    }
  }

  // ------------------------------------------------------------------
  // GEOJSON -> GRAPHIC
  // ------------------------------------------------------------------
  private featureToGraphic(feature: GeoJsonFeature): Graphic | null {
    if (!feature.geometry) return null;

    const geometry = this.toArcGisGeometry(feature.geometry);
    if (!geometry) return null;

    const attributes: Record<string, any> = {
      ...(feature.properties ?? {})
    };

    const featureId =
      feature.id ?? attributes[this.uniqueIdPropertyName] ?? crypto.randomUUID?.() ?? `id-${Date.now()}`;

    attributes[this.uniqueIdPropertyName] = featureId;

    const symbol = this.getSymbolForGeometry(geometry.type);

    return new Graphic({
      geometry,
      attributes,
      symbol,
      popupTemplate: this.enableUserEdit ? null : this.buildPopupTemplate(attributes)
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
          const first = ring[0];
          const last = ring[ring.length - 1];
          if (!first || !last) return ring;
          if (first[0] !== last[0] || first[1] !== last[1]) {
            return [...ring, [...first]];
          }
          return ring;
        });

        return new Polygon({
          rings,
          spatialReference: { wkid: 4326 }
        });
      }

      case 'MultiPolygon': {
        const rings: number[][][] = [];
        for (const polygon of geometry.coordinates) {
          for (const ring of polygon) {
            const first = ring[0];
            const last = ring[ring.length - 1];
            if (!first || !last) {
              rings.push(ring);
              continue;
            }
            if (first[0] !== last[0] || first[1] !== last[1]) {
              rings.push([...ring, [...first]]);
            } else {
              rings.push(ring);
            }
          }
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

  // ------------------------------------------------------------------
  // GRAPHIC -> GEOJSON
  // ------------------------------------------------------------------
  private graphicToGeoJsonFeature(graphic: Graphic): GeoJsonFeature {
    const geometry = graphic.geometry;
    const properties = { ...(graphic.attributes ?? {}) };
    const featureId = properties[this.uniqueIdPropertyName] ?? graphic.attributes?.[this.uniqueIdPropertyName];

    let geojsonGeometry: GeoJsonGeometry | null = null;

    if (geometry?.type === 'point') {
      const point = geometry as Point;
      geojsonGeometry = {
        type: 'Point',
        coordinates: [point.longitude ?? point.x, point.latitude ?? point.y]
      };
    } else if (geometry?.type === 'multipoint') {
      const multipoint = geometry as Multipoint;
      geojsonGeometry = {
        type: 'MultiPoint',
        coordinates: multipoint.points.map((p) => [p[0], p[1]])
      };
    } else if (geometry?.type === 'polyline') {
      const polyline = geometry as Polyline;
      if (polyline.paths.length <= 1) {
        geojsonGeometry = {
          type: 'LineString',
          coordinates: polyline.paths[0] ?? []
        };
      } else {
        geojsonGeometry = {
          type: 'MultiLineString',
          coordinates: polyline.paths
        };
      }
    } else if (geometry?.type === 'polygon') {
      const polygon = geometry as Polygon;

      geojsonGeometry = {
        type: 'Polygon',
        coordinates: polygon.rings.map((ring) => {
          const first = ring[0];
          const last = ring[ring.length - 1];
          if (!first || !last) return ring as number[][];
          if (first[0] !== last[0] || first[1] !== last[1]) {
            return [...ring, [...first]] as number[][];
          }
          return ring as number[][];
        })
      };
    }

    return {
      type: 'Feature',
      id: featureId,
      geometry: geojsonGeometry,
      properties
    };
  }

  // ------------------------------------------------------------------
  // POPUP TEMPLATE
  // ------------------------------------------------------------------
  private buildPopupTemplate(attributes: Record<string, any>): any {
    if (!this.infoTemplate) {
      return {
        title: 'Details',
        content: Object.entries(attributes)
          .map(([key, value]) => `<div><b>${key}:</b> ${String(value)}</div>`)
          .join('')
      };
    }

    const title = this.interpolateTemplate(this.infoTemplate.title ?? 'Details', attributes);
    const content = this.interpolateTemplate(this.infoTemplate.content ?? '', attributes);

    return { title, content };
  }

  private interpolateTemplate(template: string, attributes: Record<string, any>): string {
    return template.replace(/\$\{([^}]+)\}/g, (_, key: string) => {
      const value = attributes[key.trim()];
      return value == null ? '' : String(value);
    });
  }

  private getPopupLocation(geometry: Geometry): Point | null {
    if (!geometry) return null;

    if (geometry.type === 'point') {
      return geometry as Point;
    }

    const extent = geometry.extent;
    if (extent?.center) {
      return extent.center as Point;
    }

    return null;
  }

  // ------------------------------------------------------------------
  // SYMBOLS
  // ------------------------------------------------------------------
  private getSymbolForGeometry(geometryType: string): any {
    if (this.renderer?.type === 'simple' && this.renderer?.symbol) {
      return this.renderer.symbol;
    }

    switch (geometryType) {
      case 'point':
      case 'multipoint':
        return {
          type: 'simple-marker',
          color: [255, 0, 0, 1],
          size: 10,
          outline: { color: [0, 0, 0, 1], width: 1 }
        };

      case 'polyline':
        return {
          type: 'simple-line',
          color: [0, 0, 0, 1],
          width: 3
        };

      case 'polygon':
      default:
        return {
          type: 'simple-fill',
          color: [173, 216, 230, 0.35],
          outline: { color: [0, 0, 0, 1], width: 2 }
        };
    }
  }

  // ------------------------------------------------------------------
  // DRAW TOOL MAPPING
  // ------------------------------------------------------------------
  private determineSketchCreateTool(drawGeometryType: string): string | null {
    switch (drawGeometryType.toLowerCase()) {
      case 'point':      return 'point';
      case 'multipoint': return 'multipoint';
      case 'line':
      case 'polyline':
      case 'linestring': return 'polyline';
      case 'polygon':    return 'polygon';
      case 'rectangle':  return 'rectangle';
      case 'circle':     return 'circle';
      default:           return null;
    }
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'arc-geojson-layer': ArcGeoJsonLayer;
  }
}
