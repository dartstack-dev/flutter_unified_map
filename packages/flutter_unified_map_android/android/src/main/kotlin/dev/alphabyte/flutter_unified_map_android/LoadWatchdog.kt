package dev.alphabyte.flutter_unified_map_android

/**
 * Reports a load timeout when Google Maps has not loaded within [timeoutMillis] of time in which it could load: a
 * paused, stopped or zero-sized MapView renders nothing, so it never calls its loaded callback.
 */
class LoadWatchdog(
    private val timeoutMillis: Long,
    private val schedule: (Runnable, Long) -> Unit,
    private val cancel: (Runnable) -> Unit,
    private val onTimeout: () -> Unit,
) {
    var loaded = false
        private set

    /** The timeout fired and no load followed yet. */
    var failed = false
        private set

    private var armed = false
    private var stopped = false
    private val timeout = Runnable {
        armed = false
        if (stopped || loaded) return@Runnable
        failed = true
        onTimeout()
    }

    /** Each time the map becomes able to load, the full timeout starts again. */
    fun canLoad(value: Boolean) {
        if (value && !armed && !loaded && !failed && !stopped) {
            armed = true
            schedule(timeout, timeoutMillis)
        } else if (!value) {
            disarm()
        }
    }

    /** Returns whether this load is news to Dart: the first one, which also clears a timeout error. */
    fun onLoaded(): Boolean {
        if (stopped) return false
        disarm()
        if (loaded) return false
        loaded = true
        failed = false
        return true
    }

    fun stop() {
        stopped = true
        disarm()
    }

    private fun disarm() {
        if (!armed) return
        armed = false
        cancel(timeout)
    }
}
