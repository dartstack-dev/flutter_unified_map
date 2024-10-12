package dev.alphabyte.flutter_unified_map_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class MarkerFlightsTest {
    private class Pin(val name: String)

    private fun frame(latitude: Double, longitude: Double, alpha: Float = 1f) = MarkerFrame(latitude, longitude, alpha)

    private fun assertFrame(expected: MarkerFrame, actual: MarkerFrame) {
        assertEquals(expected.latitude, actual.latitude, 1e-9)
        assertEquals(expected.longitude, actual.longitude, 1e-9)
        assertEquals(expected.alpha, actual.alpha, 1e-6f)
    }

    @Test
    fun lerpMovesPositionAndAlphaLinearly() {
        val from = frame(48.0, 2.0, 0f)
        val to = frame(50.0, 12.0, 1f)
        assertFrame(from, MarkerFrame.lerp(from, to, 0f))
        assertFrame(frame(49.0, 7.0, 0.5f), MarkerFrame.lerp(from, to, 0.5f))
        assertFrame(to, MarkerFrame.lerp(from, to, 1f))
    }

    @Test
    fun lerpCrossesTheAntimeridianTheShortWay() {
        val from = frame(0.0, 170.0)
        val to = frame(0.0, -170.0)
        assertFrame(frame(0.0, 175.0), MarkerFrame.lerp(from, to, 0.25f))
        assertFrame(frame(0.0, -180.0), MarkerFrame.lerp(from, to, 0.5f))
        assertFrame(frame(0.0, -175.0), MarkerFrame.lerp(from, to, 0.75f))
        assertFrame(frame(0.0, 175.0), MarkerFrame.lerp(to, from, 0.75f))
    }

    @Test
    fun longitudesWrapIntoTheHalfOpenRange() {
        assertEquals(-180.0, MarkerFrame.wrapLongitude(180.0), 1e-9)
        assertEquals(-170.0, MarkerFrame.wrapLongitude(190.0), 1e-9)
        assertEquals(170.0, MarkerFrame.wrapLongitude(-190.0), 1e-9)
        assertEquals(20.0, MarkerFrame.longitudeDelta(170.0, -170.0), 1e-9)
        assertEquals(-20.0, MarkerFrame.longitudeDelta(-170.0, 170.0), 1e-9)
    }

    @Test
    fun alphaOvershootIsClamped() {
        assertEquals(1f, MarkerFrame.lerp(frame(0.0, 0.0, 0f), frame(0.0, 0.0, 1f), 1.2f).alpha)
        assertEquals(0f, MarkerFrame.lerp(frame(0.0, 0.0, 0f), frame(0.0, 0.0, 1f), -0.2f).alpha)
    }

    @Test
    fun appearSlidesFromTheParentOrFadesInPlace() {
        val target = frame(48.0, 11.0)
        val parent = frame(47.0, 10.0)
        assertEquals(frame(47.0, 10.0, 0f) to frame(48.0, 11.0, 1f), MarkerPlans.appear(target, parent))
        assertEquals(frame(48.0, 11.0, 0f) to frame(48.0, 11.0, 1f), MarkerPlans.appear(target, null))
    }

    @Test
    fun moveGlidesOnlyWhenSomethingChanges() {
        assertNull(MarkerPlans.move(frame(48.0, 11.0), frame(48.0, 11.0)))
        assertEquals(frame(48.0, 11.0) to frame(49.0, 11.0), MarkerPlans.move(frame(48.0, 11.0), frame(49.0, 11.0)))
        val fading = frame(48.0, 11.0, 0.3f)
        assertEquals(fading to frame(48.0, 11.0, 1f), MarkerPlans.move(fading, frame(48.0, 11.0)))
    }

    @Test
    fun disappearSlidesIntoTheParentOrFadesInPlace() {
        val current = frame(48.0, 11.0, 0.8f)
        assertEquals(current to frame(47.0, 10.0, 0f), MarkerPlans.disappear(current, frame(47.0, 10.0)))
        assertEquals(current to frame(48.0, 11.0, 0f), MarkerPlans.disappear(current, null))
    }

    @Test
    fun aNewerBatchTakesAMarkerOverFromItsBatch() {
        val registry = FlightRegistry<Pin>()
        val a = Pin("a")
        val b = Pin("b")
        val first = FlightBatch<Pin>()
        registry.add(first, MarkerFlight("a", a, frame(0.0, 0.0, 0f), frame(1.0, 1.0), removeAtEnd = false))
        registry.add(first, MarkerFlight("b", b, frame(0.0, 0.0, 0f), frame(2.0, 2.0), removeAtEnd = false))

        val second = FlightBatch<Pin>()
        registry.add(second, MarkerFlight("a", a, frame(0.5, 0.5, 0.5f), frame(3.0, 3.0), removeAtEnd = false))

        assertEquals(listOf("b"), first.all.map { it.id })
        assertEquals(listOf("a"), second.all.map { it.id })
        assertEquals(frame(3.0, 3.0), registry["a"]!!.to)

        assertEquals(listOf("b"), registry.finish(first).map { it.id })
        assertNull(registry["b"])
        assertSame(a, registry["a"]!!.target)
        assertEquals(listOf("a"), registry.finish(second).map { it.id })
        assertNull(registry["a"])
    }

    @Test
    fun finishingAnOldBatchLeavesTakenOverMarkersAlone() {
        val registry = FlightRegistry<Pin>()
        val a = Pin("a")
        val first = FlightBatch<Pin>()
        registry.add(first, MarkerFlight("a", a, frame(0.0, 0.0), frame(1.0, 1.0, 0f), removeAtEnd = true))
        val revived = registry.detach("a")!!
        assertTrue(revived.removeAtEnd)
        assertTrue(first.isEmpty)
        assertTrue(registry.finish(first).isEmpty())

        val second = FlightBatch<Pin>()
        registry.add(second, MarkerFlight("a", a, frame(0.5, 0.5, 0.5f), frame(0.0, 0.0), removeAtEnd = false))
        assertTrue(registry.finish(first).isEmpty())
        assertEquals(listOf("a"), second.all.map { it.id })
    }

    @Test
    fun disappearingIsTrackedPerNativeMarker() {
        val registry = FlightRegistry<Pin>()
        val old = Pin("old")
        val fresh = Pin("fresh")
        val batch = FlightBatch<Pin>()
        registry.add(batch, MarkerFlight("a", old, frame(0.0, 0.0), frame(0.0, 0.0, 0f), removeAtEnd = true))
        registry.add(batch, MarkerFlight("b", fresh, frame(0.0, 0.0, 0f), frame(0.0, 0.0), removeAtEnd = false))

        assertTrue(registry.isDisappearing("a", old))
        assertFalse(registry.isDisappearing("a", fresh))
        assertFalse(registry.isDisappearing("b", fresh))
        assertFalse(registry.isDisappearing("c", old))

        registry.detach("a")
        assertFalse(registry.isDisappearing("a", old))
    }

    @Test
    fun currentFrameFollowsTheBatchFraction() {
        val registry = FlightRegistry<Pin>()
        val batch = FlightBatch<Pin>()
        registry.add(batch, MarkerFlight("a", Pin("a"), frame(0.0, 0.0, 0f), frame(2.0, 4.0), removeAtEnd = false))
        assertFrame(frame(0.0, 0.0, 0f), registry.currentFrame("a")!!)
        batch.fraction = 0.5f
        assertFrame(frame(1.0, 2.0, 0.5f), registry.currentFrame("a")!!)
        assertEquals(setOf(batch), registry.batches)
        registry.finish(batch)
        assertNull(registry.currentFrame("a"))
        assertTrue(registry.batches.isEmpty())
    }

    @Test
    fun clearEmptiesTheBatches() {
        val registry = FlightRegistry<Pin>()
        val first = FlightBatch<Pin>()
        val second = FlightBatch<Pin>()
        registry.add(first, MarkerFlight("a", Pin("a"), frame(0.0, 0.0), frame(1.0, 1.0, 0f), removeAtEnd = true))
        registry.add(second, MarkerFlight("b", Pin("b"), frame(0.0, 0.0, 0f), frame(1.0, 1.0), removeAtEnd = false))

        registry.clear()
        assertTrue(first.isEmpty)
        assertTrue(second.isEmpty)
        assertTrue(registry.finish(first).isEmpty())
        assertNull(registry["a"])
    }

    @Test
    fun flightFrameAtFollowsLerp() {
        val flight = MarkerFlight("a", Pin("a"), frame(0.0, 179.0, 1f), frame(0.0, -179.0, 0f), removeAtEnd = true)
        assertFrame(frame(0.0, -180.0, 0.5f), flight.frameAt(0.5f))
        assertFrame(frame(0.0, -179.0, 0f), flight.frameAt(1f))
    }
}
