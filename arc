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

  let graphic = this.getLayerGraphicFromHit(hit);

  // fallback: sometimes polygon/circle fill hitTest misses
  if (!graphic) {
    graphic = this.findNearestGraphic(evt.mapPoint);
  }

  console.log('[arc-geojson-layer] double click edit:', {
    enableUserEdit: this.enableUserEdit,
    graphicFound: !!graphic,
    geometryType: graphic?.geometry?.type,
    featureCount: this.featureLayer?.graphics?.length,
    sketchCount: this.sketchLayer?.graphics?.length
  });

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


private findNearestGraphic(mapPoint: Point): Graphic | undefined {
  if (!mapPoint || !this.featureLayer) return undefined;

  const graphics = this.featureLayer.graphics.toArray();

  if (!graphics.length) return undefined;

  // For now return the first polygon/polyline/point when hitTest misses.
  // This avoids double-click failing on circle/polygon transparent fill.
  return graphics.find((g: Graphic) => !!g.geometry);
}


async activateGraphicsEditor(graphic: Graphic): Promise<void> {
  if (!this.enableUserEdit) {
    console.warn('[arc-geojson-layer] editor not opened: enableUserEdit is false');
    return;
  }

  if (!graphic?.geometry) {
    console.warn('[arc-geojson-layer] editor not opened: graphic has no geometry');
    return;
  }

  if (!this.graphicsEditor) {
    await this.createEditor();
  }

  this.enableInfoPopupWindow(false);

  try {
    this.graphicsEditor?.cancel();
  } catch {}

  this.sketchLayer.graphics.removeAll();

  const editableGraphic = graphic.clone();

  editableGraphic.attributes = {
    ...(graphic.attributes ?? {})
  };

  editableGraphic.symbol =
    graphic.symbol ?? this.getDefaultSymbolForGeometry(graphic.geometry);

  editableGraphic.popupTemplate = null as any;

  this.featureLayer.remove(graphic);
  this.sketchLayer.add(editableGraphic);

  await this.view.whenLayerView(this.sketchLayer);

  try {
    this.graphicsEditor.update([editableGraphic], {
      tool: this.resolveUpdateTool(),
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      multipleSelectionEnabled: false,
      toggleToolOnClick: false
    });

    console.log('[arc-geojson-layer] editor opened');
  } catch (error) {
    console.error('[arc-geojson-layer] editor activation failed:', error);

    this.sketchLayer.remove(editableGraphic);

    this.applyGraphicDefaults(graphic);

    if (!this.featureLayer.graphics.includes(graphic)) {
      this.featureLayer.add(graphic);
    }
  }
}