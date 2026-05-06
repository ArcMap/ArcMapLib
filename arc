private getDefaultSymbolForGeometry(
  geometry: Geometry | null | undefined
): any {
  if (!geometry) return null;

  const rendererConfig = this.renderer
    ? JsonUtils.getJsonFor(this.renderer)
    : null;

  const parsedRenderer = rendererConfig?.parsedJson;
  const rendererSymbol = parsedRenderer?.symbol;

  // 1. Angular renderer wins
  if (rendererSymbol) {
    return JsonUtils.normalizePlainSymbol(rendererSymbol);
  }

  // 2. Library fallback only when Angular did not pass renderer
  let size = JsonUtils.DEFAULT_SYMBOL_MARKER_SIZE;

  if (ArcGeojsonLayer.isPolyline(geometry)) {
    size = JsonUtils.DEFAULT_SYMBOL_LINE_WIDTH;
  }

  if (ArcGeojsonLayer.isPolygon(geometry)) {
    size = JsonUtils.DEFAULT_SYMBOL_POLYGON_WIDTH;
  }

  return JsonUtils.getJsonSymbolFor(
    geometry.type,
    JsonUtils.getRandomColor(),
    size
  );
}