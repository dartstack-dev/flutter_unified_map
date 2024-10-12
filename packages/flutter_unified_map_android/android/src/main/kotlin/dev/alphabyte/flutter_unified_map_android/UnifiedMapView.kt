package dev.alphabyte.flutter_unified_map_android

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import android.view.View
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.GoogleMapOptions
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.OnMapReadyCallback
import com.google.android.gms.maps.model.LatLng
import java.io.ByteArrayOutputStream
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class UnifiedMapView(
    context: Context,
    private val viewId: Long,
    private var options: PMapOptions,
    private val events: EventSink,
    private val onDisposed: (MapInstance) -> Unit,
) : MapInstance, DefaultLifecycleObserver, OnMapReadyCallback {
    override val id: Long get() = viewId

    /** The MapView's own lifecycle, in order; DESTROYED is final. */
    private enum class ViewState { DESTROYED, NEW, CREATED, STARTED, RESUMED }

    private val mapView = MapView(
        context,
        GoogleMapOptions()
            .camera(options.initialCamera.toCameraPosition())
            .backgroundColor(options.backgroundColorArgb.toColorInt())
            .mapToolbarEnabled(false)
            .zoomControlsEnabled(false),
    )
    private val density = Density { mapView.resources.displayMetrics.density }
    private var appliedDensity = density.value

    private var map: GoogleMap? = null
    private var markers: MarkerController? = null
    private var overlays: OverlayController? = null
    private var tiles: TileController? = null
    private var appliedOptions: PMapOptions? = null

    private var lifecycle: Lifecycle? = null
    private var state = ViewState.NEW
    private var disposed = false
    private var readySent = false
    private var sentWidth = 0
    private var sentHeight = 0

    private var moving = false
    private var movingByGesture = false
    private var moveFramePending = false
    private val moveFrame = Choreographer.FrameCallback {
        moveFramePending = false
        val map = map
        if (map != null && !disposed) events.onCameraMove(viewId, map.cameraPosition.toPCamera())
    }

    private val pendingMoves = HashSet<CancellableContinuation<Unit>>()
    private val pendingSnapshots = HashSet<CancellableContinuation<Bitmap?>>()
    private val frames = FrameWatcher(mapView)

    private val handler = Handler(Looper.getMainLooper())
    private val load = LoadWatchdog(
        LOAD_TIMEOUT_MILLIS,
        schedule = { runnable, delay -> handler.postDelayed(runnable, delay) },
        cancel = handler::removeCallbacks,
        onTimeout = { events.onMapError(viewId, PMapErrorCode.LOAD_TIMEOUT, LOAD_TIMEOUT_MESSAGE) },
    )
    private var loadedPending = false
    private val loadedCallback = GoogleMap.OnMapLoadedCallback { onLoaded() }

    private val layoutListener = View.OnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
        onLayout(right - left, bottom - top)
    }

    init {
        mapView.addOnLayoutChangeListener(layoutListener)
    }

    fun start(lifecycle: Lifecycle?) {
        raise(ViewState.CREATED)
        if (lifecycle != null) attachLifecycle(lifecycle) else raise(ViewState.RESUMED)
        mapView.getMapAsync(this)
    }

    /** Called when the plugin gets a (new) activity; observing replays the events up to its current state. */
    override fun attachLifecycle(lifecycle: Lifecycle) {
        if (disposed || state == ViewState.DESTROYED || this.lifecycle === lifecycle) return
        this.lifecycle?.removeObserver(this)
        this.lifecycle = lifecycle
        lifecycle.addObserver(this)
    }

    /**
     * Called before the activity goes away while the engine (and this view) survives it, so that the activity's
     * ON_DESTROY does not destroy a MapView that the next activity will show again.
     */
    override fun detachLifecycle() {
        lifecycle?.removeObserver(this)
        lifecycle = null
    }

    override fun getView(): View = mapView

    override fun dispose() {
        if (disposed) return
        disposed = true
        Choreographer.getInstance().removeFrameCallback(moveFrame)
        mapView.removeOnLayoutChangeListener(layoutListener)
        map?.let { map ->
            map.stopAnimation()
            map.setOnMapLoadedCallback(null)
            map.setOnCameraMoveStartedListener(null)
            map.setOnCameraMoveListener(null)
            map.setOnCameraIdleListener(null)
            map.setOnMapClickListener(null)
            map.setOnMapLongClickListener(null)
            map.setOnMarkerClickListener(null)
        }
        lifecycle?.removeObserver(this)
        lifecycle = null
        lower(ViewState.DESTROYED)
        onDisposed(this)
    }

    override fun onLowMemory() {
        if (!disposed && state >= ViewState.CREATED) mapView.onLowMemory()
    }

    /** Posted: the application hears of a configuration change before the activity's resources are updated. */
    override fun onConfigurationChanged() {
        handler.post(::applyDensity)
    }

    private fun applyDensity() {
        if (disposed || state == ViewState.DESTROYED || density.value == appliedDensity) return
        appliedDensity = density.value
        map?.let(::applyPadding)
        overlays?.onDensityChanged()
        tiles?.onDensityChanged()
    }

    override fun onCreate(owner: LifecycleOwner) = raise(ViewState.CREATED)

    override fun onStart(owner: LifecycleOwner) = raise(ViewState.STARTED)

    override fun onResume(owner: LifecycleOwner) = raise(ViewState.RESUMED)

    override fun onPause(owner: LifecycleOwner) = lower(ViewState.STARTED)

    override fun onStop(owner: LifecycleOwner) = lower(ViewState.CREATED)

    /**
     * FlutterActivity detaches the plugin before it dispatches ON_DESTROY, but a FlutterFragment dispatches it first,
     * while the engine and this view may live on. The MapView is destroyed with the view, in [dispose].
     */
    override fun onDestroy(owner: LifecycleOwner) {
        owner.lifecycle.removeObserver(this)
        if (lifecycle === owner.lifecycle) lifecycle = null
        lower(ViewState.CREATED)
    }

    private fun raise(target: ViewState) {
        while (!disposed && state != ViewState.DESTROYED && state < target) {
            state = when (state) {
                ViewState.NEW -> ViewState.CREATED.also { mapView.onCreate(null) }
                ViewState.CREATED -> ViewState.STARTED.also { mapView.onStart() }
                else -> ViewState.RESUMED.also { mapView.onResume() }
            }
        }
        updateLoadWatchdog()
    }

    private fun lower(target: ViewState) {
        while (state > target) {
            state = when (state) {
                ViewState.RESUMED -> ViewState.STARTED.also { mapView.onPause() }
                ViewState.STARTED -> ViewState.CREATED.also { mapView.onStop() }
                ViewState.CREATED -> ViewState.DESTROYED.also { destroyMapView() }
                else -> ViewState.DESTROYED
            }
        }
        updateLoadWatchdog()
    }

    private fun destroyMapView() {
        load.stop()
        Choreographer.getInstance().removeFrameCallback(moveFrame)
        moveFramePending = false
        pendingMoves.toList().forEach { if (it.isActive) it.resume(Unit) }
        pendingMoves.clear()
        pendingSnapshots.toList().forEach { if (it.isActive) it.resume(null) }
        pendingSnapshots.clear()
        frames.release()
        // MapView.onDestroy frees every marker, overlay and tile layer at once.
        markers?.clear()
        map = null
        markers = null
        overlays = null
        tiles = null
        mapView.onDestroy()
    }

    private fun updateLoadWatchdog() {
        load.canLoad(!disposed && state == ViewState.RESUMED && mapView.width > 0 && mapView.height > 0)
    }

    override fun onMapReady(googleMap: GoogleMap) {
        if (disposed || state == ViewState.DESTROYED) return
        map = googleMap
        markers = MarkerController(googleMap, density)
        overlays = OverlayController(googleMap, density)
        tiles = TileController(googleMap, density) { applyMapType() }
        applyOptions()
        frames.install()
        googleMap.setOnMapLoadedCallback(loadedCallback)
        maybeSendReady()
    }

    private fun onLoaded() {
        if (disposed || state == ViewState.DESTROYED || !load.onLoaded()) return
        if (readySent) events.onMapLoaded(viewId) else loadedPending = true
    }

    private fun installListeners(map: GoogleMap) {
        map.setOnCameraMoveStartedListener { reason ->
            val byGesture = reason == GoogleMap.OnCameraMoveStartedListener.REASON_GESTURE
            // One start per movement, as on MapKit: a gesture that takes over a programmatic move continues it.
            if (moving) {
                movingByGesture = movingByGesture || byGesture
                return@setOnCameraMoveStartedListener
            }
            moving = true
            movingByGesture = byGesture
            events.onCameraMoveStarted(viewId, byGesture)
        }
        map.setOnCameraMoveListener {
            if (moveFramePending) return@setOnCameraMoveListener
            moveFramePending = true
            Choreographer.getInstance().postFrameCallback(moveFrame)
        }
        map.setOnCameraIdleListener {
            if (moveFramePending) {
                moveFramePending = false
                Choreographer.getInstance().removeFrameCallback(moveFrame)
                events.onCameraMove(viewId, map.cameraPosition.toPCamera())
            }
            moving = false
            movingByGesture = false
            events.onCameraIdle(viewId, map.cameraPosition.toPCamera())
            // The SDK calls a loaded callback only once; while in error, a new camera may load and clear it.
            if (load.failed) map.setOnMapLoadedCallback(loadedCallback)
        }
        map.setOnMapClickListener { sendTap(map, it, longPress = false) }
        map.setOnMapLongClickListener { sendTap(map, it, longPress = true) }
        map.setOnMarkerClickListener { marker ->
            val markers = markers
            val markerId = (marker.tag as? String)?.takeIf {
                markers != null && markers.isTappable(it) && !markers.isDisappearing(marker)
            }
            if (markerId != null) events.onMarkerTap(viewId, markerId) else sendTap(map, marker.position, longPress = false)
            true
        }
    }

    private fun sendTap(map: GoogleMap, position: LatLng, longPress: Boolean) {
        val point = density.toPPoint(map.projection.toScreenLocation(position))
        if (longPress) events.onLongPress(viewId, position.toPLatLng(), point)
        else events.onTap(viewId, position.toPLatLng(), point)
    }

    private fun onLayout(width: Int, height: Int) {
        if (disposed || width <= 0 || height <= 0) return
        applyDensity()
        updateLoadWatchdog()
        if (!readySent) {
            maybeSendReady()
            return
        }
        if (width == sentWidth && height == sentHeight) return
        sentWidth = width
        sentHeight = height
        events.onViewSize(viewId, size())
    }

    private fun maybeSendReady() {
        val map = map ?: return
        if (readySent || disposed || mapView.width <= 0 || mapView.height <= 0) return
        readySent = true
        sentWidth = mapView.width
        sentHeight = mapView.height
        events.onMapReady(viewId, map.cameraPosition.toPCamera(), size())
        // Installed only now so that no camera or tap event can reach Dart before the ready event.
        installListeners(map)
        if (loadedPending) {
            loadedPending = false
            events.onMapLoaded(viewId)
        }
    }

    private fun size(): PSize = PSize(density.logical(mapView.width), density.logical(mapView.height))

    override fun updateOptions(options: PMapOptions) {
        this.options = options
        applyOptions()
    }

    /** Sets only what changed: a padding that follows a draggable panel must not reload the style on every frame. */
    private fun applyOptions() {
        val map = map ?: return
        val previous = appliedOptions
        appliedOptions = options
        if (previous == null || previous.style != options.style || previous.showsPointsOfInterest != options.showsPointsOfInterest) {
            applyMapType()
            map.setMapStyle(MapStyles.styleOptions(options.style, options.showsPointsOfInterest))
        }
        if (previous == null || previous.interaction != options.interaction || previous.showsCompass != options.showsCompass) {
            map.uiSettings.apply {
                isScrollGesturesEnabled = options.interaction.scrollEnabled
                isZoomGesturesEnabled = options.interaction.zoomEnabled
                isRotateGesturesEnabled = options.interaction.rotateEnabled
                isTiltGesturesEnabled = options.interaction.tiltEnabled
                isCompassEnabled = options.showsCompass
                isMyLocationButtonEnabled = false
                isZoomControlsEnabled = false
                isMapToolbarEnabled = false
                isIndoorLevelPickerEnabled = false
            }
        }
        if (previous == null) map.isIndoorEnabled = false
        if (previous?.showsBuildings != options.showsBuildings) map.isBuildingsEnabled = options.showsBuildings
        if (previous?.showsTraffic != options.showsTraffic) map.isTrafficEnabled = options.showsTraffic
        if (previous == null || previous.minZoom != options.minZoom || previous.maxZoom != options.maxZoom) {
            map.resetMinMaxZoomPreference()
            map.setMinZoomPreference(options.minZoom.toFloat())
            map.setMaxZoomPreference(options.maxZoom.toFloat())
        }
        if (previous?.padding != options.padding) applyPadding(map)
        if (previous?.showsUserLocation != options.showsUserLocation) {
            try {
                map.isMyLocationEnabled = options.showsUserLocation
            } catch (e: SecurityException) {
                Log.w(TAG, "showsUserLocation needs ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION", e)
            }
        }
    }

    private fun applyPadding(map: GoogleMap) {
        map.setPadding(
            density.pxInt(options.padding.left),
            density.pxInt(options.padding.top),
            density.pxInt(options.padding.right),
            density.pxInt(options.padding.bottom),
        )
    }

    private fun applyMapType() {
        val map = map ?: return
        val replaced = tiles?.replacesBaseMap == true
        map.mapType = if (replaced) GoogleMap.MAP_TYPE_NONE else MapStyles.mapType(options.style)
    }

    override fun registerIcons(icons: List<PIcon>) {
        if (!disposed) markers?.registerIcons(icons)
    }

    override fun updateMarkers(
        added: List<PMarker>,
        changed: List<PMarker>,
        removedIds: List<String>,
        transition: PMarkerTransition?,
    ) {
        val markers = markers ?: return
        markers.update(added, changed, removedIds, transition)
        frames.markChanged()
    }

    override fun updatePolylines(added: List<PPolyline>, changed: List<PPolyline>, removedIds: List<String>) {
        overlays?.updatePolylines(added, changed, removedIds)
    }

    override fun updatePolygons(added: List<PPolygon>, changed: List<PPolygon>, removedIds: List<String>) {
        overlays?.updatePolygons(added, changed, removedIds)
    }

    override fun updateCircles(added: List<PCircle>, changed: List<PCircle>, removedIds: List<String>) {
        overlays?.updateCircles(added, changed, removedIds)
    }

    override fun updateTileLayers(added: List<PTileLayer>, changed: List<PTileLayer>, removedIds: List<String>) {
        tiles?.update(added, changed, removedIds)
    }

    override suspend fun moveCamera(update: PCameraUpdate, animationMillis: Long?) {
        val map = map ?: return
        val cameraUpdate = CameraUpdates.build(map, update, density, mapView.width, mapView.height, options)
        if (animationMillis == null || animationMillis <= 0) {
            map.moveCamera(cameraUpdate)
            return
        }
        suspendCancellableCoroutine { continuation ->
            pendingMoves.add(continuation)
            continuation.invokeOnCancellation { pendingMoves.remove(continuation) }
            val finish = {
                pendingMoves.remove(continuation)
                if (continuation.isActive) continuation.resume(Unit)
            }
            map.animateCamera(
                cameraUpdate,
                animationMillis.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                object : GoogleMap.CancelableCallback {
                    override fun onFinish() = finish()

                    override fun onCancel() = finish()
                },
            )
        }
    }

    override fun camera(): PCamera = readyMap().cameraPosition.toPCamera()

    override fun visibleRegion(): PLatLngBounds = readyMap().projection.visibleRegion.latLngBounds.toPLatLngBounds()

    override fun toScreen(position: PLatLng): PPoint =
        density.toPPoint(readyMap().projection.toScreenLocation(position.toLatLng()))

    override fun toLatLng(screenPoint: PPoint): PLatLng =
        readyMap().projection.fromScreenLocation(density.toPoint(screenPoint)).toPLatLng()

    override suspend fun takeSnapshot(): ByteArray? {
        val map = map ?: return null
        val markers = markers ?: return null
        val bitmap = try {
            if (markers.beginSnapshot()) frames.markChanged()
            frames.awaitChangeRendered()
            if (disposed || state == ViewState.DESTROYED) return null
            // Google may never call back for a MapView that does not render (paused, stopped).
            withTimeoutOrNull(SNAPSHOT_TIMEOUT_MILLIS) {
                suspendCancellableCoroutine<Bitmap?> { continuation ->
                    pendingSnapshots.add(continuation)
                    continuation.invokeOnCancellation { pendingSnapshots.remove(continuation) }
                    map.snapshot { snapshot ->
                        pendingSnapshots.remove(continuation)
                        if (continuation.isActive) continuation.resume(snapshot)
                    }
                }
            }
        } finally {
            if (!disposed) markers.endSnapshot()
        } ?: return null
        return withContext(Dispatchers.Default) {
            ByteArrayOutputStream().use { stream ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                stream.toByteArray()
            }
        }
    }

    private fun readyMap(): GoogleMap {
        if (disposed) throw FlutterError("disposed", "Map view $viewId is disposed", null)
        if (state == ViewState.DESTROYED) {
            throw FlutterError("destroyed", "The activity destroyed the MapView of map view $viewId", null)
        }
        val map = map
        if (map == null || !readySent) throw FlutterError("not-ready", "Map view $viewId is not ready", null)
        return map
    }

    companion object {
        const val LOAD_TIMEOUT_MILLIS = 15_000L
        const val SNAPSHOT_TIMEOUT_MILLIS = 5_000L
        val LOAD_TIMEOUT_MESSAGE = "Google Maps did not finish loading within ${LOAD_TIMEOUT_MILLIS / 1000} s " +
            "of being visible. Logcat usually shows 'Authorization failure' for a rejected key."
    }
}
