package dev.alphabyte.flutter_unified_map_android

import kotlin.test.Test
import kotlin.test.assertEquals

class TileUrlTemplateTest {
    private fun layer(template: String, subdomains: List<String> = listOf("a", "b", "c")) = PTileLayer(
        id = "t",
        urlTemplate = template,
        subdomains = subdomains,
        minZoom = 0.0,
        maxZoom = 19.0,
        tileSize = 512,
        headers = emptyMap(),
        replacesBaseMap = false,
        opacity = 1.0,
        zIndex = 0.0,
    )

    @Test
    fun aTileAlwaysGetsTheSameUrl() {
        val template = TileUrlTemplate(layer("https://{s}.tile.example/{z}/{x}/{y}.png"), retina = false)
        val first = template.url(3, 5, 4).toString()
        repeat(5) { assertEquals(first, template.url(3, 5, 4).toString()) }
        assertEquals("https://c.tile.example/4/3/5.png", first)
        assertEquals("https://a.tile.example/4/1/2.png", template.url(1, 2, 4).toString())
        assertEquals("https://b.tile.example/4/2/2.png", template.url(2, 2, 4).toString())
    }

    @Test
    fun retinaSuffixWithoutSubdomains() {
        val template = TileUrlTemplate(layer("https://tile.example/{z}/{x}/{y}{r}.png", emptyList()), retina = true)
        assertEquals("https://tile.example/1/0/1@2x.png", template.url(0, 1, 1).toString())
    }

    @Test
    fun levelsPastMaxZoomAreScaledUpFromTheLastNativeLevel() {
        val template = TileUrlTemplate(layer("https://tile.example/{z}/{x}/{y}.png"), retina = false)
        assertEquals(true, template.covers(21))
        assertEquals(0, template.levelsAboveMaxZoom(19))
        assertEquals(2, template.levelsAboveMaxZoom(21))
        val source = TileGrid.source(1001, 2002, 21, 1 + template.levelsAboveMaxZoom(21))
        assertEquals(TileGrid.Source(x = 125, y = 250, zoom = 18, column = 1, row = 2, divisions = 8), source)
    }
}
