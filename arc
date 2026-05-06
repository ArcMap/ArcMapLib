private async activateGraphicsEditor(graphic: Graphic): Promise<void> {

  if (!this.graphicsEditor) {
    await this.createEditor();
  }

  if (!this.sketchLayer) {
    console.error('[up-geojson-layer] sketchLayer missing');
    return;
  }

  const editableGraphic = graphic.clone();

  this.sketchLayer.graphics.removeAll();

  this.sketchLayer.add(editableGraphic);

  await this.view.whenLayerView(this.sketchLayer);

  await new Promise(resolve => setTimeout(resolve, 200));

  const addedGraphic = this.sketchLayer.graphics.toArray()[0];

  console.log(
    '[up-geojson-layer] sketch graphics count',
    this.sketchLayer.graphics.length
  );

  console.log(
    '[up-geojson-layer] addedGraphic',
    addedGraphic
  );

  if (!addedGraphic) {
    console.error(
      '[up-geojson-layer] failed to add graphic to sketch layer'
    );
    return;
  }

  const tool = this.resolveUpdateTool(addedGraphic);

  this.graphicsEditor.update([addedGraphic], {
    tool,
    enableRotation: this.enableUserEditRotating,
    enableScaling: this.enableUserEditScaling,
    preserveAspectRatio: this.enableUserEditUniformScaling,
    multipleSelectionEnabled: false,
    toggleToolOnClick: false
  });

  console.log('[up-geojson-layer] editor opened');
}