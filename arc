async connectedCallback(): Promise<void> {
  super.connectedCallback();
  await this.waitForAncestorMap();
  if (!this.isConnected) return;
  try {
    await this.resolveAncestorMapAndView();
    await this.createLayer(this.geojson);
    this.bindViewEvents();
    this._initComplete = true;
    console.log('[arc-geojson-layer] READY, name:', this.name);

    // Always sync current geojson after init — Angular may have
    // pushed real data before connectedCallback finished
    const currentParsed = ArcGeojsonLayer.parseJson<FeatureCollection>(this.geojson);
    const currentCount = currentParsed.parsedJson?.features?.length ?? 0;
    const layerCount = this.featureLayer.graphics.length;

    if (currentCount > 0 && currentCount !== layerCount) {
      console.log('[arc-geojson-layer] syncing geojson after init, name:', this.name,
        'count:', currentCount);
      await this.updateGeojson(this.geojson);
    }

    if (this._pendingEnableUserEdit !== undefined) {
      await this.updateEditing(this._pendingEnableUserEdit);
      this._pendingEnableUserEdit = undefined;
    }
  } catch (e) {
    console.error('[arc-geojson-layer] connectedCallback error:', e);
  }
}
