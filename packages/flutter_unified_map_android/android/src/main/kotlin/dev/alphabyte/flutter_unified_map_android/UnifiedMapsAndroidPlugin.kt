package dev.alphabyte.flutter_unified_map_android

import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter

class UnifiedMapsAndroidPlugin : FlutterPlugin, ActivityAware {
    private val views = MapViews()
    private var lifecycle: Lifecycle? = null
    private var applicationContext: Context? = null
    private var events: EventSink? = null

    private val componentCallbacks = object : ComponentCallbacks2 {
        override fun onConfigurationChanged(newConfig: Configuration) {
            views.all().forEach { it.onConfigurationChanged() }
        }

        @Suppress("DEPRECATION")
        override fun onTrimMemory(level: Int) {
            // UI_HIDDEN only means the app went to the background, which is no reason to drop the map's caches.
            if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW && level != ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) {
                views.all().forEach { it.onLowMemory() }
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onLowMemory() {
            views.all().forEach { it.onLowMemory() }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val events = EventSink(UnifiedMapsFlutterApi(binding.binaryMessenger)).also { this.events = it }
        UnifiedMapsHostApi.setUp(binding.binaryMessenger, HostApiImpl(views))
        binding.platformViewRegistry.registerViewFactory(MapViewFactory.VIEW_TYPE, MapViewFactory(views, events) { lifecycle })
        applicationContext = binding.applicationContext.also { it.registerComponentCallbacks(componentCallbacks) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UnifiedMapsHostApi.setUp(binding.binaryMessenger, null)
        applicationContext?.unregisterComponentCallbacks(componentCallbacks)
        applicationContext = null
        views.all().forEach { it.dispose() }
        events?.close()
        events = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding).also { this.lifecycle = it }
        views.all().forEach { it.attachLifecycle(lifecycle) }
    }

    override fun onDetachedFromActivityForConfigChanges() = detachFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    // Views that outlive the activity (cached engine, add-to-app) must not have their MapView destroyed by its
    // ON_DESTROY: see UnifiedMapView.onDestroy.
    override fun onDetachedFromActivity() = detachFromActivity()

    private fun detachFromActivity() {
        lifecycle = null
        views.all().forEach { it.detachLifecycle() }
    }
}
