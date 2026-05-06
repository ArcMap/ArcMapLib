const clickHandle = this.view.on('click', async (evt: any) => {
  if (this.enableUserEdit) return;

  const hit = await this.view.hitTest(evt, {
    include: [this.featureLayer]
  });

  const graphic = this.getLayerGraphicFromHit(hit);

  if (!graphic) return;

  this.emitLayerEvent(
    'layerClick',
    this.buildMouseEvent(graphic, evt.mapPoint)
  );

  if (!this.inDrawingMode) {
    this.showGraphicPopup(graphic, evt.mapPoint);
  }
});