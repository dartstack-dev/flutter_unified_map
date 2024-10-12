package dev.alphabyte.flutter_unified_map_android

import android.graphics.SurfaceTexture
import android.view.Choreographer
import android.view.TextureView
import android.view.ViewGroup
import com.google.android.gms.maps.MapView
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/** Counts the frames Google Maps renders, so that a snapshot can wait until a marker change is drawn. */
class FrameWatcher(private val mapView: MapView) {
    private var rendersToTexture = false
    private var renderedFrames = 0L
    private var changedAt = 0L
    private val waiters = HashMap<CancellableContinuation<Unit>, Long>()
    private var released = false

    /**
     * With texture layer hybrid composition, Flutter only redraws the platform view when it is invalidated,
     * but the Maps SDK renders into its TextureView without invalidating the MapView.
     */
    fun install() {
        val textureView = findTextureView(mapView) ?: return
        rendersToTexture = true
        val inner = textureView.surfaceTextureListener
        textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                inner?.onSurfaceTextureAvailable(surface, width, height)
            }

            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
                inner?.onSurfaceTextureSizeChanged(surface, width, height)
            }

            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean =
                inner?.onSurfaceTextureDestroyed(surface) ?: true

            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
                inner?.onSurfaceTextureUpdated(surface)
                if (released) return
                mapView.invalidate()
                onFrameRendered()
            }
        }
    }

    fun markChanged() {
        changedAt = renderedFrames
    }

    /**
     * Google Maps renders on its own thread and `snapshot` returns the last frame it rendered. The frame delivered
     * right after a marker change may have been drawn before it, so wait for the one after that, but not for long:
     * an idle map renders only as many frames as the change needs.
     */
    suspend fun awaitChangeRendered() {
        if (!rendersToTexture) {
            awaitChoreographerFrames(2)
            return
        }
        val target = changedAt + 2
        if (renderedFrames >= target || released) return
        withTimeoutOrNull(RENDER_WAIT_MILLIS) {
            suspendCancellableCoroutine { continuation ->
                waiters[continuation] = target
                continuation.invokeOnCancellation { waiters.remove(continuation) }
            }
        }
    }

    fun release() {
        released = true
        waiters.keys.toList().forEach { if (it.isActive) it.resume(Unit) }
        waiters.clear()
    }

    private fun onFrameRendered() {
        renderedFrames++
        if (waiters.isEmpty()) return
        val due = waiters.filterValues { it <= renderedFrames }.keys
        waiters.keys.removeAll(due)
        due.forEach { if (it.isActive) it.resume(Unit) }
    }

    private suspend fun awaitChoreographerFrames(count: Int) {
        repeat(count) {
            suspendCancellableCoroutine { continuation ->
                val callback = Choreographer.FrameCallback { if (continuation.isActive) continuation.resume(Unit) }
                Choreographer.getInstance().postFrameCallback(callback)
                continuation.invokeOnCancellation { Choreographer.getInstance().removeFrameCallback(callback) }
            }
        }
    }

    private fun findTextureView(group: ViewGroup): TextureView? {
        for (i in 0 until group.childCount) {
            when (val child = group.getChildAt(i)) {
                is TextureView -> return child
                is ViewGroup -> findTextureView(child)?.let { return it }
            }
        }
        return null
    }

    companion object {
        /**
         * Upper bound only: the wait normally ends after the second rendered frame (40-120 ms on the emulator), but
         * under load 250 ms was hit and the snapshot still showed disappearing markers.
         */
        const val RENDER_WAIT_MILLIS = 1_000L
    }
}
