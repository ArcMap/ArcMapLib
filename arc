private bindViewEvents(): void {

  let clickTimer: any = null;
  let doubleClickInProgress = false;

  const clickHandle = this.view.on("click", async (evt: any) => {

    clickTimer = setTimeout(async () => {

      // Ignore delayed click after double-click
      if (doubleClickInProgress) {
        return;
      }

      const hit = await this.view.hitTest(evt, {
        include: [this.featureLayer, this.sketchLayer]
      });

      let graphic = this.getLayerGraphicFromHit(hit);

      if (!graphic) {
        graphic = this.findNearestEditableGraphic(evt.mapPoint);
      }

      // =========================
      // EDIT MODE
      // =========================

      if (this.enableUserEdit) {

        // Click INSIDE edited polygon → keep editor open
        if (graphic && this.isEditorActive()) {
          return;
        }

        // Click OUTSIDE polygon → close editor
        if (!graphic && this.isEditorActive()) {

          console.log('[up-geojson-layer] editor closed');

          this.finishActiveEditor();
        }

        return;
      }

      // =========================
      // NORMAL POPUP MODE
      // =========================

      this.emitLayerEvent(
        "layerClick",
        this.buildMouseEvent(graphic, evt.mapPoint)
      );

      if (this.infoTemplate) {
        this.showGraphicPopup(graphic, evt.mapPoint);
      }

    }, 250);
  });

  const dblClickHandle = this.view.on("double-click", async (evt: any) => {

    evt.stopPropagation();

    doubleClickInProgress = true;

    if (clickTimer) {
      clearTimeout(clickTimer);
      clickTimer = null;
    }

    console.log('[up-geojson-layer] double click edit');

    const hit = await this.view.hitTest(evt, {
      include: [this.featureLayer]
    });

    let graphic = this.getLayerGraphicFromHit(hit);

    if (!graphic) {
      graphic = this.findNearestEditableGraphic(evt.mapPoint);
    }

    console.log('[up-geojson-layer] dblclick graphic:', {
      enableUserEdit: this.enableUserEdit,
      found: !!graphic,
      geometry: graphic?.geometry?.type,
      featureCount: this.featureLayer?.graphics?.length
    });

    if (this.enableUserEdit && graphic) {
      await this.activateGraphicsEditor(graphic);
    }

    // IMPORTANT
    setTimeout(() => {
      doubleClickInProgress = false;
    }, 400);
  });

  this.eventHandles.push(clickHandle);
  this.eventHandles.push(dblClickHandle);
}