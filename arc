const clickHandle = this.view.on('click', async (evt: any) => {
  const hit = await this.view.hitTest(evt, {
    include: [this.featureLayer, this.sketchLayer]
  });

  const graphic = this.getLayerGraphicFromHit(hit);

  // Click outside while editor is open -> close editor
  if (!graphic) {
    if (this.isEditorActive()) {
      this.finishActiveEditor();
    }
    return;
  }

  clickTimer = setTimeout(async () => {
    clickTimer = null;

    if (this.enableUserEdit) {
      // Single click should not open editor.
      // Editor opens only on double-click.
      return;
    }

    this.emitLayerEvent(
      'layerClick',
      this.buildMouseEvent(graphic, evt.mapPoint)
    );

    if (!this.inDrawingMode) {
      this.showGraphicPopup(graphic, evt.mapPoint);
    }
  }, 250);
});