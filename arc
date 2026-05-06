private getLayerGraphicFromHit(hit: any): Graphic | undefined {
  return hit?.results
    ?.map((r: any) => r.graphic)
    ?.find((g: Graphic) => {
      const layer = g?.layer;
      return (
        g?.geometry &&
        (
          layer === this.featureLayer ||
          layer === this.sketchLayer ||
          layer?.id === this.featureLayer?.id ||
          layer?.id === this.sketchLayer?.id
        )
      );
    });
}