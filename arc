if (this.enableUserEdit) {

  // Ignore click immediately after double-click.
  if (doubleClickInProgress) {
    return;
  }

  // If editor is open and user clicked INSIDE same graphic,
  // do not close editor.
  if (graphic && this.isEditorActive()) {
    return;
  }

  // Close editor only when user clicks outside all graphics.
  if (!graphic && this.isEditorActive()) {
    console.log('[up-geojson-layer] closing editor from outside click');

    this.finishActiveEditor();
  }

  return;
}