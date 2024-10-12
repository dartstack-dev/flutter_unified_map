package dev.alphabyte.flutter_unified_map_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class LineStyleTest {
    private val density = Density { 2f }

    private fun polyline(dashPattern: List<Double>? = null) = PPolyline(
        id = "l",
        points = emptyList(),
        colorArgb = 0xFF0000FF,
        width = 5.0,
        borderColorArgb = 0xFFFFFFFF,
        borderWidth = 3.0,
        dashPattern = dashPattern,
        cap = PStrokeCap.ROUND,
        join = PStrokeJoin.ROUND,
        zIndex = 2.0,
        geodesic = false,
    )

    @Test
    fun theBorderIsWiderAndBeneath() {
        assertEquals(10f, LineStyle.width(polyline(), border = false, density))
        assertEquals(16f, LineStyle.width(polyline(), border = true, density))
        assertEquals(2f, LineStyle.zIndex(polyline(), border = false))
        assertEquals(1.5f, LineStyle.zIndex(polyline(), border = true))
        assertEquals(0xFFFFFFFF, LineStyle.color(polyline(), border = true))
        assertEquals(0xFF0000FF, LineStyle.color(polyline(), border = false))
    }

    @Test
    fun dashesAreInPhysicalPixelsAndPaired() {
        assertNull(LineStyle.dashes(polyline(), density))
        assertNull(LineStyle.dashes(polyline(emptyList()), density))
        assertEquals(listOf(24f, 16f), LineStyle.dashes(polyline(listOf(12.0, 8.0)), density))
        assertEquals(listOf(10f, 4f, 2f, 10f, 4f, 2f), LineStyle.dashes(polyline(listOf(5.0, 2.0, 1.0)), density))
    }

    @Test
    fun densityIsReadOnEachUse() {
        var scale = 2f
        val live = Density { scale }
        assertEquals(10f, LineStyle.width(polyline(), border = false, live))
        scale = 3f
        assertEquals(15f, LineStyle.width(polyline(), border = false, live))
    }
}
