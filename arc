private async createEditor(): Promise<void> {
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
      return;
    }

    if (evt.state === 'cancel') {
      console.log('DRAWING CANCELLED');
      this.inDrawingMode = false;
      this.blockGeoJsonUpdate = false;
      return;
    }

    // Handle 'active' state — drawing is in progress
    // Make sure block stays active
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
}


async startDrawing(drawGeometryType: string): Promise<void> {
  if (!this.featureLayer || !this.view) return;
  if (!this.graphicsEditor) {
    console.error('arc-geojson-layer: graphicsEditor not ready');
    return;
  }

  const existingType = this.determineExistingGeometryType();
  if (
    existingType &&
    !this.validGeometryType(drawGeometryType, existingType)
  ) return;

  console.log('startDrawing called with:', drawGeometryType);

  this.inDrawingMode = true;
  this.blockGeoJsonUpdate = true;

  this.enableInfoPopupWindow(false);

  const tool = this.toSketchCreateTool(drawGeometryType);
  console.log('creating sketch tool:', tool);

  this.graphicsEditor.create(tool);

  console.log('graphicsEditor state after create:', this.graphicsEditor.state);
}
