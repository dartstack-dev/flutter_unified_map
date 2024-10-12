package dev.alphabyte.flutter_unified_map_android

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

class MapUnavailable(val code: PMapErrorCode, val message: String)

object ApiKeyCheck {
    val META_DATA_NAMES = listOf("com.google.android.geo.API_KEY", "com.google.android.maps.v2.API_KEY")

    const val MISSING_MESSAGE =
        "No Google Maps API key: the com.google.android.geo.API_KEY meta-data is missing or empty in AndroidManifest.xml"

    fun find(metaData: (String) -> Any?): String? =
        META_DATA_NAMES.firstNotNullOfOrNull { name -> metaData(name)?.toString()?.trim()?.takeIf { it.isNotEmpty() } }
}

object MapAvailability {
    fun check(context: Context): MapUnavailable? {
        if (ApiKeyCheck.find(metaDataOf(context)) == null) {
            return MapUnavailable(PMapErrorCode.API_KEY_MISSING, ApiKeyCheck.MISSING_MESSAGE)
        }
        val availability = GoogleApiAvailability.getInstance()
        val status = availability.isGooglePlayServicesAvailable(context)
        if (status != ConnectionResult.SUCCESS) {
            val resolution = if (availability.isUserResolvableError(status)) {
                "; the user can fix this (GoogleApiAvailability.makeGooglePlayServicesAvailable), then the map must be created again"
            } else {
                ""
            }
            return MapUnavailable(
                PMapErrorCode.SERVICES_UNAVAILABLE,
                "Google Play services are not available: ${availability.getErrorString(status)} (status $status)$resolution",
            )
        }
        return null
    }

    private fun metaDataOf(context: Context): (String) -> Any? {
        val info = try {
            applicationInfo(context.packageManager, context.packageName)
        } catch (e: PackageManager.NameNotFoundException) {
            Log.w(TAG, "cannot read the application meta-data", e)
            null
        }
        val bundle = info?.metaData ?: return { null }
        @Suppress("DEPRECATION")
        return { name -> bundle.get(name) }
    }

    private fun applicationInfo(packageManager: PackageManager, packageName: String): ApplicationInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getApplicationInfo(
                packageName,
                PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
        }
}
