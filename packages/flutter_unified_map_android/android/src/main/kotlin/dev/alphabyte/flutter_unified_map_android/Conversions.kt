package dev.alphabyte.flutter_unified_map_android

import android.graphics.Point
import com.google.android.gms.maps.model.ButtCap
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.Cap
import com.google.android.gms.maps.model.JointType
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.android.gms.maps.model.RoundCap
import com.google.android.gms.maps.model.SquareCap
import kotlin.math.roundToInt

// Contract stub: the previous boolean switches derived from the flutter_map flags; the Android unit replaces them
// with one native switch per flag.
private const val DRAG = 1L
private const val PINCH_MOVE = 1L shl 2
private const val PINCH_ZOOM = 1L shl 3
private const val DOUBLE_TAP_ZOOM = 1L shl 4
private const val SCROLL_WHEEL_ZOOM = 1L shl 6
private const val ROTATE = 1L shl 7

val PInteraction.scrollEnabled: Boolean get() = flags and (DRAG or PINCH_MOVE) != 0L
val PInteraction.zoomEnabled: Boolean get() = flags and (PINCH_ZOOM or SCROLL_WHEEL_ZOOM) != 0L
val PInteraction.rotateEnabled: Boolean get() = flags and ROTATE != 0L
val PInteraction.doubleTapZoomEnabled: Boolean get() = flags and DOUBLE_TAP_ZOOM != 0L

fun PLatLng.toLatLng(): LatLng = LatLng(latitude, longitude)

fun LatLng.toPLatLng(): PLatLng = PLatLng(latitude, longitude)

fun PLatLngBounds.toLatLngBounds(): LatLngBounds = LatLngBounds(southWest.toLatLng(), northEast.toLatLng())

fun LatLngBounds.toPLatLngBounds(): PLatLngBounds = PLatLngBounds(southwest.toPLatLng(), northeast.toPLatLng())

fun CameraPosition.toPCamera(): PCamera = PCamera(target.toPLatLng(), zoom.toDouble(), bearing.toDouble(), tilt.toDouble())

fun PCamera.toCameraPosition(): CameraPosition =
    CameraPosition.Builder().target(center.toLatLng()).zoom(zoom.toFloat()).bearing(bearing.toFloat()).tilt(tilt.toFloat()).build()

fun Long.toColorInt(): Int = this.toInt()

fun PStrokeCap.toCap(): Cap = when (this) {
    PStrokeCap.BUTT -> ButtCap()
    PStrokeCap.ROUND -> RoundCap()
    PStrokeCap.SQUARE -> SquareCap()
}

fun PStrokeJoin.toJointType(): Int = when (this) {
    PStrokeJoin.MITER -> JointType.DEFAULT
    PStrokeJoin.ROUND -> JointType.ROUND
    PStrokeJoin.BEVEL -> JointType.BEVEL
}

/** Read on each use: with `density` in the activity's configChanges, the scale changes while the view lives on. */
class Density(private val read: () -> Float) {
    val value: Float get() = read()

    fun px(logical: Double): Float = (logical * value).toFloat()

    fun pxInt(logical: Double): Int = (logical * value).roundToInt()

    fun logical(px: Int): Double = px / value.toDouble()

    fun logical(px: Float): Double = px / value.toDouble()

    fun toPoint(logical: PPoint): Point = Point(pxInt(logical.x), pxInt(logical.y))

    fun toPPoint(px: Point): PPoint = PPoint(logical(px.x), logical(px.y))
}

internal const val TAG = "UnifiedMaps"
