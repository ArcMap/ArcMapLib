async startDrawing(drawGeometryType: string): Promise<void> {
  console.log('[arc-geojson-layer] startDrawing called with:', drawGeometryType);

  // Cancel any active edit/draw first
  try { this.graphicsEditor?.cancel(); } catch { }

  // Clear ALL layers — graphic may be on featureLayer OR sketchLayer
  // depending on whether edit mode was active
  this.featureLayer?.graphics?.removeAll();
  this.labelLayer?.graphics?.removeAll();
  this.sketchLayer?.graphics?.removeAll();
  this._sourceCache = [];

  // Notify Angular draw layer is cleared
  this.emitLayerEvent('drawLayerCleared', null);

  // Reset geojson to empty
  this.geojson = this.tagAsInternal(
    { type: 'FeatureCollection', features: [] } as FeatureCollection
  );

  // Reset edit state
  this.enableUserEdit = false;
  this.inDrawingMode = false;

  // Recreate SketchViewModel fresh
  await this.createEditor();

  this.inDrawingMode = true;
  this.enableInfoPopupWindow(false);
  await this.ancestorMap?.hideZoomSlider?.();
  await this.ancestorMap?.hideScaleBar?.();

  const tool = toSketchTool(drawGeometryType);
  console.log('[arc-geojson-layer] creating sketch tool:', tool);

  await new Promise<void>(resolve => setTimeout(resolve, 50));

  try {
    this.graphicsEditor.create(tool as any);
    console.log('[arc-geojson-layer] state after create:', this.graphicsEditor.state);
  } catch (e) {
    console.error('[arc-geojson-layer] startDrawing error:', e);
    this.inDrawingMode = false;
  }
}
