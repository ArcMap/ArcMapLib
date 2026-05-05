private updateGeoJsonWithChanges(graphicToUpdate: Graphic): void {
  if (!graphicToUpdate?.geometry) {
    console.warn('[arc-geojson-layer] updateGeoJsonWithChanges: no geometry, skipping');
    return;
  }

  this.blockGeoJsonUpdate = true;
  this.geojson = this.tagAsInternal(this.toFeatureCollectionFromLayer());
  this.blockGeoJsonUpdate = false;
  this.refreshLabels();
  this.rebuildSourceCache();

  const feature = graphicToGeoJsonFeature(graphicToUpdate, this.uniqueIdPropertyName);

  if (!feature?.geometry) {
    console.warn('[arc-geojson-layer] updateGeoJsonWithChanges: feature geometry null, skipping emit');
    return;
  }

  this.emitLayerEvent('userEditItemUpdated', feature);
}


const updateHandle = this.graphicsEditor.on('update', (evt: any) => {
  if (!evt.toolEventInfo) return;
  const type: string = evt.toolEventInfo.type;

  if (type === 'move-start') this.graphicMoved = false;
  if (type === 'move') this.graphicMoved = true;

  // Only fire on STOP events — geometry is stable at this point
  if (['rotate-stop', 'scale-stop', 'reshape-stop',
       'vertex-add', 'vertex-remove'].includes(type)) {
    evt.graphics?.forEach((g: Graphic) => {
      if (g?.geometry) this.updateGeoJsonWithChanges(g);
    });
  }

  if (type === 'move-stop' && this.graphicMoved) {
    this.graphicMoved = false;
    evt.graphics?.forEach((g: Graphic) => {
      if (g?.geometry) this.updateGeoJsonWithChanges(g);
    });
  }
});
