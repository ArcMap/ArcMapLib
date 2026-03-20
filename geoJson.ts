export enum DrawGeometryTypes {
  // polyline
  FREEHAND_POLYLINE = 'freehand_polyline',
  LINE = 'line',
  POLYLINE = 'polyline',

  // multipoint
  MULTI_POINT = 'multi_point',

  // point
  POINT = 'point',

  // polygon
  ARROW = 'arrow',
  CIRCLE = 'circle',
  DOWN_ARROW = 'down_arrow',
  ELLIPSE = 'ellipse',
  EXTENT = 'extent',
  FREEHAND_POLYGON = 'freehand_polygon',
  LEFT_ARROW = 'left_arrow',
  POLYGON = 'polygon',
  RECTANGLE = 'rectangle',
  RIGHT_ARROW = 'right_arrow',
  TRIANGLE = 'triangle',
  UP_ARROW = 'up_arrow',
}

export default class DrawEditUtils {
  static DrawGeometryTypes = DrawGeometryTypes;

  static validGeometryType(drawGeometryType: string, layerGeometryType: string): boolean {
    const requiredLayerType = this.determineFeatureLayerGeometryType(drawGeometryType);

    if (this.normalizeLayerGeometry(layerGeometryType) !== this.normalizeLayerGeometry(requiredLayerType)) {
      console.error(
        `The geojson geometry type needs to be a ${this.convertEsriGeometryTypeToHumanReadable(requiredLayerType)} ` +
        `to draw the geometry ${drawGeometryType}.`
      );
      return false;
    }

    return true;
  }

  static determineFeatureLayerGeometryType(drawGeometryType: string): string {
    switch ((drawGeometryType ?? '').toLowerCase()) {
      case DrawGeometryTypes.FREEHAND_POLYLINE:
      case DrawGeometryTypes.LINE:
      case DrawGeometryTypes.POLYLINE:
        return 'polyline';

      case DrawGeometryTypes.MULTI_POINT:
        return 'multipoint';

      case DrawGeometryTypes.POINT:
        return 'point';

      case DrawGeometryTypes.ARROW:
      case DrawGeometryTypes.CIRCLE:
      case DrawGeometryTypes.DOWN_ARROW:
      case DrawGeometryTypes.ELLIPSE:
      case DrawGeometryTypes.EXTENT:
      case DrawGeometryTypes.FREEHAND_POLYGON:
      case DrawGeometryTypes.LEFT_ARROW:
      case DrawGeometryTypes.POLYGON:
      case DrawGeometryTypes.RECTANGLE:
      case DrawGeometryTypes.RIGHT_ARROW:
      case DrawGeometryTypes.TRIANGLE:
      case DrawGeometryTypes.UP_ARROW:
      default:
        return 'polygon';
    }
  }

  static determineSketchCreateTool(
    drawGeometryType: string
  ): 'point' | 'polyline' | 'polygon' | 'rectangle' | 'circle' {
    switch ((drawGeometryType ?? '').toLowerCase()) {
      case DrawGeometryTypes.FREEHAND_POLYLINE:
      case DrawGeometryTypes.LINE:
      case DrawGeometryTypes.POLYLINE:
        return 'polyline';

      case DrawGeometryTypes.MULTI_POINT:
      case DrawGeometryTypes.POINT:
        return 'point';

      case DrawGeometryTypes.RECTANGLE:
      case DrawGeometryTypes.EXTENT:
        return 'rectangle';

      case DrawGeometryTypes.CIRCLE:
        return 'circle';

      case DrawGeometryTypes.ARROW:
      case DrawGeometryTypes.DOWN_ARROW:
      case DrawGeometryTypes.ELLIPSE:
      case DrawGeometryTypes.FREEHAND_POLYGON:
      case DrawGeometryTypes.LEFT_ARROW:
      case DrawGeometryTypes.POLYGON:
      case DrawGeometryTypes.RIGHT_ARROW:
      case DrawGeometryTypes.TRIANGLE:
      case DrawGeometryTypes.UP_ARROW:
      default:
        return 'polygon';
    }
  }

  static isFreehand(drawGeometryType: string): boolean {
    const value = (drawGeometryType ?? '').toLowerCase();
    return value === DrawGeometryTypes.FREEHAND_POLYLINE || value === DrawGeometryTypes.FREEHAND_POLYGON;
  }

  static normalizeLayerGeometry(layerGeometryType: string): string {
    return (layerGeometryType ?? '').trim().toLowerCase();
  }

  private static convertEsriGeometryTypeToHumanReadable(layerGeometryType: string): string {
    switch (this.normalizeLayerGeometry(layerGeometryType)) {
      case 'polyline':
        return 'Polyline';
      case 'multipoint':
        return 'MultiPoint';
      case 'point':
        return 'Point';
      case 'polygon':
      default:
        return 'Polygon';
    }
  }
}
