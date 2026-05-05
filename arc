const dblClickHandle = (this.view as any).on('double-click', (evt: any) => {
  evt.stopPropagation?.();

  setTimeout(() => {
    const nearest = this.findNearest(evt.mapPoint);
    if (!nearest) return;

    console.log('[arc-geojson-layer] double-click - activating editor for:',
      nearest.geometry?.type);

    // Force enable edit mode and activate editor directly
    this.enableUserEdit = true;
    this.activateGraphicsEditor(nearest);

    // Notify Angular that edit mode was enabled via double-click
    this.emitLayerEvent('userEditEnabled', 
      graphicToGeoJsonFeature(nearest, this.uniqueIdPropertyName));
  }, 100);
});
this.eventHandles.push(dblClickHandle);
