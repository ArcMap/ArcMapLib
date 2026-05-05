async connectedCallback(): Promise<void> {
  super.connectedCallback();

  // Wait for the ancestor map to be ready before initializing.
  // This handles Angular @if recreation — the element may be inserted
  // before up-map has finished initializing, or before closest() works.
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

private waitForAncestorMap(): Promise<void> {
  return new Promise<void>(resolve => {
    // If already inside up-map and it's ready, resolve immediately
    const mapEl = this.closest('arc-map') ?? this.closest('up-map');
    if (mapEl) {
      resolve();
      return;
    }
    // Otherwise wait for the nearest map to signal it's ready
    // using DOM insertion callback via MutationObserver on the parent
    const observer = new MutationObserver(() => {
      const found = this.closest('arc-map') ?? this.closest('up-map');
      if (found) {
        observer.disconnect();
        resolve();
      }
    });
    // Observe the parent chain for DOM changes
    observer.observe(document.body, { childList: true, subtree: true });
  });
}
