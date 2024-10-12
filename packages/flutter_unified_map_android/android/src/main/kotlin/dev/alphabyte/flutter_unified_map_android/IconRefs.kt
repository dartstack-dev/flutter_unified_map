package dev.alphabyte.flutter_unified_map_android

/**
 * Which icon each marker references, counted per icon key. Mirrors the Dart side's `_IconBook`: an icon no marker
 * references after an update is dropped on both sides (the schema has no unregister call), so Dart sends it again
 * when it comes back.
 */
class IconRefs {
    private val keyByMarker = HashMap<String, String>()
    private val counts = HashMap<String, Int>()
    private val registered = HashSet<String>()

    fun registered(key: String) {
        registered.add(key)
    }

    /** Records an update; returns the icon keys to drop, among the ones it released and the ones registered for it. */
    fun update(removedIds: List<String>, placed: List<Pair<String, String>>): Set<String> {
        val released = HashSet<String>(registered)
        registered.clear()
        for (id in removedIds) keyByMarker.remove(id)?.let { released.add(it); decrement(it) }
        for ((id, key) in placed) {
            val previous = keyByMarker.put(id, key)
            if (previous == key) continue
            if (previous != null) {
                released.add(previous)
                decrement(previous)
            }
            counts[key] = (counts[key] ?: 0) + 1
        }
        released.removeAll { it in counts }
        return released
    }

    fun clear() {
        keyByMarker.clear()
        counts.clear()
        registered.clear()
    }

    private fun decrement(key: String) {
        val count = (counts[key] ?: return) - 1
        if (count <= 0) counts.remove(key) else counts[key] = count
    }
}
