package dev.alphabyte.flutter_unified_map_android

import android.content.Context
import android.util.Log
import androidx.lifecycle.Lifecycle
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MapViewFactory(
    private val views: MapViews,
    private val events: EventSink,
    private val lifecycle: () -> Lifecycle?,
) : PlatformViewFactory(UnifiedMapsHostApi.codec) {
    /** [args] is `[viewId, PMapOptions]`, encoded by the Dart side with the Pigeon codec. */
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val (rawViewId, rawOptions) = args as List<*>
        val viewId = (rawViewId as Number).toLong()
        val options = rawOptions as PMapOptions
        val unavailable = MapAvailability.check(context)
        if (unavailable != null) {
            Log.e(TAG, unavailable.message)
            val view = UnavailableMapView(context, viewId, options, unavailable, events) { views.remove(it) }
            views.add(view)
            view.start()
            return view
        }
        val view = UnifiedMapView(context, viewId, options, events) { views.remove(it) }
        views.add(view)
        view.start(lifecycle())
        return view
    }

    companion object {
        const val VIEW_TYPE = "flutter_unified_map_android/map"
    }
}
