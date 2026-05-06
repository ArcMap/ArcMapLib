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
  this._currentDrawGeometryType = drawGeometryType;

  this._isStartingDraw = false;

  await this.createEditor();
  await new Promise<void>(resolve => setTimeout(resolve, 50));

  const tool = this.toSketchCreateTool(drawGeometryType);

  try {
    // Drawing should use sketchLayer
    this.graphicsEditor.layer = this.sketchLayer;

    this.graphicsEditor.create(tool);
  } catch (error) {
    console.error('[up-geojson-layer] startDrawing error:', error);

    this.inDrawingMode = false;
    this._currentDrawGeometryType = undefined;

    try {
      await this.createEditor();
      await new Promise<void>(resolve => setTimeout(resolve, 50));

      this.graphicsEditor.layer = this.sketchLayer;
      this.graphicsEditor.create(tool);
    } catch (secondError) {
      console.error('[up-geojson-layer] second startDrawing failed:', secondError);
      this.resetEditorStateOnly();
    }
  }
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

  // Editing should use the original featureLayer graphic directly.
  // Do not move graphic into sketchLayer.
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

    console.log('[up-geojson-layer] editor opened');
  } catch (error) {
    console.error('[up-geojson-layer] editor activation failed:', error);
  }
}

