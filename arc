private getDefaultSymbolForGeometry(
  geometry: Geometry | null | undefined,
  attributes?: any
): any {
  if (!geometry) return null;

  const rendererConfig = this.renderer
    ? JsonUtils.getJsonFor(this.renderer)
    : null;

  const parsedRenderer = rendererConfig?.parsedJson;

  // 1. Angular uniqueValue renderer wins
  if (parsedRenderer?.type === 'uniqueValue' && parsedRenderer?.uniqueValueInfos?.length) {
    const field1 = parsedRenderer.field1;
    const field2 = parsedRenderer.field2;

    const attrValue1 = attributes?.[field1];
    const attrValue2 = attributes?.[field2];

    const geometryKey =
      geometry.type === 'polygon'
        ? 'polygon'
        : geometry.type === 'polyline'
        ? 'polyline'
        : 'point';

    const matchedInfo = parsedRenderer.uniqueValueInfos.find((info: any) => {
      return (
        info.value === attrValue1 ||
        info.value === attrValue2 ||
        info.value === `${attrValue1}, ${attrValue2}` ||
        info.value === `${attrValue1},${attrValue2}` ||
        info.value === geometryKey ||
        String(info.value).includes(geometryKey)
      );
    });

    if (matchedInfo?.symbol) {
      return JsonUtils.normalizePlainSymbol(matchedInfo.symbol);
    }

    if (parsedRenderer.defaultSymbol) {
      return JsonUtils.normalizePlainSymbol(parsedRenderer.defaultSymbol);
    }
  }

  // 2. Angular simple renderer wins
  if (parsedRenderer?.symbol) {
    return JsonUtils.normalizePlainSymbol(parsedRenderer.symbol);
  }

  // 3. Angular defaultSymbol fallback
  if (parsedRenderer?.defaultSymbol) {
    return JsonUtils.normalizePlainSymbol(parsedRenderer.defaultSymbol);
  }

  // 4. Library fallback only when Angular did not pass renderer
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


private applyGraphicDefaults(graphic: Graphic): void {
  if (!graphic) return;

  if (graphic.geometry) {
    graphic.symbol = this.getDefaultSymbolForGeometry(
      graphic.geometry,
      graphic.attributes
    );
  }

  graphic.popupTemplate = this.enableUserEdit || this.inDrawingMode
    ? null as any
    : this.buildPopupTemplateFromCurrent(graphic);
}



if (!graphic.symbol) {
  graphic.symbol = this.getDefaultSymbolForGeometry(
    graphic.geometry,
    graphic.attributes
  );
}