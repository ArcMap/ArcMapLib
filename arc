private onDrawComplete(graphic: Graphic): void {
  if (!graphic?.geometry) {
    console.warn('[arc-geojson-layer] onDrawComplete: no geometry');
    this.inDrawingMode = false;
    return;
  }
  console.log('[arc-geojson-layer] DRAWING COMPLETE - graphics before add:', 
    this.featureLayer.graphics.length);
  this.ancestorMap?.showZoomSlider?.();
  this.ancestorMap?.showScaleBar?.();
  this.inDrawingMode = false;
  this.addToGeoJson(graphic);
  
  // Reset SketchViewModel to ready state after draw completes
  // so subsequent draws start clean
  try { this.graphicsEditor.cancel(); } catch { }
}


async startDrawing(drawGeometryType: string): Promise<void> {
  console.log('[arc-geojson-layer] startDrawing called with:', drawGeometryType);
  if (!this.graphicsEditor) {
    console.warn('[arc-geojson-layer] startDrawing: graphicsEditor not ready');
    return;
  }

  // FIX: Cancel any active state and recreate editor before each draw.
  // SketchViewModel can get stuck after completing a previous draw.
  // Recreating it fresh ensures clean state every time.
  try { this.graphicsEditor.cancel(); } catch { }
  
  // Only recreate if previous draw completed (state is 'ready' or stuck)
  if (this.graphicsEditor.state !== 'active') {
    await this.createEditor();
  }

  this.inDrawingMode = true;
  this.enableInfoPopupWindow(false);
  await this.ancestorMap?.hideZoomSlider?.();
  await this.ancestorMap?.hideScaleBar?.();

  const toolType = drawGeometryType.toLowerCase() as any;
  console.log('[arc-geojson-layer] creating sketch tool:', toolType);
  try {
    this.graphicsEditor.create(toolType);
    console.log('[arc-geojson-layer] graphicsEditor state after create:', 
      this.graphicsEditor.state);
  } catch (e) {
    console.error('[arc-geojson-layer] startDrawing error:', e);
    this.inDrawingMode = false;
  }
}
