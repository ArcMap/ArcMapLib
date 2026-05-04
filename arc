private addToGeojson(newGraphic: Graphic): void {
  if (!newGraphic.attributes) newGraphic.attributes = {};

  if (newGraphic.attributes[this.uniqueIdPropertyName] === undefined) {
    newGraphic.attributes[this.uniqueIdPropertyName] = Date.now();
  }
  if (newGraphic.attributes.OBJECTID === undefined) {
    newGraphic.attributes.OBJECTID = Date.now();
  }

  // Force symbol based on geometry type directly
  // Do NOT use getSymbolForGraphic here — use getDefaultSymbolForGeometry
  // to guarantee a valid symbol regardless of renderer state
  if (newGraphic.geometry) {
    const forcedSymbol = this.getDefaultSymbolForGeometry(
      newGraphic.geometry
    );
    console.log('forced symbol:', forcedSymbol);
    newGraphic.symbol = forcedSymbol;
  }

  // THEN try to apply renderer symbol on top if available
  const rendererSymbol = this.getSymbolForGraphic(newGraphic);
  console.log('renderer symbol:', rendererSymbol);
  if (rendererSymbol) {
    newGraphic.symbol = rendererSymbol;
  }
  // If renderer symbol is null/undefined — keep the forced default symbol

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

  this.blockGeoJsonUpdate = true;
  this.geojson = this.toFeatureCollectionFromLayer();

  setTimeout(() => {
    if (this._internalUpdateId === currentId) {
      this.blockGeoJsonUpdate = false;
    }
  }, 2000);

  this.refreshLabels();
  this.emitLayerEvent(
    'userDrawItemAdded',
    this.graphicToGeoJsonFeature(newGraphic)
  );
}
