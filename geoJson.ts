import { LitElement, nothing } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';

import Graphic from '@arcgis/core/Graphic';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer';
import PopupTemplate from '@arcgis/core/PopupTemplate';
import MapView from '@arcgis/core/views/MapView';
import SceneView from '@arcgis/core/views/SceneView';
import SketchViewModel from '@arcgis/core/widgets/Sketch/SketchViewModel';
import SimpleMarkerSymbol from '@arcgis/core/symbols/SimpleMarkerSymbol';
import SimpleLineSymbol from '@arcgis/core/symbols/SimpleLineSymbol';
import SimpleFillSymbol from '@arcgis/core/symbols/SimpleFillSymbol';
import TextSymbol from '@arcgis/core/symbols/TextSymbol';

import Point from '@arcgis/core/geometry/Point';
import Polyline from '@arcgis/core/geometry/Polyline';
import Polygon from '@arcgis/core/geometry/Polygon';
import Multipoint from '@arcgis/core/geometry/Multipoint';
import type Geometry from '@arcgis/core/geometry/Geometry';
import type Handle from '@arcgis/core/core/Handle';
import type Renderer from '@arcgis/core/renderers/Renderer';

import DrawEditUtils from '../../common/draw-edit-utils';

type ArcgisView = MapView | SceneView;
type FeatureCollectionLike = {
  type: 'FeatureCollection';
  features: Array<{
    type: 'Feature';
    id?: string | number;
    geometry: {
      type: 'Point' | 'LineString' | 'Polygon' | 'MultiPoint';
      coordinates: any;
    } | null;
    properties?: Record<string, any>;
  }>;
};

type InfoTemplateDetails = {
  title?: string;
  details?: string;
};

type LabelJsonType = string | object | object[] | undefined;

type ArcMapLike = HTMLElement & {
  getViewInstance?: () => Promise<ArcgisView>;
  viewOnReady?: () => Promise<void>;
  enableInfoWindow?: (enable: boolean) => void;
};

@customElement('arc-geojson-layer')
export class ArcGeojsonLayer extends LitElement {
  createRenderRoot() {
    return this;
  }

  private static readonly DEFAULT_SYMBOL_COLOR = [0, 122, 255, 180];
  private static readonly DEFAULT_SYMBOL_LINE_WIDTH = 2;
  private static readonly DEFAULT_SYMBOL_MARKER_SIZE = 10;
  private static readonly DEFAULT_LABEL_SIZE = 10;
  private static readonly DEFAULT_LABEL_COLOR = [0, 0, 0, 255];

  private ancestorMap: ArcMapLike | null = null;
  private view: ArcgisView | null = null;

  private graphicsLayer: GraphicsLayer | null = null;
  private labelLayer: GraphicsLayer | null = null;

  private sketchVM: SketchViewModel | null = null;
  private viewClickHandle: Handle | null = null;
  private sketchCreateHandle: Handle | null = null;
  private sketchUpdateHandle: Handle | null = null;

  private blockGeoJsonUpdate = false;
  private removingItem = false;

  @state()
  private inDrawingMode = false;

  @property({ attribute: false })
  geojson: string | FeatureCollectionLike = {
    type: 'FeatureCollection',
    features: [],
  };

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

  @property({ attribute: 'info-template' })
  infoTemplate: string | InfoTemplateDetails = '{}';

  @property({ attribute: 'label-json' })
  labelJson: LabelJsonType;

  @property({ attribute: 'label-color' })
  labelColor: string | number[] = ArcGeojsonLayer.DEFAULT_LABEL_COLOR;

  @property({ type: Number, attribute: 'label-size' })
  labelSize = ArcGeojsonLayer.DEFAULT_LABEL_SIZE;

  @property({ type: String, attribute: 'layer-class' })
  layerClass = '';

  @property({ type: String, reflect: true })
  name = '';

  @property({ attribute: false })
  renderer?: Renderer | any;

  @property({ type: String, attribute: 'unique-id-property-name' })
  uniqueIdPropertyName = 'id';

  connectedCallback(): void {
    super.connectedCallback();
  }

  async firstUpdated(): Promise<void> {
    await this.resolveViewFromAncestor();
    await this.initializeLayers();
    await this.attachMapClickHandler();
    await this.updateGeojsonInternal(this.geojson);
  }

