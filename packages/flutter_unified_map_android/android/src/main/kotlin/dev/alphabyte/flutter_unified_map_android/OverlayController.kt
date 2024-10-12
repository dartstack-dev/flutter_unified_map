package dev.alphabyte.flutter_unified_map_android

import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.model.Circle
import com.google.android.gms.maps.model.CircleOptions
import com.google.android.gms.maps.model.Dash
import com.google.android.gms.maps.model.Gap
import com.google.android.gms.maps.model.PatternItem
import com.google.android.gms.maps.model.Polygon
import com.google.android.gms.maps.model.PolygonOptions
import com.google.android.gms.maps.model.Polyline
import com.google.android.gms.maps.model.PolylineOptions

class OverlayController(private val map: GoogleMap, private val density: Density) {
    private class Line(val main: Polyline, var border: Polyline?)

    private class Entry<P, N>(var source: P, val native: N)

    private val lines = HashMap<String, Entry<PPolyline, Line>>()
    private val polygons = HashMap<String, Entry<PPolygon, Polygon>>()
    private val circles = HashMap<String, Entry<PCircle, Circle>>()

    fun updatePolylines(added: List<PPolyline>, changed: List<PPolyline>, removedIds: List<String>) =
        sync(lines, added, changed, removedIds, { it.id }, ::addLine, ::applyLine, ::removeLine)

    fun updatePolygons(added: List<PPolygon>, changed: List<PPolygon>, removedIds: List<String>) =
        sync(polygons, added, changed, removedIds, { it.id }, ::addPolygon, ::applyPolygon) { it.remove() }

    fun updateCircles(added: List<PCircle>, changed: List<PCircle>, removedIds: List<String>) =
        sync(circles, added, changed, removedIds, { it.id }, ::addCircle, ::applyCircle) { it.remove() }

    /** Widths and dashes are logical pixels: after a density change they are drawn again at the new scale. */
    fun onDensityChanged() {
        lines.values.forEach { applyLine(it.native, it.source) }
        polygons.values.forEach { applyPolygon(it.native, it.source) }
        circles.values.forEach { applyCircle(it.native, it.source) }
    }

    private fun <P, N> sync(
        store: HashMap<String, Entry<P, N>>,
        added: List<P>,
        changed: List<P>,
        removedIds: List<String>,
        id: (P) -> String,
        add: (P) -> N,
        apply: (N, P) -> Unit,
        remove: (N) -> Unit,
    ) {
        for (removedId in removedIds) store.remove(removedId)?.let { remove(it.native) }
        for (item in changed) {
            val entry = store[id(item)]
            if (entry == null) {
                store[id(item)] = Entry(item, add(item))
            } else {
                apply(entry.native, item)
                entry.source = item
            }
        }
        for (item in added) {
            store.remove(id(item))?.let { remove(it.native) }
            store[id(item)] = Entry(item, add(item))
        }
    }

    private fun addLine(polyline: PPolyline): Line {
        val border = if (polyline.borderWidth > 0) map.addPolyline(lineOptions(polyline, border = true)) else null
        return Line(map.addPolyline(lineOptions(polyline, border = false)), border)
    }

    private fun applyLine(line: Line, polyline: PPolyline) {
        applyLine(line.main, polyline, border = false)
        val border = line.border
        when {
            polyline.borderWidth <= 0 -> {
                border?.remove()
                line.border = null
            }
            border == null -> line.border = map.addPolyline(lineOptions(polyline, border = true))
            else -> applyLine(border, polyline, border = true)
        }
    }

    private fun removeLine(line: Line) {
        line.main.remove()
        line.border?.remove()
    }

    private fun lineOptions(polyline: PPolyline, border: Boolean): PolylineOptions = PolylineOptions()
        .addAll(polyline.points.map { it.toLatLng() })
        .width(LineStyle.width(polyline, border, density))
        .color(LineStyle.color(polyline, border).toColorInt())
        .zIndex(LineStyle.zIndex(polyline, border))
        .startCap(polyline.cap.toCap())
        .endCap(polyline.cap.toCap())
        .jointType(polyline.join.toJointType())
        .pattern(pattern(polyline))
        .geodesic(polyline.geodesic)
        .clickable(false)

