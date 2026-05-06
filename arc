async activateGraphicsEditor(graphic: Graphic): Promise<void> {
  if (!this.enableUserEdit || !graphic?.geometry) return;

  if (!this.graphicsEditor) {
    await this.createEditor();
  }

  this.enableInfoPopupWindow(false);

  try {
    this.graphicsEditor.cancel();
  } catch {}

  // Important: edit existing graphic directly from featureLayer
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

  this.graphicsEditor.update([graphic], {
    tool,
    enableRotation: this.enableUserEditRotating,
    enableScaling: this.enableUserEditScaling,
    preserveAspectRatio: this.enableUserEditUniformScaling,
    multipleSelectionEnabled: false,
    toggleToolOnClick: false
  });

  console.log('[up-geojson-layer] editor opened');
}

