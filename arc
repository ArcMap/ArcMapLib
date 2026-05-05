private async waitForAncestorMap(): Promise<void> {
  // If already inside up-map, resolve immediately
  const mapEl = this.closest('arc-map') ?? this.closest('up-map');
  if (mapEl) return;

  // Otherwise wait for DOM insertion via MutationObserver
  await new Promise<void>(resolve => {
    const observer = new MutationObserver(() => {
      if (this.closest('arc-map') ?? this.closest('up-map')) {
        observer.disconnect();
        resolve();
      }
    });
    observer.observe(document.body, {
      childList: true,
      subtree: true,
    });
  });
}


async connectedCallback(): Promise<void> {
  super.connectedCallback();
  
  await this.waitForAncestorMap();
  
  if (!this.isConnected) return;

  console.log('[arc-geojson-layer] connectedCallback START');
  try {
    await this.resolveAncestorMapAndView();
    await this.createLayer(this.geojson);
    this._readyResolve();
    this._initComplete = true;
    console.log('[arc-geojson-layer] connectedCallback COMPLETE');
    if (this._pendingEnableUserEdit !== undefined) {
      await this.updateEditing(this._pendingEnableUserEdit);
      this._pendingEnableUserEdit = undefined;
    }
  } catch (e) {
    console.error('[arc-geojson-layer] connectedCallback error:', e);
  }
}
