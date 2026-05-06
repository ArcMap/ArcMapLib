private setMapCursor(cursor: 'default' | 'pointer', evt?: any): void {
  const container = this.view?.container as HTMLElement;
  if (!container) return;

  const value = cursor === 'pointer' ? 'pointer' : '';

  try {
    (this.view as any).cursor = cursor;
  } catch {}

  container.style.setProperty('cursor', value, 'important');

  const surface = container.querySelector('.esri-view-surface') as HTMLElement;
  surface?.style.setProperty('cursor', value, 'important');

  const canvas = container.querySelector('canvas') as HTMLElement;
  canvas?.style.setProperty('cursor', value, 'important');

  if (this._lastCursorElement) {
    this._lastCursorElement.style.removeProperty('cursor');
    this._lastCursorElement = undefined;
  }

  if (cursor === 'pointer' && evt?.x !== undefined && evt?.y !== undefined) {
    const rect = container.getBoundingClientRect();

    const clientX = rect.left + evt.x;
    const clientY = rect.top + evt.y;

    const el = document.elementFromPoint(clientX, clientY) as HTMLElement;

    if (el) {
      el.style.setProperty('cursor', 'pointer', 'important');
      this._lastCursorElement = el;
    }
  }
}



const pointerMoveHandle = this.view.on('pointer-move', async (evt: any) => {
  const hit = await this.view.hitTest(evt, {
    include: [this.featureLayer, this.sketchLayer]
  });

  const graphic = this.getLayerGraphicFromHit(hit);

  if (!graphic) {
    this.setMapCursor('default', evt);

    if (this.hoveredGraphicUid !== undefined) {
      this.hoveredGraphicUid = undefined;

      this.emitLayerEvent('layerMouseOut', {
        coordinates: { latitude: 0, longitude: 0 },
        attributes: {}
      });
    }

    return;
  }

  this.setMapCursor('pointer', evt);

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


