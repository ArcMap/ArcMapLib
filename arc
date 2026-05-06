private bindViewEvents(): void {
  let clickTimer: any = null;

  const clickHandle = this.view.on('click', async (evt: any) => {
    if (clickTimer) {
      clearTimeout(clickTimer);
      clickTimer = null;
    }

    clickTimer = setTimeout(async () => {
      clickTimer = null;

      const hit = await this.view.hitTest(evt, {
        include: [this.featureLayer, this.sketchLayer]
      });

      const graphic = this.getLayerGraphicFromHit(hit);

      if (this.enableUserEdit) {
        // Single click should never open/close editor.
        // Editor open/close is controlled only by double-click.
        return;
      }

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

    if (!this.enableUserEdit) return;

    // If editor is already open, double-click should close it.
    if (this.isEditorActive()) {
      this.finishActiveEditor();
      return;
    }

    this.enableInfoPopupWindow(false);

    const hit = await this.view.hitTest(evt, {
      include: [this.featureLayer]
    });

    let graphic = this.getLayerGraphicFromHit(hit);

    if (!graphic || graphic.geometry?.type === 'point') {
      graphic = this.findNearestEditableGraphic(evt.mapPoint);
    }

    console.log('[up-geojson-layer] double click edit:', {
      enableUserEdit: this.enableUserEdit,
      found: !!graphic,
      geometry: graphic?.geometry?.type,
      featureCount: this.featureLayer?.graphics?.length
    });

    if (!graphic) return;

    await this.activateGraphicsEditor(graphic);
  });

  const nativeDblClick = async (event: MouseEvent) => {
    event.preventDefault();
    event.stopPropagation();

    if (clickTimer) {
      clearTimeout(clickTimer);
      clickTimer = null;
    }

    if (!this.enableUserEdit) return;

    // Same rule for native fallback.
    if (this.isEditorActive()) {
      this.finishActiveEditor();
      return;
    }

    const rect = this.view.container.getBoundingClientRect();

    const screenPoint = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top
    };

    const hit = await this.view.hitTest(screenPoint, {
      include: [this.featureLayer]
    });

    let graphic = this.getLayerGraphicFromHit(hit);

    if (!graphic || graphic.geometry?.type === 'point') {
      graphic = this.findNearestEditableGraphic(
        this.view.toMap(screenPoint) as Point
      );
    }

    console.log('[up-geojson-layer] native dblclick edit:', {
      enableUserEdit: this.enableUserEdit,
      found: !!graphic,
      geometry: graphic?.geometry?.type
    });

    if (!graphic) return;

    await this.activateGraphicsEditor(graphic);
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