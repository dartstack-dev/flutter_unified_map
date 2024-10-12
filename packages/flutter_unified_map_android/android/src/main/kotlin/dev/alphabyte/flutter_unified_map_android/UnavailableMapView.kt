package dev.alphabyte.flutter_unified_map_android

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.lifecycle.Lifecycle

/** Stands in for the Google map when it cannot be created: it reports why once and never becomes ready. */
class UnavailableMapView(
    context: Context,
    private val viewId: Long,
    options: PMapOptions,
    private val reason: MapUnavailable,
    private val events: EventSink,
    private val onDisposed: (MapInstance) -> Unit,
) : MapInstance {
    override val id: Long get() = viewId

    private val view = FrameLayout(context).apply { setBackgroundColor(options.backgroundColorArgb.toColorInt()) }
    private val handler = Handler(Looper.getMainLooper())
    private val reportError = Runnable { if (!disposed) events.onMapError(viewId, reason.code, reason.message) }
    private var disposed = false

    fun start() {
        handler.post(reportError)
    }

    override fun getView(): View = view

    override fun dispose() {
        if (disposed) return
        disposed = true
        handler.removeCallbacks(reportError)
        onDisposed(this)
    }

    override fun attachLifecycle(lifecycle: Lifecycle) {}

    override fun detachLifecycle() {}

    override fun onLowMemory() {}

    override fun onConfigurationChanged() {}

    override fun updateOptions(options: PMapOptions) {}

    override fun registerIcons(icons: List<PIcon>) {}

    override fun updateMarkers(
        added: List<PMarker>,
        changed: List<PMarker>,
        removedIds: List<String>,
        transition: PMarkerTransition?,
    ) {}

    override fun updatePolylines(added: List<PPolyline>, changed: List<PPolyline>, removedIds: List<String>) {}

    override fun updatePolygons(added: List<PPolygon>, changed: List<PPolygon>, removedIds: List<String>) {}

    override fun updateCircles(added: List<PCircle>, changed: List<PCircle>, removedIds: List<String>) {}

    override fun updateTileLayers(added: List<PTileLayer>, changed: List<PTileLayer>, removedIds: List<String>) {}

    override suspend fun moveCamera(update: PCameraUpdate, animationMillis: Long?) {}

    override fun camera(): PCamera = throw notReady()

    override fun visibleRegion(): PLatLngBounds = throw notReady()

    override fun toScreen(position: PLatLng): PPoint = throw notReady()

    override fun toLatLng(screenPoint: PPoint): PLatLng = throw notReady()

    override suspend fun takeSnapshot(): ByteArray? = null

    private fun notReady() = FlutterError("not-ready", "Map view $viewId never becomes ready: ${reason.message}", null)
}
