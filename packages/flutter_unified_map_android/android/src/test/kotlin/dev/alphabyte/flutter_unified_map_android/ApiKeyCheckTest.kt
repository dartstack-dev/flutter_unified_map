package dev.alphabyte.flutter_unified_map_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ApiKeyCheckTest {
    private fun find(vararg entries: Pair<String, Any?>): String? {
        val metaData = mapOf(*entries)
        return ApiKeyCheck.find { metaData[it] }
    }

    @Test
    fun noMetaDataMeansNoKey() {
        assertNull(find())
        assertNull(find("flutterEmbedding" to 2))
    }

    @Test
    fun emptyOrBlankKeysAreMissing() {
        assertNull(find("com.google.android.geo.API_KEY" to ""))
        assertNull(find("com.google.android.geo.API_KEY" to "  \n"))
        assertNull(find("com.google.android.geo.API_KEY" to null))
    }

    @Test
    fun geoKeyIsFoundAndTrimmed() {
        assertEquals("AIzaKey", find("com.google.android.geo.API_KEY" to " AIzaKey "))
    }

    @Test
    fun legacyKeyIsAccepted() {
        assertEquals("legacy", find("com.google.android.maps.v2.API_KEY" to "legacy"))
        assertEquals("legacy", find("com.google.android.geo.API_KEY" to "", "com.google.android.maps.v2.API_KEY" to "legacy"))
    }

    @Test
    fun geoKeyWinsOverLegacyKey() {
        assertEquals("geo", find("com.google.android.geo.API_KEY" to "geo", "com.google.android.maps.v2.API_KEY" to "legacy"))
    }

    @Test
    fun nonStringValuesAreReadAsText() {
        assertEquals("12345", find("com.google.android.geo.API_KEY" to 12345))
    }
}
