package dev.alphabyte.flutter_unified_map_android

class HostApiImpl(private val views: MapViews) : UnifiedMapsHostApi {
    override fun dispose(viewId: Long) {
        views[viewId]?.dispose()
    }

    override fun updateOptions(viewId: Long, options: PMapOptions) {
        views[viewId]?.updateOptions(options)
    }

    override fun registerIcons(viewId: Long, icons: List<PIcon>) {
        views[viewId]?.registerIcons(icons)
    }

    override fun updateMarkers(
        viewId: Long,
        added: List<PMarker>,
        changed: List<PMarker>,
        removedIds: List<String>,
        transition: PMarkerTransition?,
    ) {
        views[viewId]?.updateMarkers(added, changed, removedIds, transition)
    }

    override fun updatePolylines(viewId: Long, added: List<PPolyline>, changed: List<PPolyline>, removedIds: List<String>) {
        views[viewId]?.updatePolylines(added, changed, removedIds)
    }

    override fun updatePolygons(viewId: Long, added: List<PPolygon>, changed: List<PPolygon>, removedIds: List<String>) {
        views[viewId]?.updatePolygons(added, changed, removedIds)
    }

    override fun updateCircles(viewId: Long, added: List<PCircle>, changed: List<PCircle>, removedIds: List<String>) {
        views[viewId]?.updateCircles(added, changed, removedIds)
    }

    override fun updateTileLayers(viewId: Long, added: List<PTileLayer>, changed: List<PTileLayer>, removedIds: List<String>) {
        views[viewId]?.updateTileLayers(added, changed, removedIds)
    }

    // Contract stubs (see AGENTS.md): accepted and ignored until the Android unit implements them.
    override fun updateGroundOverlays(
        viewId: Long,
        added: List<PGroundOverlay>,
        changed: List<PGroundOverlay>,
        removedIds: List<String>,
    ) {}

    override fun resetTileLayer(viewId: Long, tileLayerId: String) {}

    override fun unregisterIcons(viewId: Long, keys: List<String>) {}

    override fun stopCamera(viewId: Long) {}

    override suspend fun moveCamera(viewId: Long, update: PCameraUpdate, animationMillis: Long?) {
        views[viewId]?.moveCamera(update, animationMillis)
    }

    override fun getCamera(viewId: Long): PCamera = view(viewId).camera()

    override fun getVisibleRegion(viewId: Long): PLatLngBounds = view(viewId).visibleRegion()

    override fun toScreen(viewId: Long, position: PLatLng): PPoint = view(viewId).toScreen(position)

    override fun toLatLng(viewId: Long, screenPoint: PPoint): PLatLng = view(viewId).toLatLng(screenPoint)

    override suspend fun takeSnapshot(viewId: Long): ByteArray? = views[viewId]?.takeSnapshot()

    private fun view(viewId: Long): MapInstance =
        views[viewId] ?: throw FlutterError("unknown-view", "No map view with id $viewId", null)
}
