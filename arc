async updateGeojson(
  newGeojson: string | FeatureCollection
): Promise<void> {
  console.log('updateGeojson called, blockGeoJsonUpdate:', this.blockGeoJsonUpdate);
  console.log('inDrawingMode:', this.inDrawingMode);
  console.log('enableUserEdit:', this.enableUserEdit);
  console.log('removingItem:', this.removingItem);
  
  if (this.blockGeoJsonUpdate) {
    console.log('BLOCKED by blockGeoJsonUpdate');
    return;
  }
  if (this.enableUserEdit || this.inDrawingMode || this.removingItem) {
    console.log('BLOCKED by edit/draw/remove flag');
    return;
  }
  
  console.log('PROCEEDING with updateGeojson - this will clear layer!');
  // ... rest
}


private addToGeojson(newGraphic: Graphic): void {
  console.log('addToGeojson called');
  console.log('graphic geometry type:', newGraphic.geometry?.type);
  // ... rest
  
  this._internalUpdateId++;
  const currentId = this._internalUpdateId;
  console.log('setting blockGeoJsonUpdate = true, id:', currentId);
  
  this.blockGeoJsonUpdate = true;
  this.geojson = this.toFeatureCollectionFromLayer();

  setTimeout(() => {
    console.log('setTimeout fired, currentId:', currentId, 'internalUpdateId:', this._internalUpdateId);
    if (this._internalUpdateId === currentId) {
      console.log('unblocking geojson update');
      this.blockGeoJsonUpdate = false;
    }
  }, 500);
