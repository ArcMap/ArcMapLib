if (this.graphicsEditor?.state === 'active' || this.sketchLayer?.graphics?.length > 0) {
  this.finishActiveEditor();
  return;
}


private _finishingEditor = false;

private finishActiveEditor(): void {
  if (this._finishingEditor) return;

  this._finishingEditor = true;

  const editedGraphics = this.sketchLayer?.graphics?.toArray() ?? [];

  editedGraphics.forEach((g: Graphic) => {
    if (!g?.geometry) return;

    this.replaceGraphicInFeatureLayer(g);
    this.updateGeojsonWithChanges(g);
  });

  try {
    this.graphicsEditor?.cancel();
  } catch {}

  this.sketchLayer?.graphics?.removeAll();

  this.enableInfoPopupWindow(!this.enableUserEdit);

  setTimeout(() => {
    this._finishingEditor = false;
  }, 0);
}





const dblClickHandle = this.view.on('double-click', async (evt: any) => {
  evt.stopPropagation();

  if (clickTimer) {
    clearTimeout(clickTimer);
    clickTimer = null;
  }

  // IMPORTANT: turn editor off before hitTest
  if (this.graphicsEditor?.state === 'active' || this.sketchLayer?.graphics?.length > 0) {
    this.finishActiveEditor();
    return;
  }

  this.enableInfoPopupWindow(false);

  const hit = await this.view.hitTest(evt, {
    include: [this.featureLayer, this.sketchLayer]
  });

  let graphic = this.getLayerGraphicFromHit(hit);

  if (!graphic) {
    graphic = this.findNearestGraphic(evt.mapPoint);
  }

  if (!graphic) return;

  if (this.enableUserEdit) {
    await this.activateGraphicsEditor(graphic);
    return;
  }

  if (!this.inDrawingMode) {
    this.enableInfoPopupWindow(true);
    this.showGraphicPopup(graphic, evt.mapPoint);
  }
});



if (this.graphicsEditor?.state === 'active' || this.sketchLayer?.graphics?.length > 0) {
  this.finishActiveEditor();
  return;
}