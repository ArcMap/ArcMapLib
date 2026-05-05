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

import TextSymbol from '@arcgis/core/symbols/TextSymbol';

import type Geometry from '@arcgis/core/geometry/Geometry';

import type {

  FeatureCollection,

  Feature,

  Geometry as GeoJsonGeometry

} from 'geojson';

import JsonUtils from '../common/json-utils';

import { InfoTemplateDetails } from '../external-api';

type LayerMouseEvent = {

  coordinates: { latitude: number; longitude: number };

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

  private static layerSequence = 0;

  private readonly internalLayerUid =

    `arc-geojson-layer-${++ArcGeojsonLayer.layerSequence}`;

  private graphicsEditor!: SketchViewModel;

  private ancestorMap!: any;

  private featureLayer!: GraphicsLayer;

  private labelLayer!: GraphicsLayer;

  private sketchLayer!: GraphicsLayer;

  private view!: MapView;

  private inDrawingMode = false;

  private removingItem = false;

  private blockGeoJsonUpdate = false;

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

  geojson: string | FeatureCollection = {

    type: 'FeatureCollection',

    features: []

  };

  @property({ attribute: 'info-template' })

  infoTemplate!: string | InfoTemplateDetails;

  @property({ attribute: 'label-color' })

  labelColor: number[] | string = JsonUtils.DEFAULT_LABEL_COLOR;

  @property({ type: Number, attribute: 'label-size' })

  labelSize = JsonUtils.DEFAULT_LABEL_SIZE;

  @property({ type: String, attribute: 'label-json' })

  labelJson: string | object | object[] = '';

  @property({ attribute: 'layer-class' })

  layerClass = '';

  @property({ attribute: 'name' })

  name?: string = undefined;

  @property({ attribute: 'renderer' })

  renderer: any = undefined;

  @property({ attribute: 'unique-id-property-name' })

  uniqueIdPropertyName = 'id';

  protected createRenderRoot(): this {

    return this;

  }

  render() {

    return null;

  }

  private get layerBaseId(): string {

    return this.id || this.name || this.internalLayerUid;

  }

  async connectedCallback(): Promise<void> {

    super.connectedCallback();

    await this.waitForAncestorMap();

    if (!this.isConnected) return;

    try {

      await this.resolveAncestorMapAndView();

      await this.createLayer(this.geojson);

      this.bindViewEvents();

      this._initComplete = true;

      if (this._pendingGeojson !== undefined) {

        await this.updateGeojson(this._pendingGeojson);

        this._pendingGeojson = undefined;

      }

      if (this._pendingEnableUserEdit !== undefined) {

        await this.updateEditing(this._pendingEnableUserEdit);

        this._pendingEnableUserEdit = undefined;

      }

      console.log('[arc-geojson-layer] READY:', this.name, this.layerBaseId);

    } catch (error) {

      console.error('[arc-geojson-layer] connectedCallback error:', error);

    }

  }

  disconnectedCallback(): void {

    super.disconnectedCallback();

    this.cleanupEditor();

    this.cleanupViewEvents();

    if (this.view?.map) {

      [this.featureLayer, this.labelLayer, this.sketchLayer].forEach(layer => {

        if (!layer) return;

        try {

          layer.graphics?.removeAll();

          this.view.map.remove(layer);

        } catch {}

      });

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

    if (

      changedProps.has('enableUserEdit') ||

      changedProps.has('enableUserEditMove') ||

      changedProps.has('enableUserEditVertices') ||

      changedProps.has('enableUserEditScaling') ||

      changedProps.has('enableUserEditRotating') ||

      changedProps.has('enableUserEditUniformScaling') ||

      changedProps.has('enableUserEditAddVertices') ||

      changedProps.has('enableUserEditDeleteVertices')

    ) {

      this.updateEditing(this.enableUserEdit);

    }

  }

  private waitForAncestorMap(): Promise<void> {

    return new Promise<void>(resolve => {

      const found = this.closest('arc-map') ?? this.closest('up-map');

      if (found) {

        resolve();

        return;

      }

      const observer = new MutationObserver(() => {

        if (this.closest('arc-map') ?? this.closest('up-map')) {

          observer.disconnect();

          resolve();

        }

      });

      observer.observe(document.body, {

        childList: true,

        subtree: true

      });

    });

  }

  private async resolveAncestorMapAndView(): Promise<void> {

    this.ancestorMap = this.closest('arc-map') as any;

    if (!this.ancestorMap) {

      throw new Error('arc-geojson-layer must be inside <arc-map>');

    }

    if (typeof this.ancestorMap.componentOnReady === 'function') {

      await this.ancestorMap.componentOnReady();

    }

    if (typeof this.ancestorMap.getViewInstance !== 'function') {

      throw new Error('arc-map must expose getViewInstance()');

    }

    this.view = await this.ancestorMap.getViewInstance();

    if (!this.view) {

      throw new Error('getViewInstance() returned undefined');

    }

    await this.view.when();

    try {

      this.view.navigation.doubleClickZoomEnabled = false;

    } catch {}

  }

  private async createLayer(geojson: string | FeatureCollection): Promise<void> {

    const gId = `${this.layerBaseId}-graphics`;

    const lId = `${this.layerBaseId}-labels`;

    const sId = `${this.layerBaseId}-sketch`;

    if (this.view?.map) {

      [gId, lId, sId].forEach(id => {

        const oldLayer = this.view.map.findLayerById(id);

        if (oldLayer) {

          try {

            (oldLayer as GraphicsLayer).graphics?.removeAll();

            this.view.map.remove(oldLayer);

          } catch {}

        }

      });

    }

    this.featureLayer = new GraphicsLayer({

      id: gId,

      title: this.name || this.id || this.internalLayerUid

    });

    this.labelLayer = new GraphicsLayer({

      id: lId,

      title: `${this.name || this.internalLayerUid} Labels`,

      listMode: 'hide'

    });

    this.sketchLayer = new GraphicsLayer({

      id: sId,

      title: `${this.name || this.internalLayerUid} Sketch`,

      listMode: 'hide'

    });

    this.view.map.add(this.featureLayer);

    this.view.map.add(this.labelLayer);

    this.view.map.add(this.sketchLayer);

    const fsInfo = this.getUpGISJson(

      geojson ?? { type: 'FeatureCollection', features: [] }

    );

    fsInfo?.graphics?.forEach((g: Graphic) => {

      this.applyGraphicDefaults(g);

      this.featureLayer.add(g);

    });

    this.refreshLabels();

    this.updateLayerClass(this.layerClass);

    await this.createEditor();

    this.blockGeoJsonUpdate = true;

    this.geojson = this.toFeatureCollectionFromLayer();

    this.blockGeoJsonUpdate = false;

  }

  private async createEditor(): Promise<void> {

    this.cleanupEditor();

    this.graphicsEditor = new SketchViewModel({

      view: this.view,

      layer: this.sketchLayer,

      updateOnGraphicClick: false,

      defaultUpdateOptions: {

        enableRotation: this.enableUserEditRotating,

        enableScaling: this.enableUserEditScaling,

        preserveAspectRatio: this.enableUserEditUniformScaling,

        multipleSelectionEnabled: false,

        toggleToolOnClick: false

      }

    });

    const createHandle = this.graphicsEditor.on('create', (evt: any) => {

      if (evt.state !== 'complete' || !evt.graphic || this._isStartingDraw) {

        return;

      }

      const cloned = evt.graphic.clone();

      this.resetEditorStateOnly();

      this.inDrawingMode = false;

      this.addToGeojson(cloned);

      if (this.enableUserEdit) {

        cloned.popupTemplate = null as any;

        this.enableInfoPopupWindow(false);

      } else {

        this.enableInfoPopupWindow(true);

      }

    });

    const updateHandle = this.graphicsEditor.on('update', (evt: any) => {

      if (evt.state === 'complete' && evt.graphics?.length) {

        evt.graphics.forEach((g: Graphic) => {

          if (!g?.geometry) return;

          this.sketchLayer.remove(g);

          this.applyGraphicDefaults(g);

          if (!this.featureLayer.graphics.includes(g)) {

            this.featureLayer.add(g);

          }

          this.updateGeojsonWithChanges(g);

        });

        this.resetEditorStateOnly();

        this.enableInfoPopupWindow(!this.enableUserEdit);

      }

      if (evt.state === 'cancel') {

        this.sketchLayer.graphics.toArray().forEach((g: Graphic) => {

          this.sketchLayer.remove(g);

          this.applyGraphicDefaults(g);

          if (!this.featureLayer.graphics.includes(g)) {

            this.featureLayer.add(g);

          }

        });

        this.resetEditorStateOnly();

        this.enableInfoPopupWindow(!this.enableUserEdit);

      }

    });

    this.editorHandles.push(createHandle, updateHandle);

  }

  private bindViewEvents(): void {

    let clickTimer: any = null;

    try {

      this.view.navigation.doubleClickZoomEnabled = false;

    } catch {}

    const clickHandle = this.view.on('click', async (evt: any) => {

      const hit = await this.view.hitTest(evt, {

        include: [this.featureLayer, this.sketchLayer]

      });

      const graphic = this.getLayerGraphicFromHit(hit);

      if (!graphic) return;

      clickTimer = setTimeout(async () => {

        clickTimer = null;

        if (this.enableUserEdit) {

          if (

            (evt.native?.ctrlKey || evt.native?.metaKey) &&

            this.enableUserEditRemove

          ) {

            this.removingItem = true;

            this.removeFromGeojson(graphic);

            try {

              this.graphicsEditor?.cancel();

            } catch {}

            this.resetEditorStateOnly();

            this.removingItem = false;

            return;

          }

          await this.activateGraphicsEditor(graphic);

          return;

        }

        this.emitLayerEvent(

          'layerClick',

          this.buildMouseEvent(graphic, evt.mapPoint)

        );

        if (!this.inDrawingMode) {

          this.showGraphicPopup(graphic, evt.mapPoint);

        }

      }, 250);

    });

    const dblClickHandle = this.view.on('double-click', async (evt: any) => {

      evt.stopPropagation();

      if (clickTimer) {

        clearTimeout(clickTimer);

        clickTimer = null;

      }

      this.enableInfoPopupWindow(false);

      const hit = await this.view.hitTest(evt, {

        include: [this.featureLayer, this.sketchLayer]

      });

      const graphic = this.getLayerGraphicFromHit(hit);

      if (!graphic) return;

      this.emitLayerEvent(

        'doubleClick',

        this.buildMouseEvent(graphic, evt.mapPoint)

      );

      if (this.enableUserEdit) {

        await this.activateGraphicsEditor(graphic);

        return;

      }

      if (!this.inDrawingMode) {

        this.enableInfoPopupWindow(true);

        this.showGraphicPopup(graphic, evt.mapPoint);

      }

    });

    const pointerMoveHandle = this.view.on('pointer-move', async (evt: any) => {

      const hit = await this.view.hitTest(evt, {

        include: [this.featureLayer, this.sketchLayer]

      });

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

      const uid = this.getGraphicUniqueId(graphic);

      if (this.hoveredGraphicUid !== uid) {

        if (this.hoveredGraphicUid !== undefined) {

          this.emitLayerEvent(

            'layerMouseOut',

            this.buildMouseEvent(graphic, evt.mapPoint)

          );

        }

        this.hoveredGraphicUid = uid;

        this.emitLayerEvent(

          'layerMouseOver',

          this.buildMouseEvent(graphic, evt.mapPoint)

        );

      }

    });

    this.eventHandles.push(clickHandle, dblClickHandle, pointerMoveHandle);

  }

  async updateEditing(enableEdit: boolean): Promise<void> {

    if (!this.featureLayer) {

      this._pendingEnableUserEdit = enableEdit;

      return;

    }

    try {

      this.graphicsEditor?.cancel();

    } catch {}

    this.sketchLayer?.graphics.toArray().forEach((g: Graphic) => {

      this.sketchLayer.remove(g);

      this.applyGraphicDefaults(g);

      if (!this.featureLayer.graphics.includes(g)) {

        this.featureLayer.add(g);

      }

    });

    this.featureLayer.graphics.forEach((g: Graphic) => {

      g.popupTemplate = enableEdit

        ? null as any

        : this.buildPopupTemplateFromCurrent(g);

    });

    if (enableEdit) {

      this.enableInfoPopupWindow(false);

    }

  }

  async updateGeojson(newGeojson: string | FeatureCollection): Promise<void> {

    if (

      this.inDrawingMode ||

      this.removingItem ||

      this.blockGeoJsonUpdate ||

      this._isStartingDraw

    ) {

      return;

    }

    const parsed = ArcGeojsonLayer.parseJson<FeatureCollection>(newGeojson);

    if (!parsed.parsedJson || parsed.parsedJson.type !== 'FeatureCollection') {

      console.warn('[arc-geojson-layer] invalid GeoJSON:', parsed.error);

      return;

    }

    const incomingCount = parsed.parsedJson.features?.length ?? 0;

    if (!this.featureLayer) {

      await this.createLayer(parsed.parsedJson);

      return;

    }

    if (

      this.enableUserEdit &&

      this.graphicsEditor?.state === 'active' &&

      incomingCount > 0

    ) {

      return;

    }

    try {

      this.graphicsEditor?.cancel();

    } catch {}

    this.resetEditorStateOnly();

    this.featureLayer.graphics.removeAll();

    this.labelLayer?.graphics.removeAll();

    this.sketchLayer?.graphics.removeAll();

    const fsInfo = this.getUpGISJson(parsed.parsedJson);

    fsInfo?.graphics?.forEach((g: Graphic) => {

      this.applyGraphicDefaults(g);

      this.featureLayer.add(g);

    });

    this.refreshLabels();

  }

  updateInfoTemplate(newInfoTemplate: any): void {

    this.infoTemplate = newInfoTemplate;

    if (!this.featureLayer) return;

    this.featureLayer.graphics.forEach((g: Graphic) => {

      g.popupTemplate = this.enableUserEdit || this.inDrawingMode

        ? null as any

        : this.buildPopupTemplateFromCurrent(g);

    });

  }

  updateLabelJson(v: string | object | object[]): void {

    this.labelJson = v;

    this.refreshLabels();

  }

  updateLayerClass(cls: string): void {

    this.layerClass = cls;

    if (this.featureLayer) {

      (this.featureLayer as any).className = cls;

    }

    if (this.labelLayer) {

      (this.labelLayer as any).className = `${cls}-labels`;

    }

  }

  updateRenderer(newRenderer: any): void {

    this.renderer = newRenderer;

    if (!this.featureLayer) return;

    this.featureLayer.graphics.forEach((g: Graphic) => {

      g.symbol = this.getDefaultSymbolForGeometry(g.geometry);

    });

  }

  async startDrawing(drawGeometryType: string): Promise<void> {

    if (!this.featureLayer || !this.view) return;

    this._isStartingDraw = true;

    try {

      this.graphicsEditor?.cancel();

    } catch {}

    this.resetEditorStateOnly();

    this.featureLayer.graphics.removeAll();

    this.labelLayer?.graphics.removeAll();

    this.sketchLayer?.graphics.removeAll();

    this.inDrawingMode = true;

    this.enableInfoPopupWindow(false);

    this._isStartingDraw = false;

    await this.createEditor();

    await new Promise<void>(resolve => setTimeout(resolve, 50));

    const tool = this.toSketchCreateTool(drawGeometryType);

    try {

      this.graphicsEditor.create(tool);

    } catch (error) {

      console.error('[arc-geojson-layer] startDrawing error:', error);

      this.inDrawingMode = false;

      try {

        await this.createEditor();

        await new Promise<void>(resolve => setTimeout(resolve, 50));

        this.graphicsEditor.create(tool);

      } catch (secondError) {

        console.error('[arc-geojson-layer] second startDrawing failed:', secondError);

        this.resetEditorStateOnly();

      }

    }

  }

  async cancelDrawing(): Promise<void> {

    this.inDrawingMode = false;

    try {

      this.graphicsEditor?.cancel();

    } catch {}

    this.resetEditorStateOnly();

    this.enableInfoPopupWindow(!this.enableUserEdit);

  }

  async activateGraphicsEditor(graphic: Graphic): Promise<void> {

    if (!this.enableUserEdit) {

      return;

    }

    if (!graphic?.geometry) {

      return;

    }

    if (!this.graphicsEditor) {

      await this.createEditor();

    }

    this.enableInfoPopupWindow(false);

    try {

      this.graphicsEditor?.cancel();

    } catch {}

    this.resetEditorStateOnly();

    const editableGraphic = graphic.clone();

    editableGraphic.attributes = {

      ...(graphic.attributes ?? {})

    };

    editableGraphic.symbol =

      graphic.symbol ?? this.getDefaultSymbolForGeometry(graphic.geometry);

    editableGraphic.popupTemplate = null as any;

    this.featureLayer.remove(graphic);

    this.sketchLayer.graphics.removeAll();

    this.sketchLayer.add(editableGraphic);

    try {

      this.graphicsEditor.update([editableGraphic], {

        tool: this.resolveUpdateTool(),

        enableRotation: this.enableUserEditRotating,

        enableScaling: this.enableUserEditScaling,

        preserveAspectRatio: this.enableUserEditUniformScaling,

        multipleSelectionEnabled: false,

        toggleToolOnClick: false

      });

    } catch (error) {

      console.error('[arc-geojson-layer] editor activation failed:', error);

      this.sketchLayer.remove(editableGraphic);

      this.applyGraphicDefaults(graphic);

      if (!this.featureLayer.graphics.includes(graphic)) {

        this.featureLayer.add(graphic);

      }

      this.resetEditorStateOnly();

    }

  }

  async findFeatureByUniqueId(

    uniqueId: string | number

  ): Promise<Graphic | undefined> {

    return this.featureLayer?.graphics.find(

      (g: Graphic) =>

        g.attributes?.[this.uniqueIdPropertyName] === uniqueId

    );

  }

  async getLayerId(): Promise<string> {

    return this.featureLayer?.id ?? `${this.layerBaseId}-graphics`;

  }

  async openPopup(id: string | number): Promise<void> {

    if (this.enableUserEdit || this.inDrawingMode) return;

    const g = await this.findFeatureByUniqueId(id);

    if (!g?.geometry) return;

    this.showGraphicPopup(g, ArcGeojsonLayer.getPopupPoint(g.geometry));

  }

  async zoomTo(id: string | number, zoomLevel = 9): Promise<void> {

    const g = await this.findFeatureByUniqueId(id);

    if (!g?.geometry) return;

    if (ArcGeojsonLayer.isPoint(g.geometry)) {

      await this.view.goTo({

        center: g.geometry,

        zoom: zoomLevel

      });

      return;

    }

    const extent = g.geometry.extent;

    if (extent) {

      await this.view.goTo(extent.expand(1.5));

    }

  }

  enableInfoPopupWindow(enable: boolean): void {

    if (!enable && this.view?.popup?.visible) {

      this.view.popup.close();

    }

  }

  private applyGraphicDefaults(graphic: Graphic): void {

    if (!graphic) return;

    if (graphic.geometry) {

      graphic.symbol = this.getDefaultSymbolForGeometry(graphic.geometry);

    }

    graphic.popupTemplate = this.enableUserEdit || this.inDrawingMode

      ? null as any

      : this.buildPopupTemplateFromCurrent(graphic);

  }

  private getUpGISJson(

    geojson: string | object

  ): { graphics: Graphic[]; geometryType?: string } | null {

    const result = ArcGeojsonLayer.parseJson<FeatureCollection>(geojson);

    if (!result.parsedJson || result.parsedJson.type !== 'FeatureCollection') {

      return null;

    }

    const graphics: Graphic[] = [];

    let geometryType: string | undefined;

    result.parsedJson.features.forEach((f: Feature, i: number) => {

      const g = this.geojsonFeatureToGraphic(f, i);

      if (g?.geometry) {

        if (!geometryType) {

          geometryType = g.geometry.type;

        }

        graphics.push(g);

      }

    });

    return { graphics, geometryType };

  }

  private geojsonFeatureToGraphic(

    feature: Feature,

    index: number

  ): Graphic | null {

    const geometry = this.geojsonGeometryToArcGeometry(feature.geometry);

    if (!geometry) return null;

    const props = { ...(feature.properties ?? {}) } as any;

    if (props[this.uniqueIdPropertyName] === undefined) {

      props[this.uniqueIdPropertyName] = index;

    }

    if (props.OBJECTID === undefined) {

      props.OBJECTID = index;

    }

    const graphic = new Graphic({

      geometry,

      attributes: props

    });

    this.applyGraphicDefaults(graphic);

    return graphic;

  }

  private geojsonGeometryToArcGeometry(

    geometry: GeoJsonGeometry | null

  ): Geometry | null {

    if (!geometry) return null;

    const sr = { wkid: 4326 };

    switch (geometry.type) {

      case 'Point': {

        const [x, y] = geometry.coordinates as number[];

        return new Point({

          x,

          y,

          spatialReference: sr

        });

      }

      case 'MultiPoint': {

        const pts = geometry.coordinates as number[][];

        if (!pts.length) return null;

        return new Point({

          x: pts[0][0],

          y: pts[0][1],

          spatialReference: sr

        });

      }

      case 'LineString':

        return new Polyline({

          paths: [geometry.coordinates as number[][]],

          spatialReference: sr

        });

      case 'MultiLineString':

        return new Polyline({

          paths: geometry.coordinates as number[][][],

          spatialReference: sr

        });

      case 'Polygon':

        return new Polygon({

          rings: geometry.coordinates as number[][][],

          spatialReference: sr

        });

      case 'MultiPolygon': {

        const firstPolygon = (geometry.coordinates as number[][][][])[0];

        return firstPolygon

          ? new Polygon({

              rings: firstPolygon,

              spatialReference: sr

            })

          : null;

      }

      default:

        return null;

    }

  }

  private arcGeometryToGeoJsonGeometry(

    geometry: Geometry

  ): GeoJsonGeometry {

    if (ArcGeojsonLayer.isPoint(geometry)) {

      const pt = this.toGeographicPoint(geometry as Point);

      return {

        type: 'Point',

        coordinates: [pt.x, pt.y]

      };

    }

    if (ArcGeojsonLayer.isPolyline(geometry)) {

      const pl = this.toGeographicPolyline(geometry as Polyline);

      const paths = pl.paths ?? [];

      return paths.length <= 1

        ? {

            type: 'LineString',

            coordinates: paths[0] ?? []

          }

        : {

            type: 'MultiLineString',

            coordinates: paths

          };

    }

    const poly = this.toGeographicPolygon(geometry as Polygon);

    return {

      type: 'Polygon',

      coordinates: poly.rings as any

    };

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

    if (!newGraphic.attributes) {

      newGraphic.attributes = {};

    }

    const now = Date.now();

    if (newGraphic.attributes[this.uniqueIdPropertyName] === undefined) {

      newGraphic.attributes[this.uniqueIdPropertyName] = now;

    }

    if (newGraphic.attributes.OBJECTID === undefined) {

      newGraphic.attributes.OBJECTID = now;

    }

    this.applyGraphicDefaults(newGraphic);

    if (this.enableUserEdit) {

      newGraphic.popupTemplate = null as any;

    }

    if (!this.featureLayer.graphics.includes(newGraphic)) {

      this.featureLayer.add(newGraphic);

    }

    this.blockGeoJsonUpdate = true;

    this.geojson = this.toFeatureCollectionFromLayer();

    this.blockGeoJsonUpdate = false;

    this.refreshLabels();

    this.emitLayerEvent(

      'userDrawItemAdded',

      this.graphicToGeoJsonFeature(newGraphic)

    );

  }

  private removeFromGeojson(graphicToRemove: Graphic): void {

    const feature = this.graphicToGeoJsonFeature(graphicToRemove);

    this.featureLayer.remove(graphicToRemove);

    this.sketchLayer?.remove(graphicToRemove);

    this.blockGeoJsonUpdate = true;

    this.geojson = this.toFeatureCollectionFromLayer();

    this.blockGeoJsonUpdate = false;

    this.refreshLabels();

    this.emitLayerEvent('userEditItemRemoved', feature);

    this.resetEditorStateOnly();

  }

  private updateGeojsonWithChanges(graphicToUpdate: Graphic): void {

    if (!graphicToUpdate?.geometry) return;

    this.applyGraphicDefaults(graphicToUpdate);

    this.blockGeoJsonUpdate = true;

    this.geojson = this.toFeatureCollectionFromLayer();

    this.blockGeoJsonUpdate = false;

    this.refreshLabels();

    const feature = this.graphicToGeoJsonFeature(graphicToUpdate);

    if (!feature?.geometry) return;

    this.emitLayerEvent('userEditItemUpdated', feature);

  }

  private buildPopupTemplateFromCurrent(

    graphic: Graphic

  ): PopupTemplate | null {

    return JsonUtils.buildPopupTemplateFromCurrent({

      graphic,

      infoTemplate: this.infoTemplate,

      uniqueIdPropertyName: this.uniqueIdPropertyName,

      fallbackTitle: this.name || 'Details'

    });

  }

  private showGraphicPopup(graphic: Graphic, mapPoint?: Point): void {

    if (this.enableUserEdit || this.inDrawingMode) return;

    if (!graphic.geometry) return;

    const location =

      mapPoint ?? ArcGeojsonLayer.getPopupPoint(graphic.geometry);

    graphic.popupTemplate = this.buildPopupTemplateFromCurrent(graphic);

    if (!graphic.popupTemplate) return;

    this.view?.openPopup({

      location,

      features: [graphic]

    });

  }

  private refreshLabels(): void {

    if (!this.labelLayer || !this.featureLayer) return;

    this.labelLayer.graphics.removeAll();

    const labelColor = JsonUtils.resolveLabelColor(this.labelColor);

    const labelSize = JsonUtils.resolveLabelSize(this.labelSize);

    this.featureLayer.graphics.forEach((g: Graphic) => {

      const label = g.attributes?.LABEL;

      if (!label || !g.geometry) return;

      const pt = ArcGeojsonLayer.getPopupPoint(g.geometry);

      this.labelLayer.add(

        new Graphic({

          geometry: pt,

          attributes: {

            __labelFor: g.attributes?.[this.uniqueIdPropertyName]

          },

          symbol: new TextSymbol({

            text: String(label),

            color: labelColor as any,

            haloColor: 'black',

            haloSize: 1,

            xoffset: 3,

            yoffset: 3,

            font: {

              size: labelSize,

              family: 'sans-serif',

              weight: 'bold'

            }

          })

        })

      );

    });

  }

  private getDefaultSymbolForGeometry(

    geometry: Geometry | null | undefined

  ): any {

    if (!geometry) return null;

    const rendererConfig = this.renderer

      ? JsonUtils.getJsonFor(this.renderer)

      : null;

    const parsedRenderer = rendererConfig?.parsedJson;

    if (parsedRenderer?.symbol) {

      return JsonUtils.normalizePlainSymbol(parsedRenderer.symbol);

    }

    let size = JsonUtils.DEFAULT_SYMBOL_MARKER_SIZE;

    if (ArcGeojsonLayer.isPolyline(geometry)) {

      size = JsonUtils.DEFAULT_SYMBOL_LINE_WIDTH;

    }

    if (ArcGeojsonLayer.isPolygon(geometry)) {

      size = JsonUtils.DEFAULT_SYMBOL_POLYGON_WIDTH;

    }

    return JsonUtils.getJsonSymbolFor(

      geometry.type,

      JsonUtils.DEFAULT_SYMBOL_COLOR,

      size

    );

  }

  private toSketchCreateTool(

    t: string

  ): 'point' | 'polyline' | 'polygon' | 'rectangle' | 'circle' {

    switch ((t || '').toUpperCase()) {

      case DrawGeometryTypes.POINT:

        return 'point';

      case DrawGeometryTypes.LINE:

      case DrawGeometryTypes.POLYLINE:

      case DrawGeometryTypes.FREEHAND_POLYLINE:

        return 'polyline';

      case DrawGeometryTypes.RECTANGLE:

      case DrawGeometryTypes.EXTENT:

        return 'rectangle';

      case DrawGeometryTypes.CIRCLE:

      case DrawGeometryTypes.ELLIPSE:

        return 'circle';

      default:

        return 'polygon';

    }

  }

  private resolveUpdateTool(): 'move' | 'reshape' | 'transform' {

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

    return 'move';

  }

  private resetEditorStateOnly(): void {

    this.sketchLayer?.graphics.removeAll();

  }

  private cleanupEditor(): void {

    this.editorHandles.forEach(h => {

      try { h.remove(); } catch {}

    });

    this.editorHandles = [];

    try {

      this.graphicsEditor?.cancel();

      this.graphicsEditor?.destroy();

    } catch {}

  }

  private cleanupViewEvents(): void {

    this.eventHandles.forEach(h => {

      try { h.remove(); } catch {}

    });

    this.eventHandles = [];

  }

  private toGeographicPoint(p: Point): Point {

    return p.spatialReference?.isWGS84

      ? p

      : webMercatorUtils.webMercatorToGeographic(p) as Point;

  }

  private toGeographicPolyline(p: Polyline): Polyline {

    return p.spatialReference?.isWGS84

      ? p

      : webMercatorUtils.webMercatorToGeographic(p) as Polyline;

  }

  private toGeographicPolygon(p: Polygon): Polygon {

    return p.spatialReference?.isWGS84

      ? p

      : webMercatorUtils.webMercatorToGeographic(p) as Polygon;

  }

  private buildMouseEvent(

    graphic: Graphic,

    mapPoint: Point | null

  ): LayerMouseEvent {

    const gp = mapPoint

      ? webMercatorUtils.webMercatorToGeographic(mapPoint) as Point

      : null;

    return {

      coordinates: {

        latitude: gp?.y ?? 0,

        longitude: gp?.x ?? 0

      },

      attributes: graphic?.attributes ?? {}

    };

  }

  private emitLayerEvent(name: string, detail: any): void {

    this.dispatchEvent(

      new CustomEvent(name, {

        detail,

        bubbles: true,

        composed: true

      })

    );

  }

  private getLayerGraphicFromHit(hit: any): Graphic | undefined {

    const result = hit?.results?.find((r: any) => {

      const layer = r.graphic?.layer;

      return (

        layer?.id === this.featureLayer?.id ||

        layer?.id === this.sketchLayer?.id ||

        layer === this.featureLayer ||

        layer === this.sketchLayer

      );

    });

    return result?.graphic;

  }

  private getGraphicUniqueId(

    g: Graphic

  ): string | number | undefined {

    return g.attributes?.[this.uniqueIdPropertyName] ??

      g.attributes?.OBJECTID;

  }

  static parseJson<T = any>(value: any): JsonParseResult<T> {

    if (value === null || value === undefined) {

      return { error: new Error('null/undefined') };

    }

    if (typeof value === 'string') {

      try {

        return { parsedJson: JSON.parse(value) as T };

      } catch (e: any) {

        return {

          error: e instanceof Error ? e : new Error(String(e))

        };

      }

    }

    return { parsedJson: value as T };

  }

  private static getPopupPoint(geometry: Geometry): Point {

    if (!geometry) {

      return new Point({ x: 0, y: 0 });

    }

    if (ArcGeojsonLayer.isPoint(geometry)) {

      return geometry as Point;

    }

    if (ArcGeojsonLayer.isPolyline(geometry)) {

      const pl = geometry as Polyline;

      const path = pl.paths?.[0] ?? [];

      const mid = Math.floor(path.length / 2);

      return new Point({

        x: path[mid]?.[0] ?? 0,

        y: path[mid]?.[1] ?? 0,

        spatialReference: pl.spatialReference

      });

    }

    if (ArcGeojsonLayer.isPolygon(geometry)) {

      return (geometry as Polygon).centroid ??

        new Point({ x: 0, y: 0 });

    }

    return new Point({ x: 0, y: 0 });

  }

  static isPoint(g: Geometry): g is Point {

    return g?.type === 'point';

  }

  static isPolyline(g: Geometry): g is Polyline {

    return g?.type === 'polyline';

  }

  static isPolygon(g: Geometry): g is Polygon {

    return g?.type === 'polygon';

  }

}

declare global {

  interface HTMLElementTagNameMap {

    'arc-geojson-layer': ArcGeojsonLayer;

  }

}