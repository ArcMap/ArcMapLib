const nativeDblClick = async (event: MouseEvent) => {
  event.preventDefault();
  event.stopPropagation();

  if (clickTimer) {
    clearTimeout(clickTimer);
    clickTimer = null;
  }

  console.log('[arc-geojson-layer] native dblclick fired');

  const rect = this.view.container.getBoundingClientRect();

  const screenPoint = {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top
  };

  const hit = await this.view.hitTest(screenPoint, {
    include: [this.featureLayer, this.sketchLayer]
  });

  let graphic = this.getLayerGraphicFromHit(hit);

  if (!graphic) {
    graphic = this.findNearestGraphic(this.view.toMap(screenPoint) as Point);
  }

  console.log('[arc-geojson-layer] native dblclick graphic:', {
    enableUserEdit: this.enableUserEdit,
    found: !!graphic,
    geometry: graphic?.geometry?.type
  });

  if (!graphic) return;

  this.emitLayerEvent(
    'doubleClick',
    this.buildMouseEvent(graphic, this.view.toMap(screenPoint) as Point)
  );

  if (this.enableUserEdit) {
    await this.activateGraphicsEditor(graphic);
  }
};

this.view.container.addEventListener('dblclick', nativeDblClick, true);

this.eventHandles.push({
  remove: () => {
    this.view.container.removeEventListener('dblclick', nativeDblClick, true);
  }
});



private findNearestGraphic(_mapPoint: Point): Graphic | undefined {
  return this.featureLayer?.graphics
    ?.toArray()
    ?.find((g: Graphic) => !!g.geometry);
}

