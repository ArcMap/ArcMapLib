private resolveUpdateTool(graphic?: Graphic): 'move' | 'reshape' | 'transform' {
  const geometryType = graphic?.geometry?.type;

  // Circle drawn by Sketch usually becomes polygon.
  // If you store shapeType/drawType, use that to keep circle as transform.
  const isCircle =
    graphic?.attributes?.drawGeometryType === DrawGeometryTypes.CIRCLE ||
    graphic?.attributes?.shapeType === DrawGeometryTypes.CIRCLE ||
    graphic?.attributes?.geometryType === DrawGeometryTypes.CIRCLE;

  if (isCircle) {
    return 'transform';
  }

  if (
    geometryType === 'polygon' &&
    (
      this.enableUserEditVertices ||
      this.enableUserEditAddVertices ||
      this.enableUserEditDeleteVertices
    )
  ) {
    return 'reshape';
  }

  if (this.enableUserEditScaling || this.enableUserEditRotating) {
    return 'transform';
  }

  return 'move';
}

