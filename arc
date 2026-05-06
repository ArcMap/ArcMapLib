private isEditorActive(): boolean {
  return (
    this.graphicsEditor?.state !== 'disabled' ||
    (this.sketchLayer?.graphics?.length ?? 0) > 0
  );
}