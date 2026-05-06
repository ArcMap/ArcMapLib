private showGraphicPopup(graphic: Graphic, mapPoint?: Point): void {
  if (this.enableUserEdit || this.inDrawingMode || this.shouldSuppressPopup()) {
    return;
  }

  if (!graphic?.geometry) return;

  const location = mapPoint ?? ArcGeojsonLayer.getPopupPoint(graphic.geometry);

  graphic.popupTemplate =
    graphic.popupTemplate ?? this.buildPopupTemplateFromCurrent(graphic);

  if (!graphic.popupTemplate) return;

  try {
    this.view.popupEnabled = true;
  } catch {}

  this.view.openPopup({
    location,
    features: [graphic]
  });
}



const clickHandle = this.view.on('click', async (evt: any) => {
  if (this.enableUserEdit) {
    return;
  }

  const hit = await this.view.hitTest(evt, {
    include: [this.featureLayer]
  });

  const graphic = this.getLayerGraphicFromHit(hit);

  if (!graphic) return;

  // Open popup immediately first
  if (!this.inDrawingMode) {
    this.showGraphicPopup(graphic, evt.mapPoint);
  }

  // Emit Angular event after popup opens
  setTimeout(() => {
    this.emitLayerEvent(
      'layerClick',
      this.buildMouseEvent(graphic, evt.mapPoint)
    );
  }, 0);
});