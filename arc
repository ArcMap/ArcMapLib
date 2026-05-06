.esri-view.cursor-pointer,
.esri-view.cursor-pointer *,
.esri-view.cursor-pointer canvas,
.esri-view.cursor-pointer .esri-view-surface {
  cursor: pointer !important;
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





if (!graphic) {
  this.setMapCursor('default');
  return;
}

this.setMapCursor('pointer');