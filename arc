private setMapCursor(cursor: 'default' | 'pointer'): void {
  const container = this.view?.container as HTMLElement;
  if (!container) return;

  container.classList.toggle('arc-geojson-hover-pointer', cursor === 'pointer');

  let style = document.getElementById('arc-geojson-hover-pointer-style') as HTMLStyleElement | null;

  if (!style) {
    style = document.createElement('style');
    style.id = 'arc-geojson-hover-pointer-style';
    style.textContent = `
      .arc-geojson-hover-pointer,
      .arc-geojson-hover-pointer *,
      .arc-geojson-hover-pointer canvas,
      .arc-geojson-hover-pointer .esri-view-surface,
      .arc-geojson-hover-pointer .esri-view-root,
      .arc-geojson-hover-pointer .esri-view-surface--inset-outline {
        cursor: pointer !important;
      }
    `;
    document.head.appendChild(style);
  }

  try {
    (this.view as any).cursor = cursor;
  } catch {}
}



if (!graphic) {
  this.setMapCursor('default');
  return;
}

this.setMapCursor('pointer');

console.log('cursor check:', {
  found: true,
  type: graphic.geometry?.type,
  classAdded: (this.view.container as HTMLElement).classList.contains('arc-geojson-hover-pointer'),
  computedCursor: getComputedStyle(this.view.container as HTMLElement).cursor
});


