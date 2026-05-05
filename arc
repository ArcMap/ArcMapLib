private updateGeojson(value: string | FeatureCollection): void {
  if (this.isInternalGeojson(value)) {
    console.log('[arc-geojson-layer] updateGeojson SKIPPED: internal tag');
    return;
  }

  const parsed = this.parseGeojson(value);
  const incomingCount = parsed?.features?.length ?? 0;

  console.log('[arc-geojson-layer] updateGeojson called:', {
    isInternal: false,
    inDrawingMode: this.inDrawingMode,
    removingItem: this.removingItem,
    enableUserEdit: this.enableUserEdit,
    incomingCount,
  });

  if (this.inDrawingMode || this.removingItem || this.blockGeoJsonUpdate) return;

  // Allow clear (incomingCount=0) even in edit mode
  // Block only when incoming has data AND edit mode is on
  if (this.enableUserEdit && incomingCount > 0) return;

  if (!parsed) return;

  this.loadFeaturesFromGeojson(parsed);
  this.updateRenderer(this.renderer);
  this.refreshLabels();
}
