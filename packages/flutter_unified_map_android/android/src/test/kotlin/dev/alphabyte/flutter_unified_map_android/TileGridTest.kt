package dev.alphabyte.flutter_unified_map_android

import kotlin.test.Test
import kotlin.test.assertEquals

class TileGridTest {
    @Test
    fun onlyPowerOfTwoMultiplesOf256AreShifted() {
        assertEquals(0, TileGrid.levelsAbove256(256))
        assertEquals(0, TileGrid.levelsAbove256(128))
        assertEquals(0, TileGrid.levelsAbove256(768))
        assertEquals(1, TileGrid.levelsAbove256(512))
        assertEquals(2, TileGrid.levelsAbove256(1024))
    }

    @Test
    fun a512TileCoversFourCellsOneZoomBelow() {
        assertEquals(TileGrid.Source(x = 3, y = 5, zoom = 9, column = 0, row = 1, divisions = 2), TileGrid.source(6, 11, 10, 1))
        assertEquals(TileGrid.Source(x = 3, y = 5, zoom = 9, column = 1, row = 0, divisions = 2), TileGrid.source(7, 10, 10, 1))
    }

    @Test
    fun unshiftedTilesAreUsedWhole() {
        assertEquals(TileGrid.Source(x = 6, y = 11, zoom = 10, column = 0, row = 0, divisions = 1), TileGrid.source(6, 11, 10, 0))
    }

    @Test
    fun lowZoomsCropTheWorldTile() {
        assertEquals(TileGrid.Source(x = 0, y = 0, zoom = 0, column = 0, row = 0, divisions = 1), TileGrid.source(0, 0, 0, 1))
        assertEquals(TileGrid.Source(x = 0, y = 0, zoom = 0, column = 1, row = 1, divisions = 2), TileGrid.source(1, 1, 1, 2))
    }
}
