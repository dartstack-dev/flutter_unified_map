package dev.alphabyte.flutter_unified_map_android

import kotlin.test.Test
import kotlin.test.assertEquals

class CameraUpdatesTest {
    private val current = PCamera(PLatLng(48.8, 2.3), 10.0, 45.0, 30.0)

    @Test
    fun newCameraKeepsTheFieldsItLeavesNull() {
        assertEquals(current.copy(zoom = 12.0), CameraUpdates.merge(current, PNewCamera(zoom = 12.0)))
        assertEquals(
            PCamera(PLatLng(1.0, 2.0), 10.0, 0.0, 30.0),
            CameraUpdates.merge(current, PNewCamera(center = PLatLng(1.0, 2.0), bearing = 0.0)),
        )
        assertEquals(current, CameraUpdates.merge(current, PNewCamera()))
    }
}
