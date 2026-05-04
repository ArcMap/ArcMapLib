private addToGeojson(newGraphic: Graphic): void {
  if (!newGraphic.attributes) newGraphic.attributes = {};

  if (newGraphic.attributes[this.uniqueIdPropertyName] === undefined) {
    newGraphic.attributes[this.uniqueIdPropertyName] = Date.now();
  }
  if (newGraphic.attributes.OBJECTID === undefined) {
    newGraphic.attributes.OBJECTID = Date.now();
  }

  newGraphic.symbol = this.getSymbolForGraphic(newGraphic);

  newGraphic.popupTemplate = JsonUtils.buildPopupTemplateFromCurrent({
    graphic: newGraphic,
    infoTemplate: this.infoTemplate,
    uniqueIdPropertyName: this.uniqueIdPropertyName,
    fallbackTitle: this.name || 'Details'
  });

  if (!this.featureLayer.graphics.includes(newGraphic)) {
    this.featureLayer.add(newGraphic);
  }

  this._internalUpdateId++;
  const currentId = this._internalUpdateId;

  // Store the drawn graphic reference so we can restore it
  const drawnGraphic = newGraphic;

  this.blockGeoJsonUpdate = true;
  this.geojson = this.toFeatureCollectionFromLayer();

  // Emit event so Angular/NgRx can process
  this.emitLayerEvent(
    'userDrawItemAdded',
    this.graphicToGeoJsonFeature(newGraphic)
  );

  this.refreshLabels();

  // Wait longer for NgRx to finish its full cycle
  // NgRx can take multiple render cycles to settle
  setTimeout(() => {
    if (this._internalUpdateId === currentId) {
      // Before unblocking, make sure our graphic is still on the layer
      // If Angular cleared it, restore it
      if (!this.featureLayer.graphics.includes(drawnGraphic)) {
        console.log('restoring cleared graphic after NgRx cycle');
        this.featureLayer.add(drawnGraphic);
      }
      this.blockGeoJsonUpdate = false;
    }
  }, 2000); // increased from 500ms to 2000ms
}


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

  // If incoming is empty but we have graphics — Angular is echoing
  // our drawn state back as empty. Skip it.
  const incomingCount = parsed.parsedJson.features?.length ?? 0;
  const currentCount = this.featureLayer.graphics.length;

  if (incomingCount === 0 && currentCount > 0) {
    console.log('updateGeojson: skipping empty echo, we have', currentCount, 'graphics');
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
