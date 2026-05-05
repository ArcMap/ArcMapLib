async startDrawing(drawGeometryType: string): Promise<void> {
  console.log('[arc-geojson-layer] startDrawing called with:', drawGeometryType);

  this._isStartingDraw = true; // block events during clear

  try { this.graphicsEditor?.cancel(); } catch { }

  this.featureLayer?.graphics?.removeAll();
  this.labelLayer?.graphics?.removeAll();
  this.sketchLayer?.graphics?.removeAll();
  this._sourceCache = [];

  this.geojson = this.tagAsInternal(
    { type: 'FeatureCollection', features: [] } as FeatureCollection
  );
  this.enableUserEdit = false;
  this.inDrawingMode = false;

  this._isStartingDraw = false; // unblock events

  this.inDrawingMode = true;
  this.enableInfoPopupWindow(false);
  await this.ancestorMap?.hideZoomSlider?.();
  await this.ancestorMap?.hideScaleBar?.();

  const tool = toSketchTool(drawGeometryType);
  console.log('[arc-geojson-layer] creating sketch tool:', tool);

  try {
    this.graphicsEditor.create(tool as any);
    if (this.graphicsEditor.state !== 'active') {
      await this.createEditor();
      await new Promise<void>(r => setTimeout(r, 50));
      this.graphicsEditor.create(tool as any);
    }
  } catch (e) {
    console.error('[arc-geojson-layer] startDrawing error:', e);
    await this.createEditor();
    await new Promise<void>(r => setTimeout(r, 50));
    try { this.graphicsEditor.create(tool as any); } catch { }
    this.inDrawingMode = false;
  }
}


