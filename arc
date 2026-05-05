// esriSMS or simple-marker → SimpleMarkerSymbol
if (type === 'esrisms' || type === 'simple-marker' ||
    ArcGeojsonLayer.isPoint(geometry)) {
  const outlineColor = rendererSymbol?.outline?.color ?? sym.outline?.color ?? [0, 0, 0, 200];
  const outlineWidth = rendererSymbol?.outline?.width ?? sym.outline?.width ?? 1;
  return new SimpleMarkerSymbol({
    style: this.esriStyleToArcGIS(sym.style, 'circle') as any,
    size: sym.size ?? size,
    color: sym.color,
    outline: new SimpleLineSymbol({ color: outlineColor, width: outlineWidth })
  });
}

// esriSLS or simple-line → SimpleLineSymbol
if (type === 'esrisls' || type === 'simple-line' ||
    ArcGeojsonLayer.isPolyline(geometry)) {
  return new SimpleLineSymbol({
    style: this.esriStyleToArcGIS(sym.style, 'solid') as any,
    width: sym.width ?? size,
    color: sym.color
  });
}

// esriSFS or simple-fill → SimpleFillSymbol
const outlineColor = rendererSymbol?.outline?.color
  ?? sym.outline?.color ?? [110, 110, 110, 255];
const outlineWidth = rendererSymbol?.outline?.width
  ?? sym.outline?.width ?? ArcGeojsonLayer.DEFAULT_SYMBOL_LINE_WIDTH;

return new SimpleFillSymbol({
  style: this.esriStyleToArcGIS(sym.style, 'solid') as any,
  color: sym.color,
  outline: new SimpleLineSymbol({ color: outlineColor, width: outlineWidth })
});
