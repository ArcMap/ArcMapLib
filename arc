async startDrawing(drawGeometryType: string): Promise<void> {
  console.log('[arc-geojson-layer] startDrawing called with:', drawGeometryType);

  // Clear any previously drawn graphic from this layer
  // User switching from circle to polygon should remove the circle
  this.featureLayer.graphics.removeAll();
  this.labelLayer.graphics.removeAll();
  this._sourceCache = [];
  
  // Update internal geojson to reflect cleared state
  this.geojson = this.tagAsInternal(
    { type: 'FeatureCollection', features: [] } as FeatureCollection
  );

  // Recreate SketchViewModel fresh — prevents stuck state
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
    console.log('[arc-geojson-layer] graphicsEditor state after create:', 
      this.graphicsEditor.state);
  } catch (e) {
    console.error('[arc-geojson-layer] startDrawing error:', e);
    this.inDrawingMode = false;
  }
}
