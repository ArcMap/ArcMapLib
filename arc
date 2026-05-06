private replaceGraphicInFeatureLayer(updatedGraphic: Graphic): void {
  const uid = this.getGraphicUniqueId(updatedGraphic);

  this.featureLayer.graphics.toArray().forEach((g: Graphic) => {
    if (this.getGraphicUniqueId(g) === uid) {
      this.featureLayer.remove(g);
    }
  });

  this.sketchLayer.graphics.toArray().forEach((g: Graphic) => {
    if (this.getGraphicUniqueId(g) === uid) {
      this.sketchLayer.remove(g);
    }
  });

  this.applyGraphicDefaults(updatedGraphic);
  this.featureLayer.add(updatedGraphic);
}



this.sketchLayer.remove(g);
this.applyGraphicDefaults(g);

if (!this.featureLayer.graphics.includes(g)) {
  this.featureLayer.add(g);
}

this.updateGeojsonWithChanges(g);




this.replaceGraphicInFeatureLayer(g);
this.updateGeojsonWithChanges(g);





const uid = this.getGraphicUniqueId(graphic);

this.featureLayer.graphics.toArray().forEach((g: Graphic) => {
  if (this.getGraphicUniqueId(g) === uid) {
    this.featureLayer.remove(g);
  }
});

this.sketchLayer.graphics.toArray().forEach((g: Graphic) => {
  if (this.getGraphicUniqueId(g) === uid) {
    this.sketchLayer.remove(g);
  }
});



private resolveUpdateTool(graphic?: Graphic): 'move' | 'reshape' | 'transform' {
  const isCircle =
    graphic?.attributes?.drawGeometryType === DrawGeometryTypes.CIRCLE;

  if (isCircle) {
    return 'transform';
  }

  if (
    graphic?.geometry?.type === 'polygon' &&
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