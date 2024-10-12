package dev.alphabyte.flutter_unified_map_android

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.view.animation.PathInterpolator
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.Marker
import com.google.android.gms.maps.model.MarkerOptions

class MarkerController(private val map: GoogleMap, private val density: Density) {
    private class State(var appliedIconKey: String?, var tappable: Boolean)

    private val bitmaps = HashMap<String, Bitmap>()
    private val descriptors = HashMap<String, BitmapDescriptor>()
    private val states = HashMap<String, State>()
    private val iconRefs = IconRefs()
    private val missingLogged = HashSet<String>()

    /** Stands in for a missing icon: without one, Google draws its default red pin. */
    private val blank: BitmapDescriptor by lazy {
        BitmapDescriptorFactory.fromBitmap(Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888))
    }

    private val transitions = MarkerTransitions<GoogleMarker>(AnimatorClock)

    fun registerIcons(icons: List<PIcon>) {
        for (icon in icons) {
            val decoded = BitmapFactory.decodeByteArray(icon.pngBytes, 0, icon.pngBytes.size)
            if (decoded == null) {
                Log.w(TAG, "icon ${icon.key}: the PNG cannot be decoded")
                continue
            }
            val width = density.pxInt(icon.logicalSize.width).coerceAtLeast(1)
            val height = density.pxInt(icon.logicalSize.height).coerceAtLeast(1)
            bitmaps[icon.key] = if (decoded.width == width && decoded.height == height) decoded
            else Bitmap.createScaledBitmap(decoded, width, height, true)
            descriptors.remove(icon.key)
            missingLogged.remove(icon.key)
            iconRefs.registered(icon.key)
        }
    }

    fun update(added: List<PMarker>, changed: List<PMarker>, removedIds: List<String>, transition: PMarkerTransition?) {
        for (id in removedIds) states.remove(id)
        val placed = changed + added
        transitions.update(
            removedIds,
            placed.map { Placement(it.id, it.position.toFrame(), it) },
            transition?.let { pigeon ->
                MarkerTransition(
                    pigeon.durationMillis,
                    pigeon.appearFrom.mapValues { it.value.toFrame() },
                    pigeon.disappearTo.mapValues { it.value.toFrame() },
                )
            },
            create = { marker, frame -> add(marker, frame) },
            reuse = { marker, native -> apply(native.marker, marker) },
        )
        for (key in iconRefs.update(removedIds, placed.map { it.id to it.iconKey })) {
            bitmaps.remove(key)
            descriptors.remove(key)
        }
    }

    fun isTappable(id: String): Boolean = states[id]?.tappable == true

    fun isDisappearing(marker: Marker): Boolean {
        val id = marker.tag as? String ?: return false
        return transitions.isDisappearing(id, GoogleMarker(marker))
    }

    /** See [MarkerTransitions.beginSnapshot]. */
    fun beginSnapshot(): Boolean = transitions.beginSnapshot()

    fun endSnapshot() = transitions.endSnapshot()

    /** Forgets every marker without removing it from the map, which is being destroyed. */
    fun clear() {
        transitions.clear()
        states.clear()
        iconRefs.clear()
        descriptors.clear()
        bitmaps.clear()
    }

    private fun add(marker: PMarker, frame: MarkerFrame): GoogleMarker? {
        val descriptor = descriptor(marker.iconKey)
        val position = LatLng(frame.latitude, frame.longitude)
        val options = MarkerOptions()
            .position(position)
            .alpha(frame.alpha)
            .anchor(marker.anchor.x.toFloat(), marker.anchor.y.toFloat())
            .zIndex(marker.zIndex.toFloat())
            .flat(marker.flat)
            .rotation(marker.rotation.toFloat())
            .icon(descriptor ?: blank)
        val native = map.addMarker(options) ?: return null
        native.tag = marker.id
        states[marker.id] = State(marker.iconKey.takeIf { descriptor != null }, marker.tappable)
        return GoogleMarker(native, MarkerFrame(position.latitude, position.longitude, frame.alpha))
    }

    /** Also restores the zIndex of a revived marker, which [GoogleMarker.sendToBack] lowered. */
    private fun apply(native: Marker, marker: PMarker) {
        val state = states.getOrPut(marker.id) { State(null, marker.tappable) }
        if (state.appliedIconKey != marker.iconKey) {
            val descriptor = descriptor(marker.iconKey)
            native.setIcon(descriptor ?: blank)
            state.appliedIconKey = marker.iconKey.takeIf { descriptor != null }
        }
        native.setAnchor(marker.anchor.x.toFloat(), marker.anchor.y.toFloat())
        native.zIndex = marker.zIndex.toFloat()
        native.isFlat = marker.flat
        native.rotation = marker.rotation.toFloat()
        state.tappable = marker.tappable
    }

    private fun descriptor(key: String): BitmapDescriptor? {
        descriptors[key]?.let { return it }
        val bitmap = bitmaps[key]
        if (bitmap == null) {
            if (missingLogged.add(key)) Log.w(TAG, "icon $key was never registered or could not be decoded")
            return null
        }
        return BitmapDescriptorFactory.fromBitmap(bitmap).also { descriptors[key] = it }
    }
}

/**
 * Keeps the frame it last set, so that transitions do not read it back through the Maps SDK. Equal when the markers
 * are: Google Maps hands listeners a new [Marker] wrapper for the same marker.
 */
private class GoogleMarker(val marker: Marker, private var cached: MarkerFrame? = null) : MarkerHandle {
    override var frame: MarkerFrame
        get() = cached ?: MarkerFrame(marker.position.latitude, marker.position.longitude, marker.alpha).also { cached = it }
        set(value) {
            val position = LatLng(value.latitude, value.longitude)
            marker.position = position
            marker.alpha = value.alpha
            cached = MarkerFrame(position.latitude, position.longitude, value.alpha)
        }

    override var isVisible: Boolean
        get() = marker.isVisible
        set(value) {
            marker.isVisible = value
        }

    override fun sendToBack() {
        marker.zIndex = -Float.MAX_VALUE
    }

    override fun remove() = marker.remove()

    override fun equals(other: Any?): Boolean = other is GoogleMarker && other.marker == marker

    override fun hashCode(): Int = marker.hashCode()
}

/** cubic-bezier(0.42, 0, 0.58, 1): the ease-in-out of MapKit's backend and of Flutter's Curves.easeInOut. */
private object AnimatorClock : TransitionClock {
    override fun play(durationMillis: Long, onFrame: (Float) -> Unit, onEnd: () -> Unit): Playback {
        val animator = ValueAnimator.ofFloat(0f, 1f)
        animator.duration = durationMillis
        animator.interpolator = PathInterpolator(0.42f, 0f, 0.58f, 1f)
        animator.addUpdateListener { onFrame(it.animatedValue as Float) }
        animator.addListener(
            object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) = onEnd()
            },
        )
        animator.start()
        return Playback { animator.cancel() }
    }
}

private fun PLatLng.toFrame() = MarkerFrame(latitude, longitude, 1f)
