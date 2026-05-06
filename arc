this.sketchLayer.graphics.removeAll();

const editableGraphic = new Graphic({
  geometry: graphic.geometry.clone(),
  attributes: { ...(graphic.attributes ?? {}) },
  symbol: graphic.symbol ?? this.getDefaultSymbolForGeometry(graphic.geometry),
  popupTemplate: null as any
});

this.sketchLayer.graphics.add(editableGraphic);

await this.view.whenLayerView(this.sketchLayer);
await new Promise(resolve => setTimeout(resolve, 100));

console.log('[up-geojson-layer] sketch graphics count', this.sketchLayer.graphics.length);

if (this.sketchLayer.graphics.length === 0) {
  console.error('[up-geojson-layer] failed to add graphic to sketch layer');
  return;
}

const tool = this.resolveUpdateTool(editableGraphic);

this.graphicsEditor.update([editableGraphic], {
  tool,
  enableRotation: this.enableUserEditRotating,
  enableScaling: this.enableUserEditScaling,
  preserveAspectRatio: this.enableUserEditUniformScaling,
  multipleSelectionEnabled: false,
  toggleToolOnClick: false
});