  async updated(changedProps: Map<string, unknown>): Promise<void> {
    if (changedProps.has('enableUserEdit') && this.sketchVM) {
      this.enableInfoPopupWindow(!this.enableUserEdit);
    }

    if (changedProps.has('renderer')) {
      this.applyRendererToAllGraphics();
    }

    if (
      changedProps.has('labelJson') ||
      changedProps.has('labelColor') ||
      changedProps.has('labelSize')
    ) {
      this.refreshLabels();
    }

    if (changedProps.has('infoTemplate')) {
      this.applyPopupTemplateToAllGraphics();
    }

    if (changedProps.has('geojson') && !this.blockGeoJsonUpdate) {
      await this.updateGeojsonInternal(this.geojson);
    }
  }

  render() {
    return nothing;
  }

  private async resolveViewFromAncestor(): Promise<void> {
    this.ancestorMap = this.closest('arc-map') as ArcMapLike | null;

    if (!this.ancestorMap) {
      console.error('<arc-geojson-layer> must be a descendant of <arc-map>.');
      return;
    }

    if (typeof this.ancestorMap.viewOnReady === 'function') {
      await this.ancestorMap.viewOnReady();
    }

    if (typeof this.ancestorMap.getViewInstance === 'function') {
      this.view = await this.ancestorMap.getViewInstance();
    }

    if (!this.view) {
      console.error('Unable to resolve ArcGIS view instance from <arc-map>.');
    }
  }

  private async initializeLayers(): Promise<void> {
    if (!this.view) return;

    if (!this.graphicsLayer) {
      this.graphicsLayer = new GraphicsLayer({
        id: `${this.id || 'arc-geojson-layer'}-graphics`,
        listMode: 'show',
      });
      this.view.map.add(this.graphicsLayer);
    }

    if (!this.labelLayer) {
      this.labelLayer = new GraphicsLayer({
        id: `${this.id || 'arc-geojson-layer'}-labels`,
        listMode: 'show',
      });
      this.view.map.add(this.labelLayer);
    }

    if (!this.sketchVM && this.graphicsLayer) {
      this.sketchVM = new SketchViewModel({
        view: this.view,
        layer: this.graphicsLayer,
        defaultUpdateOptions: {
          enableRotation: this.enableUserEditRotating,
          enableScaling: this.enableUserEditScaling,
          preserveAspectRatio: this.enableUserEditUniformScaling,
          multipleSelectionEnabled: false,
          toggleToolOnClick: false,
        },
      });

      this.attachSketchHandlers();
    }
  }

  private attachSketchHandlers(): void {
    if (!this.sketchVM) return;

    this.sketchCreateHandle?.remove();
    this.sketchUpdateHandle?.remove();

    this.sketchCreateHandle = this.sketchVM.on('create', (event) => {
      if (event.state === 'start') {
        this.inDrawingMode = true;
        this.enableInfoPopupWindow(false);
      }

      if (event.state === 'complete') {
        const graphic = event.graphic;
        this.inDrawingMode = false;
        this.enableInfoPopupWindow(true);

        this.ensureGraphicIds(graphic);
        this.decorateGraphic(graphic);
        this.syncGeojsonFromLayer();
        this.refreshLabels();

        this.dispatchEvent(
          new CustomEvent('userDrawItemAdded', {
            detail: this.graphicToGeojsonFeature(graphic),
            bubbles: true,
            composed: true,
          })
        );
      }

      if (event.state === 'cancel') {
        this.inDrawingMode = false;
        this.enableInfoPopupWindow(true);
      }
    });

    this.sketchUpdateHandle = this.sketchVM.on('update', (event) => {
      if (event.state === 'start') {
        this.enableInfoPopupWindow(false);
      }

      if (event.state === 'complete') {
        this.enableInfoPopupWindow(true);

        if (event.graphics?.length) {
          event.graphics.forEach((g) => this.decorateGraphic(g));
          this.syncGeojsonFromLayer();
          this.refreshLabels();

          this.dispatchEvent(
            new CustomEvent('userEditItemUpdated', {
              detail: event.graphics.map((g) => this.graphicToGeojsonFeature(g)),
              bubbles: true,
              composed: true,
            })
          );
        }
      }

      if (event.state === 'cancel') {
        this.enableInfoPopupWindow(true);
      }
    });
  }

