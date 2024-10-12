package dev.alphabyte.flutter_unified_map_android

import androidx.lifecycle.Lifecycle
import io.flutter.plugin.platform.PlatformView

interface MapInstance : PlatformView {
    val id: Long

    fun attachLifecycle(lifecycle: Lifecycle)

    fun detachLifecycle()

    fun onLowMemory()

    /** The display density may have changed in place (`density` in the activity's configChanges). */
    fun onConfigurationChanged()

    fun updateOptions(options: PMapOptions)

    fun registerIcons(icons: List<PIcon>)

    fun updateMarkers(added: List<PMarker>, changed: List<PMarker>, removedIds: List<String>, transition: PMarkerTransition?)

    fun updatePolylines(added: List<PPolyline>, changed: List<PPolyline>, removedIds: List<String>)

    fun updatePolygons(added: List<PPolygon>, changed: List<PPolygon>, removedIds: List<String>)

    fun updateCircles(added: List<PCircle>, changed: List<PCircle>, removedIds: List<String>)

    fun updateTileLayers(added: List<PTileLayer>, changed: List<PTileLayer>, removedIds: List<String>)

    suspend fun moveCamera(update: PCameraUpdate, animationMillis: Long?)

    fun camera(): PCamera

    fun visibleRegion(): PLatLngBounds

    fun toScreen(position: PLatLng): PPoint

    fun toLatLng(screenPoint: PPoint): PLatLng

    suspend fun takeSnapshot(): ByteArray?
}
