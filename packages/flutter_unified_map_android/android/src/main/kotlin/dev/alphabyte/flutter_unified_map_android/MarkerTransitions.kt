package dev.alphabyte.flutter_unified_map_android

/** A native marker as [MarkerTransitions] drives it. */
interface MarkerHandle {
    var frame: MarkerFrame
    var isVisible: Boolean

    /** Lets live markers win the hit test over a marker that is going away. */
    fun sendToBack()

    fun remove()
}

/** Plays one transition: [onFrame] gets the eased fraction, [onEnd] runs once, at the end or on cancel. */
fun interface TransitionClock {
    fun play(durationMillis: Long, onFrame: (Float) -> Unit, onEnd: () -> Unit): Playback
}

fun interface Playback {
    fun cancel()
}

class MarkerTransition(
    val durationMillis: Long,
    val appearFrom: Map<String, MarkerFrame> = emptyMap(),
    val disappearTo: Map<String, MarkerFrame> = emptyMap(),
)

class Placement<T>(val id: String, val frame: MarkerFrame, val payload: T)

/**
 * The live markers of one map view and their transitions. Disappearing markers are not live: they stay in the
 * [FlightRegistry] until their batch ends.
 */
class MarkerTransitions<M : MarkerHandle>(private val clock: TransitionClock) {
    private val live = HashMap<String, M>()
    private val flights = FlightRegistry<M>()
    private val playbacks = HashSet<Playback>()
    private var snapshots = 0

    internal operator fun get(id: String): M? = live[id]

    /**
     * Removes [removedIds], then places [targets] in order: [create] makes a missing marker at its start frame,
     * [reuse] updates the other properties of an existing one.
     */
    fun <T> update(
        removedIds: List<String>,
        targets: List<Placement<T>>,
        transition: MarkerTransition?,
        create: (T, MarkerFrame) -> M?,
        reuse: (T, M) -> Unit,
    ) {
        val animation = transition?.takeIf { it.durationMillis > 0 }
        val batch = FlightBatch<M>()
        for (id in removedIds) {
            val handle = live.remove(id) ?: continue
            val current = currentFrame(id, handle)
            flights.detach(id)
            if (animation == null) {
                handle.remove()
                continue
            }
            handle.sendToBack()
            val (from, to) = MarkerPlans.disappear(current, animation.disappearTo[id])
            flights.add(batch, MarkerFlight(id, handle, from, to, removeAtEnd = true))
            if (snapshots > 0) handle.isVisible = false
        }
        for (placement in targets) {
            val id = placement.id
            val existing = live[id] ?: revive(id)
            if (existing == null) {
                if (animation == null) {
                    create(placement.payload, placement.frame.withAlpha(1f))?.let { live[id] = it }
                    continue
                }
                val (from, to) = MarkerPlans.appear(placement.frame, animation.appearFrom[id])
                val handle = create(placement.payload, from) ?: continue
                live[id] = handle
                val flight = MarkerFlight(id, handle, from, to, removeAtEnd = false)
                flights.add(batch, flight)
                continue
            }
            val current = currentFrame(id, existing)
            flights.detach(id)
            reuse(placement.payload, existing)
            val move = animation?.let { MarkerPlans.move(current, placement.frame) }
            if (move == null) {
                existing.frame = placement.frame.withAlpha(1f)
            } else {
                val flight = MarkerFlight(id, existing, move.first, move.second, removeAtEnd = false)
                flights.add(batch, flight)
                existing.frame = move.first
            }
        }
        if (animation != null && !batch.isEmpty) play(batch, animation.durationMillis)
    }

    private fun currentFrame(id: String, handle: M): MarkerFrame = flights.currentFrame(id) ?: handle.frame

    private fun revive(id: String): M? {
        val flight = flights[id]?.takeIf { it.removeAtEnd } ?: return null
        flight.target.isVisible = true
        live[id] = flight.target
        return flight.target
    }

    private fun play(batch: FlightBatch<M>, durationMillis: Long) {
        var playback: Playback? = null
        var ended = false
        val started = clock.play(
            durationMillis,
            onFrame = { fraction ->
                batch.fraction = fraction
                for (flight in batch.all) flight.target.frame = flight.frameAt(fraction)
            },
            onEnd = {
                ended = true
                playback?.let(playbacks::remove)
                for (flight in flights.finish(batch)) {
                    if (flight.removeAtEnd) flight.target.remove() else flight.target.frame = flight.to
                }
            },
        )
        playback = started
        if (!ended) playbacks.add(started)
    }

    fun isDisappearing(id: String, handle: M): Boolean = flights.isDisappearing(id, handle)

    /**
     * Hides disappearing markers until [endSnapshot] (the other in-flight markers keep their current opacity, as on
     * MapKit and flutter_map); returns whether that changed anything.
     */
    fun beginSnapshot(): Boolean {
        snapshots++
        var changed = false
        for (batch in flights.batches) {
            for (flight in batch.all) {
                if (!flight.removeAtEnd) continue
                if (flight.target.isVisible) changed = true
                flight.target.isVisible = false
            }
        }
        return changed
    }

    fun endSnapshot() {
        if (snapshots == 0 || --snapshots > 0) return
        for (batch in flights.batches) {
            for (flight in batch.all) if (flight.removeAtEnd) flight.target.isVisible = true
        }
    }

    /** Stops every transition and forgets every marker without touching it: the map that holds them is going away. */
    fun clear() {
        flights.clear()
        playbacks.toList().forEach { it.cancel() }
        playbacks.clear()
        snapshots = 0
        live.clear()
    }
}
