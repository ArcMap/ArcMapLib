private injectGeojsonStyles(): void {
  const styleId = 'arc-geojson-layer-cursor-style';

  if (document.getElementById(styleId)) return;

  const style = document.createElement('style');
  style.id = styleId;
  style.textContent = geojsonStyles.cssText;

  document.head.appendChild(style);
}



async connectedCallback(): Promise<void> {
  super.connectedCallback();

  this.injectGeojsonStyles();

  await this.waitForAncestorMap();

  // existing code...
}


private setMapCursor(cursor: 'default' | 'pointer'): void {
  const container = this.view?.container as HTMLElement;
  if (!container) return;

  if (cursor === 'pointer') {
    container.classList.add('cursor-pointer');
  } else {
    container.classList.remove('cursor-pointer');
  }

  try {
    (this.view as any).cursor = cursor;
  } catch {}
}