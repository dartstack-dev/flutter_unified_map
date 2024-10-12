/// Tolerance of [integerZoom]: MapKit reports zoom 5 as 4.9999999.
const integerZoomEpsilon = 1e-6;

/// The integer zoom level [zoom] is at, tolerating the rounding error of platforms that convert zoom to a span.
int integerZoom(double zoom) => (zoom + integerZoomEpsilon).floor();
