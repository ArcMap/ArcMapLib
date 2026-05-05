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
  
  // Clone the graphic before clearing sketch layer
  // SketchViewModel owns the graphic on sketchLayer —
  // we must clone it before removing from sketchLayer
  const clonedGraphic = graphic.clone();
  
  // Clear sketch layer so next draw starts clean
  this.sketchLayer.graphics.removeAll();
  
  this.addToGeoJson(clonedGraphic);
}


async startDrawing(drawGeometryType: string): Promise<void> {
  console.log('[arc-geojson-layer] startDrawing called with:', drawGeometryType);

  // Always cancel and recreate fresh — guarantees clean state
  // regardless of what previous draw left behind
  try { this.graphicsEditor?.cancel(); } catch { }
  this.sketchLayer?.graphics?.removeAll();
  
  await this.createEditor();

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
