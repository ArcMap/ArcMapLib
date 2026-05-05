private loadFeaturesFromGeojson(fc: FeatureCollection): void {
  // Clear ALL layers including sketchLayer
  // Graphics may be on sketchLayer if edit mode was active
  this.featureLayer.graphics.removeAll();
  this.sketchLayer?.graphics?.removeAll();
  
  console.log('[arc-geojson-layer] loadFeaturesFromGeojson - loading features:',
    fc.features.length,
    'featureLayer on map:', this.view?.map?.layers?.includes(this.featureLayer));

  for (const feature of fc.features) {
    const geom = geojsonToArcGISGeometry(feature.geometry as any);
    if (!geom) continue;
    const attrs = {
      ...(feature.properties ?? {}),
      [this.uniqueIdPropertyName]: (feature as any).id ??
        feature.properties?.[this.uniqueIdPropertyName] ?? Date.now(),
      OBJECTID: Date.now() + Math.random(),
    };
    const g = new Graphic({
      geometry: geom, attributes: attrs,
      symbol: this.getSymbolForGeometry(geom),
    });
    g.popupTemplate = this.buildPopupTemplateFromCurrent() ?? undefined;
    this.featureLayer.graphics.add(g);
  }
  this.rebuildSourceCache();
  
  console.log('[arc-geojson-layer] loadFeaturesFromGeojson DONE - graphics on featureLayer:',
    this.featureLayer.graphics.length,
    'graphics on sketchLayer:', this.sketchLayer?.graphics?.length ?? 0);
}


private updateGeojson(value: string | FeatureCollection): void {
  if (this.isInternalGeojson(value)) {
    console.log('[arc-geojson-layer] updateGeojson SKIPPED: internal tag');
    return;
  }
  const parsed = this.parseGeojson(value);
  const incomingCount = parsed?.features?.length ?? 0;

  console.log('[arc-geojson-layer] updateGeojson called:', {
    inDrawingMode: this.inDrawingMode, removingItem: this.removingItem,
    enableUserEdit: this.enableUserEdit, incomingCount,
  });

  if (this.inDrawingMode || this.removingItem || this.blockGeoJsonUpdate) return;
  if (this.enableUserEdit && incomingCount > 0) return;
  if (!parsed) return;

  // Cancel active editor before clearing
  if (incomingCount === 0) {
    try { this.graphicsEditor?.cancel(); } catch { }
    this.sketchLayer?.graphics?.removeAll();
  }

  console.log('[arc-geojson-layer] updateGeojson PROCEEDING - will clear and redraw');
  this.loadFeaturesFromGeojson(parsed);
  this.updateRenderer(this.renderer);
  this.refreshLabels();
}
