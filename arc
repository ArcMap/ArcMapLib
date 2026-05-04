async updateGeojson(
  newGeojson: string | FeatureCollection
): Promise<void> {
  if (this.blockGeoJsonUpdate) return;
  if (this.enableUserEdit || this.inDrawingMode || this.removingItem) return;

  if (!this.featureLayer) {
    await this.createLayer(newGeojson);
    return;
  }

  // Parse incoming geojson
  const parsed = ArcGeojsonLayer.parseJson<FeatureCollection>(newGeojson);
  if (!parsed.parsedJson) return;

  const incomingCount = parsed.parsedJson.features?.length ?? 0;
  const currentCount = this.featureLayer.graphics.length;

  // If incoming is LESS than what we have — Angular is echoing
  // a stale/cleared state. Skip it to preserve drawn graphics.
  if (incomingCount < currentCount) {
    console.log(
      'updateGeojson: skipping — incoming',
      incomingCount,
      'less than current',
      currentCount
    );
    return;
  }

  this.featureLayer.removeAll();
  this.labelLayer?.removeAll();

  const fsInfo = this.getUpGISJson(newGeojson);
  if (!fsInfo) return;

  for (const graphic of fsInfo.graphics) {
    this.featureLayer.add(graphic);
  }

  this.updateRenderer(this.renderer);
  this.refreshLabels();
  this.updateInfoTemplate(this.infoTemplate);
}
