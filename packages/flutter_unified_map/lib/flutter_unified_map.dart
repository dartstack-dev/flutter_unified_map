/// Native maps for Flutter with flutter_map's API: Google Maps on Android, MapKit on iOS and macOS, flutter_map
/// itself on web, Windows and Linux.
///
/// Code written for flutter_map 8 compiles by replacing `package:flutter_map/flutter_map.dart` with this library.
/// The pure data types of flutter_map (CRS, bounds, interaction flags, keyboard options, stroke patterns, tile
/// providers...) are flutter_map's own, re-exported; everything bound to the map widget is reimplemented with the
/// same API. Native-only settings live in `NativeParams` and the `nativeParams` of the layers.
library;

export 'package:flutter_map/flutter_map.dart'
    show
        AssetTileProvider,
        AttributionAlignment,
        BuiltInMapCachingProvider,
        CachedMapTile,
        CachedMapTileMetadata,
        CachedMapTileReadFailure,
        Crs,
        CrsSimple,
        CursorKeyboardRotationOptions,
        CursorRotationBehaviour,
        DisabledMapCachingProvider,
        Epsg3857,
        Epsg4326,
        ErrorTileCallBack,
        EvictErrorTileStrategy,
        FadeInTileDisplay,
        FileTileProvider,
        InstantaneousTileDisplay,
        InteractiveFlag,
        IsKeyCursorRotationTrigger,
        KeyboardOptions,
        LatLngBounds,
        LatLngTween,
        LogoSourceAttribution,
        MapCachingProvider,
        MultiFingerGesture,
        NetworkTileProvider,
        PatternFit,
        // ignore: deprecated_member_use
        PolygonLabelPlacement,
        PolygonPainterFillMethod,
        PositionedTapController,
        PositionedTapDetector2,
        Proj4Crs,
        Projection,
        RenderTranslucentPointer,
        RetinaMode,
        SourceAttribution,
        SphericalMercator,
        StrokePattern,
        TapPosition,
        TapPositionCallback,
        TextSourceAttribution,
        TileBuilder,
        TileCoordinates,
        TileDisplay,
        TileImage,
        TileProvider,
        TileUpdateEvent,
        TileUpdateTransformer,
        TileUpdateTransformers,
        TranslucentPointer,
        WMSTileLayerOptions,
        coordinateDebugTileBuilder,
        darkModeTileBuilder,
        darkModeTilesContainerBuilder,
        loadingTimeDebugTileBuilder;
export 'package:latlong2/latlong.dart' show LatLng;

export 'src/layer/attribution/rich_attribution_animation.dart';
export 'src/layer/attribution/rich_attribution_widget.dart';
export 'src/layer/attribution/simple_attribution_widget.dart';
export 'src/layer/circle_layer/circle_layer.dart';
export 'src/layer/circle_layer/circle_marker.dart';
export 'src/layer/flutter_map_layer/flutter_map_layer.dart';
export 'src/layer/marker_layer/marker.dart';
export 'src/layer/marker_layer/marker_layer.dart';
export 'src/layer/overlay_image_layer/overlay_image_layer.dart';
export 'src/layer/polygon_layer/label/placement_calculator.dart';
export 'src/layer/polygon_layer/polygon.dart';
export 'src/layer/polygon_layer/polygon_layer.dart';
export 'src/layer/polyline_layer/polyline.dart';
export 'src/layer/polyline_layer/polyline_layer.dart';
export 'src/layer/shared/layer_hit_result.dart';
export 'src/layer/scalebar/scalebar.dart';
export 'src/layer/shared/mobile_layer_transformer.dart';
export 'src/layer/tile_layer/tile_layer.dart' show TileLayer;
export 'src/map/camera/camera_constraint.dart';
export 'src/map/camera/camera_fit.dart';
export 'src/map/camera/map_camera.dart';
export 'src/map/controller/map_controller.dart';
export 'src/map/error/map_error.dart';
export 'src/map/error/map_error_view.dart';
export 'src/map/events/map_events.dart';
export 'src/map/options/interaction_options.dart';
export 'src/map/options/map_options.dart';
export 'src/map/conversions.dart' show StrokePatternDashes;
export 'src/map/unified_map.dart';
export 'src/native/native_params.dart';
export 'src/raster/widget_rasterizer.dart' show WidgetRasterizer;
