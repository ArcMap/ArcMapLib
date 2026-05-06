private resolveUpdateTool(graphic?: Graphic): 'move' | 'reshape' | 'transform' {
  const drawGeometryType =
    graphic?.attributes?.drawGeometryType ??
    graphic?.attributes?.shapeType ??
    graphic?.attributes?.geometryType;

  const isCircle =
    String(drawGeometryType).toUpperCase() === DrawGeometryTypes.CIRCLE;

  // Circle must use transform, not reshape.
  // Circle is stored as polygon, but reshape will distort it.
  if (isCircle) {
    return 'transform';
  }

  // Normal polygon should allow vertex editing.
  if (
    graphic?.geometry?.type === 'polygon' &&
    (
      this.enableUserEditVertices ||
      this.enableUserEditAddVertices ||
      this.enableUserEditDeleteVertices
    )
  ) {
    return 'reshape';
  }

  if (this.enableUserEditScaling || this.enableUserEditRotating) {
    return 'transform';
  }

  return 'move';
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
  this._currentDrawGeometryType = drawGeometryType;

  this._isStartingDraw = false;

  await this.createEditor();
  await new Promise<void>(resolve => setTimeout(resolve, 50));

  const tool = this.toSketchCreateTool(drawGeometryType);

  try {
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


const createHandle = this.graphicsEditor.on('create', (evt: any) => {
  if (evt.state !== 'complete' || !evt.graphic || this._isStartingDraw) {
    return;
  }

  const cloned = evt.graphic.clone();

  cloned.attributes = {
    ...(cloned.attributes ?? {}),
    drawGeometryType: this._currentDrawGeometryType
  };

  this.resetEditorStateOnly();

  this.inDrawingMode = false;

  this.addToGeojson(cloned);

  this._currentDrawGeometryType = undefined;

  if (this.enableUserEdit) {
    cloned.popupTemplate = null as any;
    this.enableInfoPopupWindow(false);
  } else {
    this.enableInfoPopupWindow(true);
  }
});