const pointerMoveHandle = this.view.on('pointer-move', async (evt: any) => {
  const hit = await this.view.hitTest(evt, {
    include: [this.featureLayer, this.sketchLayer]
  });

  const graphic = this.getLayerGraphicFromHit(hit);

  if (!graphic) {
    this.view.container.style.cursor = '';

    if (this.hoveredGraphicUid !== undefined) {
      this.hoveredGraphicUid = undefined;

      this.emitLayerEvent('layerMouseOut', {
        coordinates: { latitude: 0, longitude: 0 },
        attributes: {}
      });
    }

    return;
  }

  this.view.container.style.cursor = 'pointer';

  const uid = this.getGraphicUniqueId(graphic);

  if (this.hoveredGraphicUid !== uid) {
    if (this.hoveredGraphicUid !== undefined) {
      this.emitLayerEvent(
        'layerMouseOut',
        this.buildMouseEvent(graphic, evt.mapPoint)
      );
    }

    this.hoveredGraphicUid = uid;

    this.emitLayerEvent(
      'layerMouseOver',
      this.buildMouseEvent(graphic, evt.mapPoint)
    );
  }
});




try {
  if (this.view?.container) {
    this.view.container.style.cursor = '';
  }
} catch {}