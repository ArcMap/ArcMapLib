async startDrawing(drawGeometryType: string): Promise<void> {
  if (!this.featureLayer || !this.view) return;

  console.log('startDrawing called with:', drawGeometryType);

  const existingType = this.determineExistingGeometryType();
  if (
    existingType &&
    !this.validGeometryType(drawGeometryType, existingType)
  ) return;

  // Cancel any existing editor
  if (this.graphicsEditor) {
    try { this.graphicsEditor.cancel(); } catch { }
    try { this.graphicsEditor.destroy(); } catch { }
  }

  // Recreate SketchViewModel fresh each time
  this.graphicsEditor = new SketchViewModel({
    view: this.view,
    layer: this.featureLayer,
    defaultUpdateOptions: {
      enableRotation: this.enableUserEditRotating,
      enableScaling: this.enableUserEditScaling,
      multipleSelectionEnabled: false,
      preserveAspectRatio: this.enableUserEditUniformScaling,
      toggleToolOnClick: false
    },
    updateOnGraphicClick: false
  });

  this.graphicsEditor.on('create', (evt: any) => {
    console.log('create event state:', evt.state,
      'graphic:', evt.graphic?.geometry?.type);

    if (evt.state === 'complete' && evt.graphic) {
      console.log('DRAWING COMPLETE');
      this.inDrawingMode = false;
      this.blockGeoJsonUpdate = false;
      this.addToGeojson(evt.graphic);
      this.enableInfoPopupWindow(false);

      setTimeout(() => {
        console.log('500ms after complete - graphics count:',
          this.featureLayer?.graphics?.length);
        console.log('blockGeoJsonUpdate:', this.blockGeoJsonUpdate);
      }, 500);

      setTimeout(() => {
        console.log('2000ms after complete - graphics count:',
          this.featureLayer?.graphics?.length);
      }, 2000);

      return;
    }

    if (evt.state === 'cancel') {
      console.log('DRAWING CANCELLED');
      this.inDrawingMode = false;
      this.blockGeoJsonUpdate = false;
      return;
    }

    if (evt.state === 'active' || evt.state === 'start') {
      console.log('DRAWING ACTIVE - keeping block');
      this.inDrawingMode = true;
      this.blockGeoJsonUpdate = true;
    }
  });

  this.graphicsEditor.on('update', (evt: any) => {
    if (evt.state === 'start') {
      this.graphicMoved = false;
    }
    if (evt.toolEventInfo?.type === 'move-start') this.graphicMoved = true;
    if (evt.toolEventInfo?.type === 'reshape-start') this.graphicMoved = true;
    if (evt.toolEventInfo?.type === 'scale-start') this.graphicMoved = true;
    if (evt.toolEventInfo?.type === 'rotate-start') this.graphicMoved = true;

    if (evt.state === 'complete' && evt.graphics?.length) {
      for (const graphic of evt.graphics) {
        this.updateGeojsonWithChanges(graphic);
      }
      this.enableInfoPopupWindow(true);
    }

    if (evt.state === 'cancel') {
      this.enableInfoPopupWindow(true);
    }
  });

  // Set flags BEFORE create
  this.inDrawingMode = true;
  this.blockGeoJsonUpdate = true;
  this.enableInfoPopupWindow(false);

  const tool = this.toSketchCreateTool(drawGeometryType);
  console.log('creating sketch tool:', tool);

  // Small delay to ensure view is ready
  await new Promise(resolve => setTimeout(resolve, 100));

  this.graphicsEditor.create(tool);

  console.log('graphicsEditor state after create:',
    this.graphicsEditor.state);
}
