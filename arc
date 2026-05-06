private setMapCursor(cursor: 'default' | 'pointer'): void {
  try {
    (this.view as any).cursor = cursor;
  } catch {}

  try {
    const container = this.view?.container as HTMLElement;
    if (container) {
      container.style.cursor = cursor;
    }

    const surface = container?.querySelector('.esri-view-surface') as HTMLElement;
    if (surface) {
      surface.style.cursor = cursor;
    }

    const canvas = container?.querySelector('canvas') as HTMLElement;
    if (canvas) {
      canvas.style.cursor = cursor;
    }
  } catch {}
}