disconnectedCallback(): void {
  super.disconnectedCallback();
  console.log('[arc-geojson-layer] disconnectedCallback - name:', this.name,
    'featureLayer on map:', this.view?.map?.layers?.includes(this.featureLayer),
    'graphics count:', this.featureLayer?.graphics?.length);
  // ... rest unchanged
}


async connectedCallback(): Promise<void> {
  super.connectedCallback();
  console.log('[arc-geojson-layer] connectedCallback - name:', this.name,
    'existing layers on map:', this.view?.map?.layers?.length);
