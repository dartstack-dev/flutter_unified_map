package dev.alphabyte.flutter_unified_map_android

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tan
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FitBoundsSolverTest {
    private val noPadding = PEdgeInsets(0.0, 0.0, 0.0, 0.0)

    private fun worldPoint(latitude: Double, longitude: Double, zoom: Double): Pair<Double, Double> {
        val scale = 256.0 * 2.0.pow(zoom)
        val rad = latitude * PI / 180.0
        val y = 0.5 - ln(tan(PI / 4.0 + rad / 2.0)) / (2.0 * PI)
        return Pair((longitude / 360.0 + 0.5) * scale, y * scale)
    }

    private fun screenOffset(
        point: PLatLng,
        solution: FitBoundsSolver.Solution,
        bearing: Double,
    ): Pair<Double, Double> {
        val (px, py) = worldPoint(point.latitude, point.longitude, solution.zoom)
        val (tx, ty) = worldPoint(solution.latitude, solution.longitude, solution.zoom)
        val dx = px - tx
        val dy = py - ty
        val rad = bearing * PI / 180.0
        return Pair(dx * cos(rad) + dy * sin(rad), -dx * sin(rad) + dy * cos(rad))
    }

    @Test
    fun symmetricFitCentersBoundsAndFillsTheLimitingAxis() {
        val bounds = PLatLngBounds(PLatLng(48.0, 2.0), PLatLng(49.0, 3.0))
        val solution = FitBoundsSolver.solve(bounds, noPadding, noPadding, 400.0, 800.0, null, 0.0..21.0, 0.0)
        val (west, north) = worldPoint(49.0, 2.0, solution.zoom)
        val (east, _) = worldPoint(48.0, 3.0, solution.zoom)
        assertEquals(400.0, east - west, 1e-6)
        val center = screenOffset(PLatLng(48.5, 2.5), solution, 0.0)
        assertEquals(0.0, center.first, 1e-6)
        val (_, south) = worldPoint(48.0, 2.0, solution.zoom)
        val (_, ty) = worldPoint(solution.latitude, solution.longitude, solution.zoom)
        assertEquals(0.0, (north + south) / 2.0 - ty, 1e-6)
    }

    @Test
    fun clampedZoomKeepsThePointCenteredInThePaddedBox() {
        val point = PLatLng(45.0, 5.0)
        val bounds = PLatLngBounds(PLatLng(45.0 - 1e-6, 5.0 - 1e-6), PLatLng(45.0 + 1e-6, 5.0 + 1e-6))
        val padding = PEdgeInsets(0.0, 0.0, 0.0, 300.0)
        val solution = FitBoundsSolver.solve(bounds, padding, noPadding, 400.0, 800.0, null, 3.0..18.0, 0.0)
        assertEquals(18.0, solution.zoom, 1e-9)
        val (x, y) = screenOffset(point, solution, 0.0)
        assertEquals(0.0, x, 1e-6)
        assertEquals(-150.0, y, 1e-6)
    }

    @Test
    fun zoomIsRaisedToTheMinimum() {
        val bounds = PLatLngBounds(PLatLng(-60.0, -170.0), PLatLng(70.0, 170.0))
        val solution = FitBoundsSolver.solve(bounds, noPadding, noPadding, 400.0, 800.0, null, 5.0..18.0, 0.0)
        assertEquals(5.0, solution.zoom, 1e-9)
    }

    @Test
    fun fitMaxZoomCapsTheZoom() {
        val point = PLatLng(45.0, 5.0)
        val solution = FitBoundsSolver.solve(PLatLngBounds(point, point), noPadding, noPadding, 400.0, 800.0, 12.0, 0.0..21.0, 0.0)
        assertEquals(12.0, solution.zoom, 1e-9)
    }

    @Test
    fun asymmetricPaddingFollowsTheBearing() {
        val point = PLatLng(45.0, 5.0)
        val padding = PEdgeInsets(100.0, 40.0, 20.0, 200.0)
        for (bearing in listOf(0.0, 37.0, 90.0, 180.0, 270.0)) {
            val solution = FitBoundsSolver.solve(PLatLngBounds(point, point), padding, noPadding, 400.0, 800.0, 16.0, 0.0..21.0, bearing)
            val (x, y) = screenOffset(point, solution, bearing)
            assertEquals((100.0 - 20.0) / 2.0, x, 1e-6, "x at bearing $bearing")
            assertEquals((40.0 - 200.0) / 2.0, y, 1e-6, "y at bearing $bearing")
        }
    }

    @Test
    fun rotatedFitUsesTheRotatedOutline() {
        val bounds = PLatLngBounds(PLatLng(-0.5, -1.0), PLatLng(0.5, 1.0))
        val flat = FitBoundsSolver.solve(bounds, noPadding, noPadding, 400.0, 400.0, null, 0.0..21.0, 0.0)
        val quarter = FitBoundsSolver.solve(bounds, noPadding, noPadding, 400.0, 400.0, null, 0.0..21.0, 90.0)
        val diagonal = FitBoundsSolver.solve(bounds, noPadding, noPadding, 400.0, 400.0, null, 0.0..21.0, 45.0)
        assertEquals(flat.zoom, quarter.zoom, 1e-6)
        assertTrue(diagonal.zoom < flat.zoom)
    }
}
