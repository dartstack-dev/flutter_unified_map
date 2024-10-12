package dev.alphabyte.flutter_unified_map_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class MarkerTransitionsTest {
    private class Pin(override var frame: MarkerFrame) : MarkerHandle {
        override var isVisible = true
        var atBack = false
        var removed = false
        var reused = 0

        override fun sendToBack() {
            atBack = true
        }

        override fun remove() {
            removed = true
        }
    }

    private class Play(val durationMillis: Long, val onFrame: (Float) -> Unit, val onEnd: () -> Unit) {
        var cancelled = false
        var ended = false

        fun at(fraction: Float) = onFrame(fraction)

        fun end() {
            if (ended) return
            ended = true
            onEnd()
        }
    }

    private class FakeClock : TransitionClock {
        val plays = mutableListOf<Play>()
        var endImmediately = false

        override fun play(durationMillis: Long, onFrame: (Float) -> Unit, onEnd: () -> Unit): Playback {
            val play = Play(durationMillis, onFrame, onEnd)
            plays += play
            if (endImmediately) {
                play.at(1f)
                play.end()
            }
            return Playback {
                play.cancelled = true
                play.end()
            }
        }
    }

    private val clock = FakeClock()
    private val transitions = MarkerTransitions<Pin>(clock)
    private val created = mutableListOf<Pin>()

    private fun frame(latitude: Double, longitude: Double, alpha: Float = 1f) = MarkerFrame(latitude, longitude, alpha)

    private fun assertFrame(expected: MarkerFrame, actual: MarkerFrame) {
        assertEquals(expected.latitude, actual.latitude, 1e-6)
        assertEquals(expected.longitude, actual.longitude, 1e-6)
        assertEquals(expected.alpha, actual.alpha, 1e-6f)
    }

    private fun update(
        removed: List<String> = emptyList(),
        placed: List<Pair<String, MarkerFrame>> = emptyList(),
        transition: MarkerTransition? = null,
    ) = transitions.update(
        removed,
        placed.map { (id, frame) -> Placement(id, frame, id) },
        transition,
        create = { _, start -> Pin(start).also { created += it } },
        reuse = { _, pin -> pin.reused++ },
    )

    private fun animated(
        appearFrom: Map<String, MarkerFrame> = emptyMap(),
        disappearTo: Map<String, MarkerFrame> = emptyMap(),
    ) = MarkerTransition(300, appearFrom, disappearTo)

    private val parent = frame(47.0, 10.0)
    private val child = frame(48.0, 12.0)

    @Test
    fun anInstantUpdatePlacesMarkersOpaqueWithoutPlaying() {
        update(placed = listOf("a" to child))
        assertFrame(child, transitions["a"]!!.frame)
        update(placed = listOf("a" to parent), transition = MarkerTransition(0))
        assertFrame(parent, transitions["a"]!!.frame)
        update(removed = listOf("a"))
        assertTrue(created.single().removed)
        assertNull(transitions["a"])
        assertTrue(clock.plays.isEmpty())
    }

    @Test
    fun anAddedMarkerSlidesFromItsParentWhileFadingIn() {
        update(placed = listOf("a" to child), transition = animated(appearFrom = mapOf("a" to parent)))
        val pin = transitions["a"]!!
        assertFrame(frame(47.0, 10.0, 0f), pin.frame)
        val play = clock.plays.single()
        assertEquals(300, play.durationMillis)
        play.at(0.5f)
        assertFrame(frame(47.5, 11.0, 0.5f), pin.frame)
        play.end()
        assertFrame(child, pin.frame)
    }

    @Test
    fun anAddedMarkerWithoutParentFadesInInPlace() {
        update(placed = listOf("a" to child), transition = animated())
        clock.plays.single().at(0.25f)
        assertFrame(frame(48.0, 12.0, 0.25f), transitions["a"]!!.frame)
    }

    @Test
    fun aChangedPositionGlidesAndAnUnchangedMarkerIsLeftAlone() {
        update(placed = listOf("a" to parent, "b" to child))
        update(placed = listOf("a" to child, "b" to child), transition = animated())
        val play = clock.plays.single()
        play.at(0.5f)
        assertFrame(frame(47.5, 11.0, 1f), transitions["a"]!!.frame)
        assertFrame(child, transitions["b"]!!.frame)
        assertEquals(1, transitions["a"]!!.reused)
        assertEquals(1, transitions["b"]!!.reused)
    }

    @Test
    fun aRemovedMarkerSlidesIntoItsParentFadesOutAndIsRemovedAtTheEnd() {
        update(placed = listOf("a" to child))
        val pin = transitions["a"]!!
        update(removed = listOf("a"), transition = animated(disappearTo = mapOf("a" to parent)))
        assertNull(transitions["a"])
        assertTrue(pin.atBack)
        assertTrue(transitions.isDisappearing("a", pin))
        val play = clock.plays.single()
        play.at(0.5f)
        assertFrame(frame(47.5, 11.0, 0.5f), pin.frame)
        assertFalse(pin.removed)
        play.end()
        assertTrue(pin.removed)
        assertFalse(transitions.isDisappearing("a", pin))
    }

    @Test
    fun aRemovedMarkerWithoutParentFadesOutInPlace() {
        update(placed = listOf("a" to child))
        val pin = transitions["a"]!!
        update(removed = listOf("a"), transition = animated())
        clock.plays.single().at(0.75f)
        assertFrame(frame(48.0, 12.0, 0.25f), pin.frame)
    }

    @Test
    fun aNewerUpdateStartsFromTheOnScreenStateOfAnInFlightMarker() {
        update(placed = listOf("a" to child), transition = animated(appearFrom = mapOf("a" to parent)))
        val first = clock.plays.single()
        first.at(0.5f)
        val pin = transitions["a"]!!
        update(placed = listOf("a" to frame(49.0, 14.0)), transition = animated())
        assertSame(pin, transitions["a"])
        val second = clock.plays.last()
        second.at(0f)
        assertFrame(frame(47.5, 11.0, 0.5f), pin.frame)
        first.at(0.9f)
        assertFrame(frame(47.5, 11.0, 0.5f), pin.frame)
        second.at(0.5f)
        assertFrame(frame(48.25, 12.5, 0.75f), pin.frame)
        first.end()
        assertFrame(frame(48.25, 12.5, 0.75f), pin.frame)
        second.end()
        assertFrame(frame(49.0, 14.0), pin.frame)
    }

    @Test
    fun aDisappearingMarkerAddedAgainIsRevivedFromItsOnScreenState() {
        update(placed = listOf("a" to child))
        val pin = transitions["a"]!!
        update(removed = listOf("a"), transition = animated(disappearTo = mapOf("a" to parent)))
        val disappearing = clock.plays.single()
        disappearing.at(0.5f)

        update(placed = listOf("a" to child), transition = animated(appearFrom = mapOf("a" to parent)))
        assertSame(pin, transitions["a"])
        assertEquals(1, created.size)
        assertEquals(1, pin.reused)
        assertFalse(transitions.isDisappearing("a", pin))
        clock.plays.last().at(0f)
        assertFrame(frame(47.5, 11.0, 0.5f), pin.frame)

        disappearing.end()
        assertFalse(pin.removed)
        clock.plays.last().end()
        assertFrame(child, pin.frame)
        assertFalse(pin.removed)
    }

    @Test
    fun anInstantUpdateRevivesAndStopsTheAnimation() {
        update(placed = listOf("a" to child))
        val pin = transitions["a"]!!
        update(removed = listOf("a"), transition = animated())
        val disappearing = clock.plays.single()
        disappearing.at(0.5f)
        pin.isVisible = false

        update(placed = listOf("a" to child))
        assertTrue(pin.isVisible)
        assertFrame(child, pin.frame)
        disappearing.at(0.9f)
        disappearing.end()
        assertFrame(child, pin.frame)
        assertFalse(pin.removed)
    }

    @Test
    fun snapshotsHideDisappearingMarkersAndKeepAppearingOnesAtTheirOpacity() {
        update(placed = listOf("gone" to parent))
        val gone = transitions["gone"]!!
        update(
            removed = listOf("gone"),
            placed = listOf("new" to child),
            transition = animated(appearFrom = mapOf("new" to parent)),
        )
        val play = clock.plays.single()
        play.at(0.5f)
        val appearing = transitions["new"]!!

        assertTrue(transitions.beginSnapshot())
        assertFalse(gone.isVisible)
        assertFrame(frame(47.5, 11.0, 0.5f), appearing.frame)
        play.at(0.6f)
        assertEquals(0.6f, appearing.frame.alpha)
        assertFalse(gone.isVisible)

        transitions.endSnapshot()
        assertTrue(gone.isVisible)
        assertFrame(frame(47.6, 11.2, 0.6f), appearing.frame)
    }

    @Test
    fun aMarkerThatStartsDisappearingDuringASnapshotIsHidden() {
        update(placed = listOf("a" to child))
        val pin = transitions["a"]!!
        assertFalse(transitions.beginSnapshot())
        update(removed = listOf("a"), placed = listOf("b" to parent), transition = animated())
        assertFalse(pin.isVisible)
        assertEquals(0f, transitions["b"]!!.frame.alpha)
        transitions.endSnapshot()
        assertTrue(pin.isVisible)
        assertEquals(0f, transitions["b"]!!.frame.alpha)
    }

    @Test
    fun nestedSnapshotsRestoreOnlyAfterTheLast() {
        update(placed = listOf("a" to child))
        val pin = transitions["a"]!!
        update(removed = listOf("a"), transition = animated())
        transitions.beginSnapshot()
        transitions.beginSnapshot()
        transitions.endSnapshot()
        assertFalse(pin.isVisible)
        transitions.endSnapshot()
        assertTrue(pin.isVisible)
    }

    @Test
    fun clearCancelsEveryTransitionAndLeavesTheMarkersToTheMap() {
        update(placed = listOf("a" to child, "b" to child))
        val a = transitions["a"]!!
        update(
            removed = listOf("a"),
            placed = listOf("c" to child),
            transition = animated(appearFrom = mapOf("c" to parent)),
        )
        val frames = created.map { it.frame }
        transitions.clear()
        assertTrue(clock.plays.single().cancelled)
        assertTrue(created.none { it.removed })
        assertEquals(frames, created.map { it.frame })
        assertNull(transitions["b"])
        assertNull(transitions["c"])
        assertFalse(transitions.isDisappearing("a", a))
    }

    @Test
    fun aTransitionThatEndsWhileStartingLeavesNothingRunning() {
        clock.endImmediately = true
        update(placed = listOf("a" to child), transition = animated(appearFrom = mapOf("a" to parent)))
        assertFrame(child, transitions["a"]!!.frame)
        update(removed = listOf("a"), transition = animated())
        assertTrue(created.single().removed)
        transitions.clear()
        assertFalse(clock.plays.any { it.cancelled })
    }

    @Test
    fun aMarkerTheFactoryCannotCreateIsSkipped() {
        transitions.update(
            emptyList(),
            listOf(Placement("a", child, "a")),
            animated(),
            create = { _, _ -> null },
            reuse = { _, _ -> },
        )
        assertNull(transitions["a"])
        assertTrue(clock.plays.isEmpty())
    }
}
