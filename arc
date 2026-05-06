private setMapCursor(cursor: 'default' | 'pointer', evt?: any): void {
  const value = cursor === 'pointer' ? 'pointer' : '';

  try {
    (this.view as any).cursor = cursor;
  } catch {}

  try {
    const container = this.view?.container as HTMLElement;
    container?.style.setProperty('cursor', value, 'important');

    const surface = container?.querySelector('.esri-view-surface') as HTMLElement;
    surface?.style.setProperty('cursor', value, 'important');

    const canvas = container?.querySelector('canvas') as HTMLElement;
    canvas?.style.setProperty('cursor', value, 'important');

    if (evt?.x !== undefined && evt?.y !== undefined) {
      const el = document.elementFromPoint(evt.x, evt.y) as HTMLElement;
      el?.style.setProperty('cursor', value, 'important');
    }
  } catch {}
}

const pointerMoveHandle = this.view.on('pointer-move', async (evt: any) => {
  const hit = await this.view.hitTest(evt, {
    include: [this.featureLayer, this.sketchLayer]
  });

  const graphic = this.getLayerGraphicFromHit(hit);

  if (!graphic) {
    this.setMapCursor('default', evt);
    return;
  }

  this.setMapCursor('pointer', evt);

  const uid = this.getGraphicUniqueId(graphic);

  if (this.hoveredGraphicUid !== uid) {
    this.hoveredGraphicUid = uid;

    this.emitLayerEvent(
      'layerMouseOver',
      this.buildMouseEvent(graphic, evt.mapPoint)
    );
  }
});