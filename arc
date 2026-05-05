disconnectedCallback(): void {
  super.disconnectedCallback();
  console.log('[arc-geojson-layer] disconnectedCallback — removing layers from map');
  
  // CRITICAL: remove layers from map immediately on disconnect
  // Angular @if destroys this component but the layers stay on the map
  // unless explicitly removed here
  if (this.view?.map) {
    if (this.featureLayer) {
      this.featureLayer.graphics.removeAll();
      this.view.map.remove(this.featureLayer);
    }
    if (this.labelLayer) {
      this.labelLayer.graphics.removeAll();
      this.view.map.remove(this.labelLayer);
    }
    if (this.sketchLayer) {
      this.sketchLayer.graphics.removeAll();
      this.view.map.remove(this.sketchLayer);
    }
  }

  // Reset ready promise for next connectedCallback cycle
  this._ready = new Promise(resolve => { this._readyResolve = resolve; });
  this._initComplete = false;
  this._wireEventsRegistered = false;
  
  this.cleanup();
}
