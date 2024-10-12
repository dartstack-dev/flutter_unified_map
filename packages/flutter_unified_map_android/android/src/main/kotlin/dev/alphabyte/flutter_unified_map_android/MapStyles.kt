package dev.alphabyte.flutter_unified_map_android

import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.model.MapStyleOptions

object MapStyles {
    private const val MUTED = """
        {"elementType":"geometry","stylers":[{"saturation":-100},{"lightness":25}]},
        {"elementType":"labels.text.fill","stylers":[{"color":"#8c8c8c"}]},
        {"elementType":"labels.text.stroke","stylers":[{"color":"#f7f7f7"}]},
        {"elementType":"labels.icon","stylers":[{"saturation":-100},{"lightness":30}]},
        {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#c8c8c8"}]},
        {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#f2f2f2"}]},
        {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
        {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#e0e0e0"}]},
        {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#e8e8e8"}]},
        {"featureType":"transit","stylers":[{"visibility":"off"}]},
        {"featureType":"water","elementType":"geometry","stylers":[{"color":"#d6d6d6"}]}
    """

    private const val NO_POI = """{"featureType":"poi","stylers":[{"visibility":"off"}]}"""

    fun mapType(style: PMapStyle): Int = when (style) {
        PMapStyle.STANDARD, PMapStyle.MUTED -> GoogleMap.MAP_TYPE_NORMAL
        PMapStyle.SATELLITE -> GoogleMap.MAP_TYPE_SATELLITE
        PMapStyle.HYBRID -> GoogleMap.MAP_TYPE_HYBRID
        PMapStyle.NONE -> GoogleMap.MAP_TYPE_NONE
    }

    fun styleOptions(style: PMapStyle, showsPointsOfInterest: Boolean): MapStyleOptions? {
        val parts = buildList {
            if (style == PMapStyle.MUTED) add(MUTED.trimIndent())
            if (!showsPointsOfInterest) add(NO_POI)
        }
        return if (parts.isEmpty()) null else MapStyleOptions("[${parts.joinToString(",")}]")
    }
}
