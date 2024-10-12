package dev.alphabyte.flutter_unified_map_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LoadWatchdogTest {
    private val scheduled = mutableListOf<Runnable>()
    private var timeouts = 0
    private val watchdog = LoadWatchdog(
        15_000L,
        schedule = { runnable, _ -> scheduled += runnable },
        cancel = { scheduled -= it },
        onTimeout = { timeouts++ },
    )

    private fun elapse() = scheduled.toList().also { scheduled.clear() }.forEach { it.run() }

    @Test
    fun nothingIsTimedBeforeTheMapCanLoad() {
        watchdog.canLoad(false)
        assertTrue(scheduled.isEmpty())
        elapse()
        assertEquals(0, timeouts)
    }

    @Test
    fun aPauseStopsTheTimerAndAResumeStartsItAgain() {
        watchdog.canLoad(true)
        assertEquals(1, scheduled.size)
        watchdog.canLoad(false)
        assertTrue(scheduled.isEmpty())
        watchdog.canLoad(true)
        watchdog.canLoad(true)
        assertEquals(1, scheduled.size)
        elapse()
        assertEquals(1, timeouts)
        assertTrue(watchdog.failed)
    }

    @Test
    fun aLoadAfterTheTimeoutIsReportedOnceAndClearsTheError() {
        watchdog.canLoad(true)
        elapse()
        watchdog.canLoad(false)
        watchdog.canLoad(true)
        assertTrue(scheduled.isEmpty())
        assertTrue(watchdog.onLoaded())
        assertFalse(watchdog.failed)
        assertFalse(watchdog.onLoaded())
        assertEquals(1, timeouts)
    }

    @Test
    fun aLoadedOrStoppedMapIsNeverTimed() {
        watchdog.canLoad(true)
        assertTrue(watchdog.onLoaded())
        assertTrue(scheduled.isEmpty())
        watchdog.canLoad(true)
        assertTrue(scheduled.isEmpty())

        val stopped = LoadWatchdog(1L, { r, _ -> scheduled += r }, { scheduled -= it }, { timeouts++ })
        stopped.canLoad(true)
        stopped.stop()
        assertTrue(scheduled.isEmpty())
        assertFalse(stopped.onLoaded())
        assertEquals(0, timeouts)
    }
}
