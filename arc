async activateGraphicsEditor(graphic: Graphic): Promise<void> {
  if (!this.enableUserEdit || !graphic?.geometry) return;

  this.enableInfoPopupWindow(false);

  try {
    this.graphicsEditor?.cancel();
  } catch {}

  if (!this.graphicsEditor) {
    await this.createEditor();
  }

  const editableGraphic = graphic.clone();

  editableGraphic.attributes = {
    ...(graphic.attributes ?? {})
  };

  editableGraphic.symbol =
    graphic.symbol ?? this.getDefaultSymbolForGeometry(graphic.geometry);

  editableGraphic.popupTemplate = null as any;

  const uid = this.getGraphicUniqueId(graphic);

  this.featureLayer.graphics.toArray().forEach((g: Graphic) => {
    if (this.getGraphicUniqueId(g) === uid) {
      this.featureLayer.remove(g);
    }
  });

  this.sketchLayer.graphics.removeAll();
  this.sketchLayer.add(editableGraphic);

  await this.view.whenLayerView(this.sketchLayer);
  await new Promise(resolve => setTimeout(resolve, 50));

  const tool = this.resolveUpdateTool(editableGraphic);

  console.log('[up-geojson-layer] opening editor with', {
    tool,
    geometry: editableGraphic.geometry?.type,
    sketchCount: this.sketchLayer.graphics.length
  });

  try {
    this.graphicsEditor.update([editableGraphic], {
      tool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      multipleSelectionEnabled: false,
      toggleToolOnClick: false
    });

    console.log('[up-geojson-layer] editor update called');
  } catch (error) {
    console.error('[up-geojson-layer] editor activation failed:', error);

    this.sketchLayer.remove(editableGraphic);
    this.replaceGraphicInFeatureLayer(graphic);
  }
}