  private async attachMapClickHandler(): Promise<void> {
    if (!this.view || this.viewClickHandle) return;

    this.viewClickHandle = this.view.on('click', async (event) => {
      if (!this.view || !this.graphicsLayer) return;

      const hit = await this.view.hitTest(event);
      const result = hit.results.find((r: any) => {
        return r.type === 'graphic' && r.graphic && r.graphic.layer === this.graphicsLayer;
      }) as any;

      if (!result?.graphic) return;

      const graphic = result.graphic as Graphic;

      const uniqueId = graphic.attributes?.[this.uniqueIdPropertyName];

      this.dispatchEvent(
        new CustomEvent('layerClick', {
          detail: {
            graphic,
            uniqueId,
            attributes: graphic.attributes ?? {},
            mapPoint: event.mapPoint,
          },
          bubbles: true,
          composed: true,
        })
      );

      if (this.enableUserEdit) {
        if (event.native?.ctrlKey && this.enableUserEditRemove) {
          this.removingItem = true;
          this.removeGraphic(graphic);
          this.removingItem = false;
          return;
        }

        await this.activateGraphicEditor(graphic);
        return;
      }

      if (uniqueId !== undefined && uniqueId !== null) {
        await this.openPopup(uniqueId);
      } else {
        await this.openPopupForGraphic(graphic);
      }
    });

    this.view.on('double-click', async (event) => {
      if (!this.view || !this.graphicsLayer) return;

      const hit = await this.view.hitTest(event);
      const result = hit.results.find((r: any) => {
        return r.type === 'graphic' && r.graphic && r.graphic.layer === this.graphicsLayer;
      }) as any;

      if (!result?.graphic) return;

      this.dispatchEvent(
        new CustomEvent('doubleClick', {
          detail: {
            graphic: result.graphic,
            attributes: result.graphic.attributes ?? {},
            mapPoint: event.mapPoint,
          },
          bubbles: true,
          composed: true,
        })
      );
    });

    this.view.on('pointer-move', async (event) => {
      if (!this.view || !this.graphicsLayer) return;

      const hit = await this.view.hitTest(event);
      const result = hit.results.find((r: any) => {
        return r.type === 'graphic' && r.graphic && r.graphic.layer === this.graphicsLayer;
      }) as any;

      if (result?.graphic) {
        this.dispatchEvent(
          new CustomEvent('layerMouseOver', {
            detail: {
              graphic: result.graphic,
              attributes: result.graphic.attributes ?? {},
            },
            bubbles: true,
            composed: true,
          })
        );
      } else {
        this.dispatchEvent(
          new CustomEvent('layerMouseOut', {
            detail: {},
            bubbles: true,
            composed: true,
          })
        );
      }
    });
  }

  async startDrawing(drawGeometryType: string): Promise<void> {
    if (!this.sketchVM || !this.graphicsLayer) return;

    const layerGeometryType = this.getCurrentLayerGeometryType();

    if (layerGeometryType && !DrawEditUtils.validGeometryType(drawGeometryType, layerGeometryType)) {
      return;
    }

    const sketchTool = DrawEditUtils.determineSketchCreateTool(drawGeometryType);
    const freehand = DrawEditUtils.isFreehand(drawGeometryType);

    this.inDrawingMode = true;
    this.enableInfoPopupWindow(false);

    this.sketchVM.create(sketchTool, freehand ? { mode: 'freehand' } : undefined);
  }

  async cancelDrawing(): Promise<void> {
    this.inDrawingMode = false;
    this.sketchVM?.cancel();
    this.enableInfoPopupWindow(true);
  }

  async findFeatureByUniqueId(uniqueId: string | number): Promise<Graphic | undefined> {
    return this.graphicsLayer?.graphics.find((graphic) => {
      return graphic.attributes?.[this.uniqueIdPropertyName] === uniqueId;
    });
  }

  async getLayerId(): Promise<string> {
    return this.graphicsLayer?.id ?? '';
  }

  async openPopup(id: string | number): Promise<void> {
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic) {
      console.warn(
        `No feature found with ${this.uniqueIdPropertyName} value "${id}". Cannot open popup.`
      );
      return;
    }

