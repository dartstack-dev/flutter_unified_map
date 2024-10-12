package dev.alphabyte.flutter_unified_map_android

/** A marker's on-screen state: position and opacity. */
data class MarkerFrame(val latitude: Double, val longitude: Double, val alpha: Float) {
    fun withAlpha(alpha: Float) = MarkerFrame(latitude, longitude, alpha)

    companion object {
        /** Longitudes take the short way across the antimeridian; the result stays within [-180, 180). */
        fun lerp(from: MarkerFrame, to: MarkerFrame, fraction: Float): MarkerFrame {
            val t = fraction.toDouble()
            val latitude = from.latitude + (to.latitude - from.latitude) * t
            val longitude = wrapLongitude(from.longitude + longitudeDelta(from.longitude, to.longitude) * t)
            val alpha = (from.alpha + (to.alpha - from.alpha) * fraction).coerceIn(0f, 1f)
            return MarkerFrame(latitude, longitude, alpha)
        }

        fun longitudeDelta(from: Double, to: Double): Double = wrapLongitude(to - from)

        fun wrapLongitude(value: Double): Double = ((value + 180.0) % 360.0 + 360.0) % 360.0 - 180.0
    }
}

/** Where an update takes a marker; null when it does not need to move or fade. */
object MarkerPlans {
    fun appear(target: MarkerFrame, appearFrom: MarkerFrame?): Pair<MarkerFrame, MarkerFrame> {
        val to = target.withAlpha(1f)
        return (appearFrom ?: to).withAlpha(0f) to to
    }

    fun move(current: MarkerFrame, target: MarkerFrame): Pair<MarkerFrame, MarkerFrame>? {
        val to = target.withAlpha(1f)
        return if (current == to) null else current to to
    }

    fun disappear(current: MarkerFrame, disappearTo: MarkerFrame?): Pair<MarkerFrame, MarkerFrame> =
        current to (disappearTo ?: current).withAlpha(0f)
}

class MarkerFlight<M>(
    val id: String,
    val target: M,
    val from: MarkerFrame,
    val to: MarkerFrame,
    val removeAtEnd: Boolean,
) {
    fun frameAt(fraction: Float): MarkerFrame = MarkerFrame.lerp(from, to, fraction)
}

/** The markers one transition animates. A marker leaves its batch when a newer update takes it over. */
class FlightBatch<M> internal constructor() {
    internal val flights = LinkedHashMap<String, MarkerFlight<M>>()

    /** The eased fraction of the last frame shown. */
    var fraction: Float = 0f
        internal set

    val isEmpty: Boolean get() = flights.isEmpty()

    val all: Collection<MarkerFlight<M>> get() = flights.values
}

/** Which marker is in flight in which batch, for one map view. */
class FlightRegistry<M> {
    private val batchOf = HashMap<String, FlightBatch<M>>()

    fun add(batch: FlightBatch<M>, flight: MarkerFlight<M>) {
        detach(flight.id)
        batch.flights[flight.id] = flight
        batchOf[flight.id] = batch
    }

    fun detach(id: String): MarkerFlight<M>? {
        val batch = batchOf.remove(id) ?: return null
        return batch.flights.remove(id)
    }

    operator fun get(id: String): MarkerFlight<M>? = batchOf[id]?.flights?.get(id)

    /** Compares with `==`: Google Maps hands listeners a new [com.google.android.gms.maps.model.Marker] wrapper. */
    fun isDisappearing(id: String, target: M): Boolean = get(id)?.let { it.removeAtEnd && it.target == target } == true

    /** Where the marker is on screen while in flight. */
    fun currentFrame(id: String): MarkerFrame? = batchOf[id]?.let { batch -> batch.flights[id]?.frameAt(batch.fraction) }

    val batches: Set<FlightBatch<M>> get() = batchOf.values.toSet()

    /** Ends [batch]: returns the flights still in it, which must now be put in their final state. */
    fun finish(batch: FlightBatch<M>): List<MarkerFlight<M>> {
        batch.fraction = 1f
        val remaining = batch.flights.values.toList()
        batch.flights.clear()
        for (flight in remaining) if (batchOf[flight.id] === batch) batchOf.remove(flight.id)
        return remaining
    }

    fun clear() {
        batchOf.values.forEach { it.flights.clear() }
        batchOf.clear()
    }
}
