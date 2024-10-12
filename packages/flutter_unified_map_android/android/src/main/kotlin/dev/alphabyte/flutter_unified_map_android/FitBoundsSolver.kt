package dev.alphabyte.flutter_unified_map_android

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.log2
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tan

/**
 * Web Mercator fit in logical pixels (Google Maps Android: the world is 256 dp wide at zoom 0).
 * Computed in Kotlin rather than with `CameraUpdateFactory.newLatLngBounds` so that asymmetric padding,
 * `maxZoom` and `bearing` collapse into one `CameraPosition` that can be animated in a single step.
 */
object FitBoundsSolver {
    private const val WORLD = 256.0

    data class Solution(val latitude: Double, val longitude: Double, val zoom: Double)

    fun solve(
        bounds: PLatLngBounds,
        fitPadding: PEdgeInsets,
        mapPadding: PEdgeInsets,
        viewWidth: Double,
        viewHeight: Double,
        maxZoom: Double?,
        zoomRange: ClosedFloatingPointRange<Double>,
        bearing: Double,
    ): Solution {
        val boxWidth = (viewWidth - mapPadding.left - mapPadding.right - fitPadding.left - fitPadding.right).coerceAtLeast(1.0)
        val boxHeight = (viewHeight - mapPadding.top - mapPadding.bottom - fitPadding.top - fitPadding.bottom).coerceAtLeast(1.0)

        val west = bounds.southWest.longitude
        var east = bounds.northEast.longitude
        if (east < west) east += 360.0
        val spanX = (east - west) / 360.0
        val spanY = mercatorY(bounds.southWest.latitude) - mercatorY(bounds.northEast.latitude)

        val rad = bearing * PI / 180.0
        val absCos = abs(cos(rad))
        val absSin = abs(sin(rad))
        val screenWidth = (spanX * absCos + spanY.coerceAtLeast(0.0) * absSin) * WORLD
        val screenHeight = (spanX * absSin + spanY.coerceAtLeast(0.0) * absCos) * WORLD
        var zoom = min(
            if (screenWidth > 1e-12) log2(boxWidth / screenWidth) else Double.POSITIVE_INFINITY,
            if (screenHeight > 1e-12) log2(boxHeight / screenHeight) else Double.POSITIVE_INFINITY,
        )
        if (zoom.isInfinite()) zoom = maxZoom ?: zoomRange.endInclusive
        if (maxZoom != null) zoom = min(zoom, maxZoom)
        // The padding shift below is converted to degrees at this zoom, so it must already be the zoom Google keeps.
        zoom = zoom.coerceIn(zoomRange)

        val scale = WORLD * 2.0.pow(zoom)
        val centerX = ((west + east) / 2.0 / 360.0 + 0.5) * scale
        val centerY = (mercatorY(bounds.southWest.latitude) + mercatorY(bounds.northEast.latitude)) / 2.0 * scale

        val shiftX = (fitPadding.right - fitPadding.left) / 2.0
        val shiftY = (fitPadding.bottom - fitPadding.top) / 2.0
        val worldDx = shiftX * cos(rad) - shiftY * sin(rad)
        val worldDy = shiftX * sin(rad) + shiftY * cos(rad)

        val targetX = centerX + worldDx
        val targetY = centerY + worldDy
        var lng = (targetX / scale - 0.5) * 360.0
        lng -= 360.0 * floor((lng + 180.0) / 360.0)
        val lat = inverseMercatorY(targetY / scale)
        return Solution(lat, lng, zoom)
    }

    private fun mercatorY(latitude: Double): Double {
        val clamped = latitude.coerceIn(-85.05112878, 85.05112878)
        val rad = clamped * PI / 180.0
        return 0.5 - ln(tan(PI / 4.0 + rad / 2.0)) / (2.0 * PI)
    }

    private fun inverseMercatorY(y: Double): Double {
        val n = PI - 2.0 * PI * y
        return (2.0 * atan(exp(n)) - PI / 2.0) * 180.0 / PI
    }
}