    private fun applyLine(native: Polyline, polyline: PPolyline, border: Boolean) {
        native.points = polyline.points.map { it.toLatLng() }
        native.width = LineStyle.width(polyline, border, density)
        native.color = LineStyle.color(polyline, border).toColorInt()
        native.zIndex = LineStyle.zIndex(polyline, border)
        native.startCap = polyline.cap.toCap()
        native.endCap = polyline.cap.toCap()
        native.jointType = polyline.join.toJointType()
        native.pattern = pattern(polyline)
        native.isGeodesic = polyline.geodesic
    }

    private fun pattern(polyline: PPolyline): List<PatternItem>? =
        LineStyle.dashes(polyline, density)?.mapIndexed { index, length -> if (index % 2 == 0) Dash(length) else Gap(length) }

    private fun addPolygon(polygon: PPolygon): Polygon {
        val options = PolygonOptions()
            .addAll(polygon.points.map { it.toLatLng() })
            .fillColor(polygon.fillColorArgb.toColorInt())
            .strokeColor(polygon.strokeColorArgb.toColorInt())
            .strokeWidth(density.px(polygon.strokeWidth))
            .zIndex(polygon.zIndex.toFloat())
            .clickable(false)
        polygon.holes.forEach { hole -> options.addHole(hole.map { it.toLatLng() }) }
        return map.addPolygon(options)
    }

    private fun applyPolygon(native: Polygon, polygon: PPolygon) {
        native.points = polygon.points.map { it.toLatLng() }
        native.holes = polygon.holes.map { hole -> hole.map { it.toLatLng() } }
        native.fillColor = polygon.fillColorArgb.toColorInt()
        native.strokeColor = polygon.strokeColorArgb.toColorInt()
        native.strokeWidth = density.px(polygon.strokeWidth)
        native.zIndex = polygon.zIndex.toFloat()
    }

    private fun addCircle(circle: PCircle): Circle = map.addCircle(
        CircleOptions()
            .center(circle.center.toLatLng())
            .radius(circle.radiusMeters)
            .fillColor(circle.fillColorArgb.toColorInt())
            .strokeColor(circle.strokeColorArgb.toColorInt())
            .strokeWidth(density.px(circle.strokeWidth))
            .zIndex(circle.zIndex.toFloat())
            .clickable(false),
    )

    private fun applyCircle(native: Circle, circle: PCircle) {
        native.center = circle.center.toLatLng()
        native.radius = circle.radiusMeters
        native.fillColor = circle.fillColorArgb.toColorInt()
        native.strokeColor = circle.strokeColorArgb.toColorInt()
        native.strokeWidth = density.px(circle.strokeWidth)
        native.zIndex = circle.zIndex.toFloat()
    }
}

/** A polyline's border is a second, wider line beneath it: `width + borderWidth` wide in total, at `zIndex - 0.5`. */
object LineStyle {
    fun width(polyline: PPolyline, border: Boolean, density: Density): Float =
        density.px(if (border) polyline.width + polyline.borderWidth else polyline.width)

    fun color(polyline: PPolyline, border: Boolean): Long = if (border) polyline.borderColorArgb else polyline.colorArgb

    fun zIndex(polyline: PPolyline, border: Boolean): Float =
        (if (border) polyline.zIndex - 0.5 else polyline.zIndex).toFloat()

    /** Dash, gap, dash… in physical pixels; Google needs pairs, so an odd pattern is repeated once. */
    fun dashes(polyline: PPolyline, density: Density): List<Float>? {
        val dashes = polyline.dashPattern?.takeIf { it.isNotEmpty() } ?: return null
        val even = if (dashes.size % 2 == 0) dashes else dashes + dashes
        return even.map { density.px(it) }
    }
}