    await this.openPopupForGraphic(graphic);
  }

  async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {
    const graphic = await this.findFeatureByUniqueId(id);
    if (!graphic || !this.view) return;

    const geometry = graphic.geometry;
    if (!geometry) return;

    if (geometry.type === 'point') {
      await this.view.goTo({ target: geometry, zoom: zoomLevel });
      return;
    }

    await this.view.goTo(geometry.extent ?? geometry);
  }

  private async openPopupForGraphic(graphic: Graphic): Promise<void> {
    if (!this.view) return;

    this.decorateGraphic(graphic);

    await this.view.openPopup({
      features: [graphic],
      location: this.getPopupPoint(graphic.geometry),
    });
  }

  private async activateGraphicEditor(graphic: Graphic): Promise<void> {
    if (!this.sketchVM) return;

    const updateOptions: any = {
      tool: this.getUpdateToolName(),
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      multipleSelectionEnabled: false,
      toggleToolOnClick: false,
    };

    this.sketchVM.update(graphic, updateOptions);
  }

  private getUpdateToolName(): 'move' | 'reshape' | 'transform' {
    if (this.enableUserEditVertices || this.enableUserEditAddVertices || this.enableUserEditDeleteVertices) {
      return 'reshape';
    }

    if (this.enableUserEditScaling || this.enableUserEditRotating) {
      return 'transform';
    }

    return 'move';
  }

  private enableInfoPopupWindow(enable: boolean): void {
    const enablePopup = enable && !this.enableUserEdit && !this.inDrawingMode;
    this.ancestorMap?.enableInfoWindow?.(enablePopup);
  }

  private async updateGeojsonInternal(newGeojson: string | FeatureCollectionLike): Promise<void> {
    if (!this.graphicsLayer) {
      await this.initializeLayers();
    }
    if (!this.graphicsLayer) return;

    const parsed = this.parseGeojson(newGeojson);
    if (!parsed) return;

    this.graphicsLayer.removeAll();
    this.labelLayer?.removeAll();

    for (let i = 0; i < parsed.features.length; i++) {
      const feature = parsed.features[i];
      if (!feature.geometry) continue;

      const geometry = this.geojsonGeometryToArcgisGeometry(feature.geometry);
      if (!geometry) continue;

      const attributes = {
        ...(feature.properties ?? {}),
      };

      if (attributes[this.uniqueIdPropertyName] === undefined || attributes[this.uniqueIdPropertyName] === null) {
        attributes[this.uniqueIdPropertyName] = feature.id ?? i;
      }

      const graphic = new Graphic({
        geometry,
        attributes,
      });

      this.decorateGraphic(graphic);
      this.graphicsLayer.add(graphic);
    }

    this.refreshLabels();
  }

  private parseGeojson(input: string | FeatureCollectionLike): FeatureCollectionLike | null {
    try {
      if (typeof input === 'string') {
        return JSON.parse(input) as FeatureCollectionLike;
      }
      return input;
    } catch (e) {
      console.error('Unable to parse geojson.', e);
      return null;
    }
  }

  private geojsonGeometryToArcgisGeometry(
    geometry: FeatureCollectionLike['features'][number]['geometry']
  ): Geometry | null {
    if (!geometry) return null;

    switch (geometry.type) {
      case 'Point':
        return new Point({
          x: geometry.coordinates[0],
          y: geometry.coordinates[1],
          spatialReference: { wkid: 4326 },
        });

      case 'LineString':
        return new Polyline({
          paths: [geometry.coordinates],
          spatialReference: { wkid: 4326 },
        });

      case 'Polygon':
        return new Polygon({
          rings: geometry.coordinates,
          spatialReference: { wkid: 4326 },
        });

      case 'MultiPoint':
        return new Multipoint({
          points: geometry.coordinates,
          spatialReference: { wkid: 4326 },
        });

      default:
        console.warn(`Unsupported GeoJSON geometry type: ${geometry.type}`);
        return null;
    }
  }

  private graphicToGeojsonFeature(graphic: Graphic): any {
    return {
      type: 'Feature',
      id: graphic.attributes?.[this.uniqueIdPropertyName],
      properties: { ...(graphic.attributes ?? {}) },
      geometry: this.arcgisGeometryToGeojson(graphic.geometry),
    };
  }

  private arcgisGeometryToGeojson(geometry: Geometry | null | undefined): any {
    if (!geometry) return null;

    switch (geometry.type) {
      case 'point': {
        const point = geometry as Point;
        return {
          type: 'Point',
          coordinates: [point.longitude ?? point.x, point.latitude ?? point.y],
        };
      }

      case 'polyline': {
        const polyline = geometry as Polyline;
        return {
          type: 'LineString',
          coordinates: polyline.paths[0],
        };
      }

      case 'polygon': {
        const polygon = geometry as Polygon;
        return {
          type: 'Polygon',
          coordinates: polygon.rings,
        };
      }

      case 'multipoint': {
        const multipoint = geometry as Multipoint;
        return {
          type: 'MultiPoint',
          coordinates: multipoint.points,
        };
      }

      default:
        return null;
    }
  }

  private syncGeojsonFromLayer(): void {
    if (!this.graphicsLayer) return;

    const features = this.graphicsLayer.graphics.toArray().map((graphic) => this.graphicToGeojsonFeature(graphic));

    this.blockGeoJsonUpdate = true;
    this.geojson = {
      type: 'FeatureCollection',
      features,
    };
    this.blockGeoJsonUpdate = false;
  }

  private removeGraphic(graphicToRemove: Graphic): void {
    if (!this.graphicsLayer) return;

    this.graphicsLayer.remove(graphicToRemove);
    this.syncGeojsonFromLayer();
    this.refreshLabels();

    this.dispatchEvent(
      new CustomEvent('userEditItemRemoved', {
        detail: this.graphicToGeojsonFeature(graphicToRemove),
        bubbles: true,
        composed: true,
      })
    );
  }

  private ensureGraphicIds(graphic: Graphic): void {
    if (!graphic.attributes) {
      graphic.attributes = {};
    }

    if (graphic.attributes[this.uniqueIdPropertyName] === undefined || graphic.attributes[this.uniqueIdPropertyName] === null) {
      graphic.attributes[this.uniqueIdPropertyName] = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    }
  }

  private decorateGraphic(graphic: Graphic): void {
    this.ensureGraphicIds(graphic);
    graphic.symbol = this.getSymbolForGraphic(graphic);
    graphic.popupTemplate = this.buildPopupTemplate();
  }

  private applyPopupTemplateToAllGraphics(): void {
    this.graphicsLayer?.graphics.forEach((graphic) => {
      graphic.popupTemplate = this.buildPopupTemplate();
    });
  }

  private buildPopupTemplate(): PopupTemplate {
    let title = '';
    let content = '';

    if (typeof this.infoTemplate === 'string') {
      try {
        const parsed = JSON.parse(this.infoTemplate);
        title = parsed?.title ?? '';
        content = parsed?.details ?? parsed?.content ?? '';
      } catch {
        content = this.infoTemplate;
      }
    } else if (this.infoTemplate) {
      title = this.infoTemplate.title ?? '';
      content = this.infoTemplate.details ?? '';
    }

    if (!title) {
      title = `{${this.uniqueIdPropertyName}}`;
    }

    return new PopupTemplate({
      title,
      content,
    });
  }

  private getSymbolForGraphic(graphic: Graphic): any {
    const rendererSymbol = this.tryResolveRendererSymbol(graphic);
    if (rendererSymbol) return rendererSymbol;

    switch (graphic.geometry?.type) {
      case 'point':
      case 'multipoint':
        return new SimpleMarkerSymbol({
          size: ArcGeojsonLayer.DEFAULT_SYMBOL_MARKER_SIZE,
          color: ArcGeojsonLayer.DEFAULT_SYMBOL_COLOR,
          outline: {
            color: [0, 0, 0, 255],
            width: 1,
          },
        });

      case 'polyline':
        return new SimpleLineSymbol({
          color: ArcGeojsonLayer.DEFAULT_SYMBOL_COLOR,
          width: ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH,
        });

      case 'polygon':
      default:
        return new SimpleFillSymbol({
          color: ArcGeojsonLayer.DEFAULT_SYMBOL_COLOR,
          outline: {
            color: [0, 0, 0, 255],
            width: ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH,
          },
        });
    }
  }

  private tryResolveRendererSymbol(graphic: Graphic): any | null {
    const rendererConfig = this.parseUnknownJson(this.renderer);
    const symbolJson = rendererConfig?.symbol;
    if (!symbolJson) return null;

    const geometryType = graphic.geometry?.type;

    try {
      if (geometryType === 'point' || geometryType === 'multipoint') {
        return SimpleMarkerSymbol.fromJSON(symbolJson);
      }

      if (geometryType === 'polyline') {
        return SimpleLineSymbol.fromJSON(symbolJson);
      }

      if (geometryType === 'polygon') {
        return SimpleFillSymbol.fromJSON(symbolJson);
      }
    } catch (e) {
      console.warn('Unable to apply renderer symbol.', e);
    }

    return null;
  }

  private applyRendererToAllGraphics(): void {
    this.graphicsLayer?.graphics.forEach((graphic) => {
      graphic.symbol = this.getSymbolForGraphic(graphic);
    });
  }

  private refreshLabels(): void {
    if (!this.graphicsLayer || !this.labelLayer) return;

    this.labelLayer.removeAll();

    const labelConfig = this.resolveLabelConfig();

    for (const graphic of this.graphicsLayer.graphics.toArray()) {
      const labelText = this.resolveLabelText(graphic, labelConfig.expression);
      if (!labelText) continue;

      const anchorPoint = this.getPopupPoint(graphic.geometry);
      if (!anchorPoint) continue;

      const labelGraphic = new Graphic({
        geometry: anchorPoint,
        symbol: new TextSymbol({
          text: labelText,
          color: labelConfig.color,
          haloColor: 'white',
          haloSize: 1,
          yoffset: 8,
          font: {
            size: labelConfig.size,
            family: 'sans-serif',
            weight: 'bold',
          },
        }),
        attributes: {
          __labelFor: graphic.attributes?.[this.uniqueIdPropertyName],
        },
      });

      this.labelLayer.add(labelGraphic);
    }
  }

  private resolveLabelConfig(): { expression: string; color: any; size: number } {
    const fallback = {
      expression: '$feature.LABEL',
      color: this.parseColor(this.labelColor) ?? ArcGeojsonLayer.DEFAULT_LABEL_COLOR,
      size: this.labelSize ?? ArcGeojsonLayer.DEFAULT_LABEL_SIZE,
    };

    const parsed = this.parseUnknownJson(this.labelJson);
    if (!parsed) return fallback;

    const first = Array.isArray(parsed) ? parsed[0] : parsed;
    if (!first) return fallback;

    return {
      expression: first.labelExpressionInfo?.expression ?? '$feature.LABEL',
      color: first.symbol?.color ?? fallback.color,
      size: first.symbol?.font?.size ?? fallback.size,
    };
  }

  private resolveLabelText(graphic: Graphic, expression: string): string {
    const attrs = graphic.attributes ?? {};
    const match = /\$feature\.([A-Za-z0-9_]+)/.exec(expression);
    if (match?.[1]) {
      return attrs[match[1]] != null ? String(attrs[match[1]]) : '';
    }
    return attrs.LABEL != null ? String(attrs.LABEL) : '';
  }

  private parseColor(value: unknown): number[] | null {
    if (Array.isArray(value)) return value as number[];
    if (typeof value === 'string') {
      try {
        const parsed = JSON.parse(value);
        return Array.isArray(parsed) ? parsed : null;
      } catch {
        return null;
      }
    }
    return null;
  }

  private parseUnknownJson(value: unknown): any {
    if (value == null) return null;
    if (typeof value === 'string') {
      try {
        return JSON.parse(value);
      } catch {
        return null;
      }
    }
    return value;
  }

  private getCurrentLayerGeometryType(): string | null {
    if (!this.graphicsLayer || this.graphicsLayer.graphics.length === 0) return null;
    return this.graphicsLayer.graphics.getItemAt(0)?.geometry?.type ?? null;
  }

  private getPopupPoint(geometry: Geometry | null | undefined): Point | null {
    if (!geometry) return null;

    if (geometry.type === 'point') {
      return geometry as Point;
    }

    if (geometry.type === 'polyline') {
      const polyline = geometry as Polyline;
      const path = polyline.paths?.[0];
      if (!path?.length) return null;
      const middleIndex = Math.floor(path.length / 2);
      return polyline.getPoint(0, middleIndex);
    }

    if (geometry.type === 'polygon') {
      const polygon = geometry as Polygon;
      return polygon.centroid;
    }

    if (geometry.type === 'multipoint') {
      const multipoint = geometry as Multipoint;
      const point = multipoint.points?.[0];
      return point
        ? new Point({
            x: point[0],
            y: point[1],
            spatialReference: multipoint.spatialReference,
          })
        : null;
    }

    return null;
  }

  disconnectedCallback(): void {
    super.disconnectedCallback();

    this.viewClickHandle?.remove();
    this.sketchCreateHandle?.remove();
    this.sketchUpdateHandle?.remove();

    if (this.view && this.graphicsLayer) {
      this.view.map.remove(this.graphicsLayer);
    }

    if (this.view && this.labelLayer) {
      this.view.map.remove(this.labelLayer);
    }

    this.graphicsLayer = null;
    this.labelLayer = null;
    this.sketchVM = null;
    this.view = null;
    this.ancestorMap = null;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'arc-geojson-layer': ArcGeojsonLayer;
  }
}
