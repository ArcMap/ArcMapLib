const dblClickHandle = (this.view as any).on('double-click', (evt: any) => {
  evt.stopPropagation?.();

  // Cancel pending single-click
  if (clickTimer) {
    clearTimeout(clickTimer);
    clickTimer = null;
  }

  // Close popup immediately
  if ((this.view as any).popup?.visible) {
    (this.view as any).popup.close();
  }

  const nearest = this.findNearest(evt.mapPoint);
  if (!nearest) {
    console.log('[arc-geojson-layer] double-click: no graphic found');
    return;
  }

  console.log('[arc-geojson-layer] double-click - activating editor:',
    nearest.geometry?.type);

  this.enableInfoPopupWindow(false);
  this.enableUserEdit = true;

  // Do NOT recreate editor — use existing one
  // Only startDrawing recreates the editor
  this.activateGraphicsEditor(nearest);

  this.emitLayerEvent('userEditEnabled',
    graphicToGeoJsonFeature(nearest, this.uniqueIdPropertyName));
});


private activateGraphicsEditor(graphic: Graphic): void {
  if (!this.graphicsEditor) {
    console.warn('[arc-geojson-layer] no graphicsEditor');
    return;
  }

  console.log('[arc-geojson-layer] activateGraphicsEditor, geomType:',
    graphic.geometry?.type);

  // Move graphic to sketch layer synchronously
  this.featureLayer.graphics.remove(graphic);
  
  // Ensure graphic has symbol before adding to sketch layer
  if (!graphic.symbol) {
    graphic.symbol = this.getSymbolForGraphic(graphic);
  }
  
  this.sketchLayer.graphics.add(graphic);

  const tool = this.enableUserEditVertices ? 'reshape' : 'transform';
  
  // Call update immediately — no setTimeout needed
  try {
    this.graphicsEditor.update([graphic], {
      tool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: !this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
    } as any);
    console.log('[arc-geojson-layer] graphicsEditor.update called, state:',
      this.graphicsEditor.state);
  } catch (e) {
    console.error('[arc-geojson-layer] activateGraphicsEditor error:', e);
    // Restore graphic to featureLayer on error
    this.sketchLayer.graphics.remove(graphic);
    this.featureLayer.graphics.add(graphic);
  }
}
