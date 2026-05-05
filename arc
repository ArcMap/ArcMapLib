private bindViewEvents(): void {
  if (this._wireEventsRegistered) return;
  this._wireEventsRegistered = true;

  this.eventHandles.forEach(h => h.remove());
  this.eventHandles = [];

  let clickTimer: any = null;

  const clickHandle = (this.view as any).on('click', (evt: any) => {
    if (!this.enableUserEdit || this.inDrawingMode) return;
    evt.stopPropagation?.();
    const nearest = this.findNearest(evt.mapPoint);
    if (!nearest) return;
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
    if (clickTimer) { clearTimeout(clickTimer); clickTimer = null; }
    if ((this.view as any).popup?.visible) (this.view as any).popup.close();

    // Only activate editor if edit mode is already on
    if (!this.enableUserEdit) return;

    const nearest = this.findNearest(evt.mapPoint);
    if (!nearest) return;

    console.log('[arc-geojson-layer] double-click activating editor:', nearest.geometry?.type);
    this.enableInfoPopupWindow(false);
    this.activateGraphicsEditor(nearest);
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


private activateGraphicsEditor(graphic: Graphic): void {
  if (!this.graphicsEditor || !this.enableUserEdit) return;

  if (!this.enableUserEditMove && !this.enableUserEditVertices &&
      !this.enableUserEditScaling && !this.enableUserEditRotating) {
    console.error('[arc-geojson-layer] all editing features disabled');
    return;
  }

  // Cancel any active state first
  if (this.graphicsEditor.state === 'active') {
    try { this.graphicsEditor.cancel(); } catch { }
  }

  this.featureLayer.graphics.remove(graphic);
  if (!graphic.symbol) graphic.symbol = this.getSymbolForGraphic(graphic);
  this.sketchLayer.graphics.add(graphic);

  const tool = this.enableUserEditVertices ? 'reshape' : 'transform';
  try {
    this.graphicsEditor.update([graphic], {
      tool,
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      preserveAspectRatio: !this.enableUserEditUniformScaling,
      toggleToolOnClick: false,
    } as any);
    console.log('[arc-geojson-layer] editor activated, state:', this.graphicsEditor.state);
  } catch (e: any) {
    console.warn('[arc-geojson-layer] activateGraphicsEditor error:', e?.message);
    this.sketchLayer.graphics.remove(graphic);
    this.featureLayer.graphics.add(graphic);
  }
}


private findNearest(mapPoint: any): Graphic | null {
  if (!mapPoint || !this._sourceCache.length) return null;

  // Check if point is inside polygon first
  for (const g of this._sourceCache) {
    if (g.geometry?.type === 'polygon') {
      try {
        if ((g.geometry as any).contains?.(mapPoint)) return g;
      } catch { }
    }
  }

  // Distance-based for points and polylines
  const THRESHOLD_PX = 20;
  let nearest: Graphic | null = null;
  let minDist = Infinity;
  for (const g of this._sourceCache) {
    if (!g.geometry) continue;
    const labelPoint = this.getPopupPoint(g.geometry);
    if (!labelPoint) continue;
    const screenPt = this.view.toScreen(labelPoint as any);
    const clickPt = this.view.toScreen(mapPoint);
    if (!screenPt || !clickPt) continue;
    const dist = Math.hypot(screenPt.x - clickPt.x, screenPt.y - clickPt.y);
    if (dist < minDist && dist < THRESHOLD_PX) { minDist = dist; nearest = g; }
  }
  return nearest;
}
