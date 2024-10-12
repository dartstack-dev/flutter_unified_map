package dev.alphabyte.flutter_unified_map_android

class MapViews {
    private val views = HashMap<Long, MapInstance>()

    operator fun get(viewId: Long): MapInstance? = views[viewId]

    fun add(view: MapInstance) {
        views.put(view.id, view)?.takeIf { it !== view }?.dispose()
    }

    fun remove(view: MapInstance) {
        if (views[view.id] === view) views.remove(view.id)
    }

    fun all(): List<MapInstance> = views.values.toList()
}
