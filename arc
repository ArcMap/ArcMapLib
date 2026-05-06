private finishActiveEditor(): void {
  const editedGraphics = this.sketchLayer?.graphics?.toArray() ?? [];

  editedGraphics.forEach((g: Graphic) => {
    this.replaceGraphicInFeatureLayer(g);
    this.updateGeojsonWithChanges(g);
  });

  try {
    this.graphicsEditor?.cancel();
  } catch {}

  this.sketchLayer?.graphics?.removeAll();
  this.enableInfoPopupWindow(!this.enableUserEdit);
}




if (this.enableUserEdit && this.graphicsEditor?.state === 'active') {
  this.finishActiveEditor();
  return;
}




if (this.enableUserEdit) {
  if (this.graphicsEditor?.state === 'active') {
    this.finishActiveEditor();
    return;
  }

  await this.activateGraphicsEditor(graphic);
  return;
}




this.sketchLayer?.graphics?.removeAll();

try {
  this.graphicsEditor?.cancel();
} catch {}