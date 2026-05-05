private updateGeoJsonWithChanges(graphicToUpdate: Graphic): void {
  // Guard: geometry may be undefined mid-edit (AbortError recovery)
  if (!graphicToUpdate?.geometry) {
    console.warn('[arc-geojson-layer] updateGeoJsonWithChanges: geometry undefined, skipping');
    return;
  }
  this.blockGeoJsonUpdate = true;
  this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
  this.blockGeoJsonUpdate = false;
  this.refreshLabels();
  this.rebuildSourceCache();
  this.emitLayerEvent('userEditItemUpdated',
    graphicToGeoJsonFeature(graphicToUpdate, this.uniqueIdPropertyName));
}


private activateGraphicsEditor(graphic: Graphic): void {
  if (!this.graphicsEditor) {
    console.warn('[arc-geojson-layer] no graphicsEditor');
    return;
  }

  // If SketchViewModel is still in create/active state, cancel first
  if (this.graphicsEditor.state === 'active') {
    try { this.graphicsEditor.cancel(); } catch { }
  }

  console.log('[arc-geojson-layer] activateGraphicsEditor, state:',
    this.graphicsEditor.state, 'geomType:', graphic.geometry?.type);

  this.featureLayer.graphics.remove(graphic);
  if (!graphic.symbol) graphic.symbol = this.getSymbolForGraphic(graphic);
  this.sketchLayer.graphics.add(graphic);

  const tool = this.enableUserEditVertices ? 'reshape' : 'transform';

  try {
    this.graphicsEditor.update([graphic], {
      tool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: !this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
    } as any);
    console.log('[arc-geojson-layer] editor activated, new state:', this.graphicsEditor.state);
  } catch (e: any) {
    console.warn('[arc-geojson-layer] activateGraphicsEditor error:', e?.message);
    // Restore graphic on error
    this.sketchLayer.graphics.remove(graphic);
    this.featureLayer.graphics.add(graphic);
  }
}


private toFeatureCollectionFromLayer(): FeatureCollection {
  const features = (this.featureLayer?.graphics?.toArray() ?? [])
    .filter((g: Graphic) => g?.geometry != null)  // ← guard
    .map((g: Graphic) => graphicToGeoJsonFeature(g, this.uniqueIdPropertyName))
    .filter((f: any) => f.geometry != null);
  return { type: 'FeatureCollection', features } as FeatureCollection;
}
