{
  "symbols": {

    "simpleMarker_Point": {
      "OLD_STENCIL": {
        "type": "esriSMS",
        "style": "esriSMSCircle",
        "color": [255, 0, 0, 255],
        "size": "10px",
        "angle": 0,
        "xoffset": 0,
        "yoffset": 0,
        "outline": {
          "type": "esriSLS",
          "style": "esriSLSSolid",
          "color": [0, 0, 0, 255],
          "width": "1px"
        }
      },
      "NEW_LITELEMENT": {
        "type": "simple-marker",
        "style": "circle",
        "color": [255, 0, 0, 255],
        "size": 10,
        "angle": 0,
        "xoffset": 0,
        "yoffset": 0,
        "outline": {
          "type": "simple-line",
          "style": "solid",
          "color": [0, 0, 0, 255],
          "width": 1
        }
      }
    },

    "simpleLine_Polyline": {
      "OLD_STENCIL": {
        "type": "esriSLS",
        "style": "esriSLSSolid",
        "color": [0, 112, 255, 255],
        "width": "2px"
      },
      "NEW_LITELEMENT": {
        "type": "simple-line",
        "style": "solid",
        "color": [0, 112, 255, 255],
        "width": 2
      }
    },

    "simpleFill_Polygon": {
      "OLD_STENCIL": {
        "type": "esriSFS",
        "style": "esriSFSSolid",
        "color": [0, 255, 0, 128],
        "outline": {
          "type": "esriSLS",
          "style": "esriSLSSolid",
          "color": [0, 0, 0, 255],
          "width": "1px"
        }
      },
      "NEW_LITELEMENT": {
        "type": "simple-fill",
        "style": "solid",
        "color": [0, 255, 0, 128],
        "outline": {
          "type": "simple-line",
          "style": "solid",
          "color": [0, 0, 0, 255],
          "width": 1
        }
      }
    },

    "textSymbol_Label": {
      "OLD_STENCIL": {
        "type": "esriTS",
        "color": [0, 0, 0, 255],
        "haloColor": [255, 255, 255, 255],
        "haloSize": "1px",
        "horizontalAlignment": "esriTHACenter",
        "verticalAlignment": "esriTVABottom",
        "font": {
          "family": "Arial",
          "size": "12px",
          "style": "esriNormal",
          "weight": "esriBold",
          "decoration": "none"
        }
      },
      "NEW_LITELEMENT": {
        "type": "text",
        "color": [0, 0, 0, 255],
        "haloColor": [255, 255, 255, 255],
        "haloSize": 1,
        "horizontalAlignment": "center",
        "verticalAlignment": "bottom",
        "font": {
          "family": "Arial",
          "size": 12,
          "style": "normal",
          "weight": "bold",
          "decoration": "none"
        }
      }
    },

    "pictureMarker_ImagePoint": {
      "OLD_STENCIL": {
        "type": "esriPMS",
        "url": "https://example.com/icon.png",
        "contentType": "image/png",
        "width": "24px",
        "height": "24px",
        "angle": 0,
        "xoffset": 0,
        "yoffset": 0
      },
      "NEW_LITELEMENT": {
        "type": "picture-marker",
        "url": "https://example.com/icon.png",
        "contentType": "image/png",
        "width": 24,
        "height": 24,
        "angle": 0,
        "xoffset": 0,
        "yoffset": 0
      }
    },

    "pictureFill_ImagePolygon": {
      "OLD_STENCIL": {
        "type": "esriPFS",
        "url": "https://example.com/texture.png",
        "contentType": "image/png",
        "width": "32px",
        "height": "32px",
        "xscale": 1,
        "yscale": 1,
        "outline": {
          "type": "esriSLS",
          "style": "esriSLSSolid",
          "color": [0, 0, 0, 255],
          "width": "1px"
        }
      },
      "NEW_LITELEMENT": {
        "type": "picture-fill",
        "url": "https://example.com/texture.png",
        "contentType": "image/png",
        "width": 32,
        "height": 32,
        "xscale": 1,
        "yscale": 1,
        "outline": {
          "type": "simple-line",
          "style": "solid",
          "color": [0, 0, 0, 255],
          "width": 1
        }
      }
    },

    "renderers": {
      "simple": {
        "OLD_STENCIL": {
          "type": "simple",
          "symbol": { "type": "esriSMS", "style": "esriSMSCircle", "size": "10px" },
          "label": "All Features",
          "description": ""
        },
        "NEW_LITELEMENT": {
          "type": "simple",
          "symbol": { "type": "simple-marker", "style": "circle", "size": 10 },
          "label": "All Features",
          "description": ""
        }
      },
      "uniqueValue": {
        "OLD_STENCIL": {
          "type": "uniqueValue",
          "field1": "STATUS",
          "defaultSymbol": { "type": "esriSMS", "style": "esriSMSCircle", "size": "8px" },
          "uniqueValueInfos": [
            { "value": "ACTIVE", "symbol": { "type": "esriSMS", "style": "esriSMSCircle", "color": [0,255,0,255], "size": "10px" } },
            { "value": "INACTIVE", "symbol": { "type": "esriSMS", "style": "esriSMSCircle", "color": [255,0,0,255], "size": "10px" } }
          ]
        },
        "NEW_LITELEMENT": {
          "type": "unique-value",
          "field": "STATUS",
          "defaultSymbol": { "type": "simple-marker", "style": "circle", "size": 8 },
          "uniqueValueInfos": [
            { "value": "ACTIVE", "symbol": { "type": "simple-marker", "style": "circle", "color": [0,255,0,255], "size": 10 } },
            { "value": "INACTIVE", "symbol": { "type": "simple-marker", "style": "circle", "color": [255,0,0,255], "size": 10 } }
          ]
        }
      },
      "classBreaks": {
        "OLD_STENCIL": {
          "type": "classBreaks",
          "field": "POPULATION",
          "classBreakInfos": [
            { "classMinValue": 0, "classMaxValue": 1000, "symbol": { "type": "esriSMS", "style": "esriSMSCircle", "size": "6px" } },
            { "classMinValue": 1000, "classMaxValue": 5000, "symbol": { "type": "esriSMS", "style": "esriSMSCircle", "size": "12px" } }
          ]
        },
        "NEW_LITELEMENT": {
          "type": "class-breaks",
          "field": "POPULATION",
          "classBreakInfos": [
            { "minValue": 0, "maxValue": 1000, "symbol": { "type": "simple-marker", "style": "circle", "size": 6 } },
            { "minValue": 1000, "maxValue": 5000, "symbol": { "type": "simple-marker", "style": "circle", "size": 12 } }
          ]
        }
      }
    },

    "KEY_DIFFERENCES": {
      "type_strings":    { "OLD": "esriSMS / esriSLS / esriSFS / esriTS / esriPMS / esriPFS", "NEW": "simple-marker / simple-line / simple-fill / text / picture-marker / picture-fill" },
      "size_units":      { "OLD": "\"10px\" string", "NEW": "10 plain number" },
      "renderer_type":   { "OLD": "\"uniqueValue\"", "NEW": "\"unique-value\"" },
      "classBreaks":     { "OLD": "\"classBreaks\"", "NEW": "\"class-breaks\"" },
      "uniqueValue_field":{ "OLD": "\"field1\"", "NEW": "\"field\"" },
      "classBreak_range":{ "OLD": "classMinValue / classMaxValue", "NEW": "minValue / maxValue" },
      "haloSize":        { "OLD": "\"1px\" string", "NEW": "1 plain number" },
      "font_size":       { "OLD": "\"12px\" string", "NEW": "12 plain number" },
      "font_style":      { "OLD": "\"esriNormal\" / \"esriItalic\"", "NEW": "\"normal\" / \"italic\"" },
      "font_weight":     { "OLD": "\"esriBold\"", "NEW": "\"bold\"" },
      "h_alignment":     { "OLD": "\"esriTHACenter\"", "NEW": "\"center\"" },
      "v_alignment":     { "OLD": "\"esriTVABottom\"", "NEW": "\"bottom\"" }
    }

  }
}
