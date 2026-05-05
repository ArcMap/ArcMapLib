private bindViewEvents(): void {
  if (this._wireEventsRegistered) return;
  this._wireEventsRegistered = true;

  this.eventHandles.forEach(h => h.remove());
  this.eventHandles = [];

  // Track click timer to cancel single-click when double-click fires
  let clickTimer: any = null;

  const clickHandle = (this.view as any).on('click', (evt: any) => {
    if (!this.enableUserEdit || this.inDrawingMode) return;
    evt.stopPropagation?.();

    const nearest = this.findNearest(evt.mapPoint);
    if (!nearest) return;

    // Delay single-click action so double-click can cancel it
    clickTimer = setTimeout(() => {
      clickTimer = null;
      if (evt.native?.ctrlKey && !evt.native?.shiftKey) {
        this.removingItem = true;
        this.removeFromGeoJson(nearest);
        this.graphicsEditor?.cancel();
        this.removingItem = false;
        return;
      }
      this.activateGraphicsEditor(nearest);
    }, 250);
  });
  this.eventHandles.push(clickHandle);

  const dblClickHandle = (this.view as any).on('double-click', (evt: any) => {
    evt.stopPropagation?.();

    // Cancel pending single-click — prevents popup from opening
    if (clickTimer) {
      clearTimeout(clickTimer);
      clickTimer = null;
    }

    // Close any open popup immediately
    if ((this.view as any).popup?.visible) {
      (this.view as any).popup.close();
    }

    const nearest = this.findNearest(evt.mapPoint);
    if (!nearest) {
      console.log('[arc-geojson-layer] double-click: no graphic found');
      return;
    }

    console.log('[arc-geojson-layer] double-click - activating editor:',
      nearest.geometry?.type);

    // Disable popup before activating editor
    this.enableInfoPopupWindow(false);

    // Set edit mode and activate editor immediately — no setTimeout
    this.enableUserEdit = true;
    this.activateGraphicsEditor(nearest);

    // Notify Angular to sync isEnableUserEdit=true
    this.emitLayerEvent('userEditEnabled',
      graphicToGeoJsonFeature(nearest, this.uniqueIdPropertyName));
  });
  this.eventHandles.push(dblClickHandle);

  const pointerMoveHandle = (this.view as any).on('pointer-move', (evt: any) => {
    if (this.inDrawingMode) return;
    const mp = this.view.toMap({ x: evt.x, y: evt.y });
    if (!mp) return;
    const nearest = this.findNearest(mp);
    if (nearest) {
      (this.view.container as HTMLElement).style.cursor = 'pointer';
      const geo = webMercatorUtils.webMercatorToGeographic(mp) as Point;
      this.emitLayerEvent('layerMouseOver', this.buildMouseEvent(nearest, geo as Point));
    } else {
      (this.view.container as HTMLElement).style.cursor = '';
      this.emitLayerEvent('layerMouseOut', null);
    }
  });
  this.eventHandles.push(pointerMoveHandle);
}
