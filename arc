private getDefaultSymbolForGeometry(
  geometry: Geometry | null | undefined
): any {
  if (!geometry) return null;

  const rendererConfig = this.renderer
    ? JsonUtils.getJsonFor(this.renderer)
    : null;

  const parsedRenderer = rendererConfig?.parsedJson;
  const rendererSymbol = parsedRenderer?.symbol;

  if (rendererSymbol) {
    const symbol = JsonUtils.normalizePlainSymbol(rendererSymbol);

    if (ArcGeojsonLayer.isPolygon(geometry) && symbol?.color) {
      const c = symbol.color.toArray ? symbol.color.toArray() : symbol.color;

      symbol.color = [
        c[0] ?? 0,
        c[1] ?? 0,
        c[2] ?? 255,
        c[3] !== undefined ? Math.min(c[3], 90) : 90
      ] as any;
    }

    return symbol;
  }

  let size = JsonUtils.DEFAULT_SYMBOL_MARKER_SIZE;

  if (ArcGeojsonLayer.isPolyline(geometry)) {
    size = JsonUtils.DEFAULT_SYMBOL_LINE_WIDTH;
  }

  if (ArcGeojsonLayer.isPolygon(geometry)) {
    size = JsonUtils.DEFAULT_SYMBOL_POLYGON_WIDTH;
  }

  return JsonUtils.getJsonSymbolFor(
    geometry.type,
    JsonUtils.DEFAULT_SYMBOL_COLOR,
    size
  );
}