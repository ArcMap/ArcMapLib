async startDrawing(drawGeometryType: string): Promise<void> {
  console.log('[arc-geojson-layer] startDrawing called with:', drawGeometryType);

  // Clear any existing drawn graphic — user is starting a new draw
  this.featureLayer.graphics.removeAll();
  this.labelLayer.graphics.removeAll();
  this._sourceCache = [];
  this.sketchLayer?.graphics?.removeAll();

  // Notify Angular that draw layer was cleared
  // so it can reset drawGeojson and any saved fence state
  this.emitLayerEvent('drawLayerCleared', null);

  // Update internal geojson to empty
  this.geojson = this.tagAsInternal(
    { type: 'FeatureCollection', features: [] } as FeatureCollection
  );

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
    console.log('[arc-geojson-layer] graphicsEditor state:', this.graphicsEditor.state);
  } catch (e) {
    console.error('[arc-geojson-layer] startDrawing error:', e);
    this.inDrawingMode = false;
  }
}
