private setMapCursor(cursor: 'default' | 'pointer'): void {
  const styleId = 'arc-geojson-layer-cursor-override';

  let style = document.getElementById(styleId) as HTMLStyleElement | null;

  if (cursor === 'pointer') {
    if (!style) {
      style = document.createElement('style');
      style.id = styleId;
      document.head.appendChild(style);
    }

    style.textContent = `
      .esri-view,
      .esri-view *,
      .esri-view canvas,
      .esri-view .esri-view-surface {
        cursor: pointer !important;
      }
    `;

    try {
      (this.view as any).cursor = 'pointer';
    } catch {}

    return;
  }

  if (style) {
    style.remove();
  }

  try {
    (this.view as any).cursor = 'default';
  } catch {}




const graphic = this.getLayerGraphicFromHit(hit);

if (!graphic) {
  this.setMapCursor('default');
  return;
}

this.setMapCursor('pointer');