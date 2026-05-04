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
    console​​​​​​​​​​​​​​​​
