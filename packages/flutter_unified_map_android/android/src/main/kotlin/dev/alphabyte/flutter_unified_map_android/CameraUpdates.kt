package dev.alphabyte.flutter_unified_map_android

import com.google.android.gms.maps.CameraUpdate
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import kotlin.math.max
import kotlin.math.min

object CameraUpdates {
    fun build(
        map: GoogleMap,
        update: PCameraUpdate,
        density: Density,
        viewWidthPx: Int,
        viewHeightPx: Int,
        options: PMapOptions,
    ): CameraUpdate {
        val current = map.cameraPosition
        update.newCamera?.let { camera ->
            return CameraUpdateFactory.newCameraPosition(merge(current.toPCamera(), camera).toCameraPosition())
        }
        update.fitBounds?.let { fit ->
            val bearing = fit.bearing ?: current.bearing.toDouble()
            val minZoom = max(options.minZoom, map.minZoomLevel.toDouble())
            val maxZoom = max(minZoom, min(options.maxZoom, map.maxZoomLevel.toDouble()))
            val solution = FitBoundsSolver.solve(
                fit.bounds,
                fit.padding,
                options.padding,
                density.logical(viewWidthPx),
                density.logical(viewHeightPx),
                fit.maxZoom,
                minZoom..maxZoom,
                bearing,
            )
            val position = CameraPosition.Builder()
                .target(LatLng(solution.latitude, solution.longitude))
                .zoom(solution.zoom.toFloat())
                .bearing(bearing.toFloat())
                .tilt(0f)
                .build()
            return CameraUpdateFactory.newCameraPosition(position)
        }
        update.scrollBy?.let { return CameraUpdateFactory.scrollBy(density.px(it.dx), density.px(it.dy)) }
        update.zoomBy?.let { zoom ->
            val focus = zoom.focus ?: return CameraUpdateFactory.zoomBy(zoom.amount.toFloat())
            return CameraUpdateFactory.zoomBy(zoom.amount.toFloat(), density.toPoint(focus))
        }
        throw FlutterError("invalid-update", "PCameraUpdate has no variant set", null)
    }

    /** The fields [camera] leaves null keep their current value. */
    fun merge(current: PCamera, camera: PNewCamera): PCamera = PCamera(
        camera.center ?: current.center,
        camera.zoom ?: current.zoom,
        camera.bearing ?: current.bearing,
        camera.tilt ?: current.tilt,
    )
}
