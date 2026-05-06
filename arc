private finishActiveEditor(): void {
  if (!this._editorOpen) return;

  const graphics = this.featureLayer?.graphics?.toArray() ?? [];

  graphics.forEach((g: Graphic) => {
    if (!g?.geometry) return;
    this.updateGeojsonWithChanges(g);
  });

  try {
    this.graphicsEditor?.cancel();
  } catch {}

  this._editorOpen = false;
  this.enableInfoPopupWindow(!this.enableUserEdit);

  console.log('[up-geojson-layer] editor closed');
}



private async handleEditorDoubleClick(mapPoint: Point, source: string): Promise<void> {
  if (!this.enableUserEdit) return;

  const now = Date.now();

  // Prevent ArcGIS double-click and native dblclick from both running.
  if (now - this._lastDoubleClickHandledAt < 350) {
    console.log('[up-geojson-layer] duplicate dblclick ignored from', source);
    return;
  }

  this._lastDoubleClickHandledAt = now;

  if (this.isEditorActive()) {
    this.finishActiveEditor();
    return;
  }

  const graphic = this.findNearestEditableGraphic(mapPoint);

  console.log('[up-geojson-layer] handleEditorDoubleClick:', {
    source,
    found: !!graphic,
    geometry: graphic?.geometry?.type,
    featureCount: this.featureLayer?.graphics?.length
  });

  if (!graphic) return;

  await this.activateGraphicsEditor(graphic);
}


async activateGraphicsEditor(graphic: Graphic): Promise<void> {
  if (!this.enableUserEdit || !graphic?.geometry) return;

  if (!this.graphicsEditor) {
    await this.createEditor();
  }

  this.enableInfoPopupWindow(false);

  try {
    this.graphicsEditor.cancel();
  } catch {}

  this.graphicsEditor.layer = this.featureLayer;

  graphic.popupTemplate = null as any;

  if (!graphic.symbol) {
    graphic.symbol = this.getDefaultSymbolForGeometry(graphic.geometry);
  }

  const tool = this.resolveUpdateTool(graphic);

  console.log('[up-geojson-layer] opening editor with', {
    tool,
    geometry: graphic.geometry.type,
    featureCount: this.featureLayer.graphics.length
  });

  try {
    this.graphicsEditor.update([graphic], {
      tool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      multipleSelectionEnabled: false,
      toggleToolOnClick: false
    });

    this._editorOpen = true;

    console.log('[up-geojson-layer] editor opened');
  } catch (error) {
    this._editorOpen = false;
    console.error('[up-geojson-layer] editor activation failed:', error);
  }
}



private bindViewEvents(): void {
  let clickTimer: any = null;

  const clickHandle = this.view.on('click', async (evt: any) => {
    if (clickTimer) {
      clearTimeout(clickTimer);
      clickTimer = null;
    }

    clickTimer = setTimeout(async () => {
      clickTimer = null;

      if (this.enableUserEdit) {
        return;
      }

      const hit = await this.view.hitTest(evt, {
        include: [this.featureLayer, this.sketchLayer]
      });

      const graphic = this.getLayerGraphicFromHit(hit);

      if (!graphic) return;

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

    await this.handleEditorDoubleClick(evt.mapPoint, 'arcgis-double-click');
  });

  const nativeDblClick = async (event: MouseEvent) => {
    event.preventDefault();
    event.stopPropagation();

    if (clickTimer) {
      clearTimeout(clickTimer);
      clickTimer = null;
    }

    const rect = this.view.container.getBoundingClientRect();

    const screenPoint = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top
    };

    const mapPoint = this.view.toMap(screenPoint) as Point;

    await this.handleEditorDoubleClick(mapPoint, 'native-dblclick');
  };

  this.view.container.addEventListener('dblclick', nativeDblClick, true);

  const pointerMoveHandle = this.view.on('pointer-move', async (evt: any) => {
    const hit = await this.view.hitTest(evt, {
      include: [this.featureLayer, this.sketchLayer]
    });

    const graphic = this.getLayerGraphicFromHit(hit);

    if (!graphic) {
      this.setMapCursor('default', evt);
      return;
    }

    this.setMapCursor('pointer', evt);

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

  this.eventHandles.push(
    clickHandle,
    dblClickHandle,
    pointerMoveHandle,
    {
      remove: () => {
        this.view.container.removeEventListener('dblclick', nativeDblClick, true);
      }
    }
  );
}