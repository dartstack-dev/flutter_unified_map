package dev.alphabyte.flutter_unified_map_android

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class EventSink(private val api: UnifiedMapsFlutterApi) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun onMapReady(viewId: Long, camera: PCamera, size: PSize) = send { api.onMapReady(viewId, camera, size) }

    fun onCameraMoveStarted(viewId: Long, byGesture: Boolean) = send { api.onCameraMoveStarted(viewId, byGesture) }

    fun onCameraMove(viewId: Long, camera: PCamera) = send { api.onCameraMove(viewId, camera) }

    fun onCameraIdle(viewId: Long, camera: PCamera) = send { api.onCameraIdle(viewId, camera) }

    fun onTap(viewId: Long, position: PLatLng, screenPoint: PPoint) = send { api.onTap(viewId, position, screenPoint) }

    fun onLongPress(viewId: Long, position: PLatLng, screenPoint: PPoint) =
        send { api.onLongPress(viewId, position, screenPoint) }

    fun onMarkerTap(viewId: Long, markerId: String) = send { api.onMarkerTap(viewId, markerId) }

    fun onViewSize(viewId: Long, size: PSize) = send { api.onViewSize(viewId, size) }

    fun onMapLoaded(viewId: Long) = send { api.onMapLoaded(viewId) }

    fun onMapError(viewId: Long, code: PMapErrorCode, message: String) = send { api.onMapError(viewId, code, message) }

    fun close() = scope.cancel()

    private fun send(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
            } catch (e: FlutterError) {
                Log.w(TAG, "event dropped: ${e.message}")
            }
        }
    }
}
