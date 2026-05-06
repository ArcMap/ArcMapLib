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


const graphic = this.getLayerGraphicFromHit(hit);

if (!graphic && this.isEditorActive()) {
  this.finishActiveEditor();
  return;
}