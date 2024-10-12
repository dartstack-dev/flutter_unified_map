package dev.alphabyte.flutter_unified_map_android

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import android.util.LruCache
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.model.Tile
import com.google.android.gms.maps.model.TileOverlay
import com.google.android.gms.maps.model.TileOverlayOptions
import com.google.android.gms.maps.model.TileProvider
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.MalformedURLException
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.floor

class TileController(
    private val map: GoogleMap,
    private val density: Density,
    private val onBaseMapReplacementChanged: () -> Unit,
) {
    private class Layer(var source: PTileLayer, val retina: Boolean, val overlay: TileOverlay)

    private val layers = HashMap<String, Layer>()

    val replacesBaseMap: Boolean get() = layers.values.any { it.source.replacesBaseMap }

    fun update(added: List<PTileLayer>, changed: List<PTileLayer>, removedIds: List<String>) {
        val before = replacesBaseMap
        for (id in removedIds) remove(id)
        for (layer in changed) {
            val current = layers[layer.id]
            if (current != null && current.retina == retina(layer) && sameTiles(current.source, layer)) {
                current.overlay.transparency = transparency(layer)
                current.overlay.zIndex = layer.zIndex.toFloat()
                current.source = layer
            } else {
                remove(layer.id)
                add(layer)
            }
        }
        for (layer in added) {
            remove(layer.id)
            add(layer)
        }
        if (before != replacesBaseMap) onBaseMapReplacementChanged()
    }

    /** The `{r}` choice depends on the density, so the layers that use it are fetched again. */
    fun onDensityChanged() {
        for (layer in layers.values.filter { it.retina != retina(it.source) }) {
            remove(layer.source.id)
            add(layer.source)
        }
    }

    private fun add(layer: PTileLayer) {
        val retina = retina(layer)
        val provider = HttpTileProvider(
            TileUrlTemplate(layer, retina),
            layer.headers,
            TileGrid.levelsAbove256(layer.tileSize.toInt()),
        )
        val options = TileOverlayOptions()
            .tileProvider(provider)
            .zIndex(layer.zIndex.toFloat())
            .transparency(transparency(layer))
            .fadeIn(true)
        val overlay = map.addTileOverlay(options) ?: return
        layers[layer.id] = Layer(layer, retina, overlay)
    }

    private fun remove(id: String) {
        layers.remove(id)?.overlay?.remove()
    }

    private fun retina(layer: PTileLayer): Boolean = density.value >= 2f && layer.urlTemplate.contains("{r}")

    private fun transparency(layer: PTileLayer): Float = (1.0 - layer.opacity).toFloat().coerceIn(0f, 1f)

    private fun sameTiles(a: PTileLayer, b: PTileLayer): Boolean =
        a.urlTemplate == b.urlTemplate &&
            a.subdomains == b.subdomains &&
            a.minZoom == b.minZoom &&
            a.maxZoom == b.maxZoom &&
            a.tileSize == b.tileSize &&
            a.headers == b.headers
}

class TileUrlTemplate(private val layer: PTileLayer, retina: Boolean) {
    private val malformedLogged = AtomicBoolean()
    private val retinaSuffix = if (retina) "@2x" else ""

    fun covers(zoom: Int): Boolean = zoom >= layer.minZoom

    /** Levels past `maxZoom`, the source's last native level: those cells are crops of its tiles, scaled up. */
    fun levelsAboveMaxZoom(zoom: Int): Int = maxOf(0, zoom - floor(layer.maxZoom).toInt())

    /** The subdomain follows from the coordinates, as in flutter_map, so a tile always has the same URL. */
    fun url(x: Int, y: Int, zoom: Int): URL? {
        val subdomain = if (layer.subdomains.isEmpty()) ""
        else layer.subdomains[Math.floorMod(x + y, layer.subdomains.size)]
        val url = layer.urlTemplate
            .replace("{z}", zoom.toString())
            .replace("{x}", x.toString())
            .replace("{y}", y.toString())
            .replace("{s}", subdomain)
            .replace("{r}", retinaSuffix)
        // Runs on the Maps SDK tile thread, where an uncaught exception would crash the app.
        return try {
            URL(url)
        } catch (e: MalformedURLException) {
            if (malformedLogged.compareAndSet(false, true)) {
                Log.w(TAG, "tile layer ${layer.id}: malformed url template ${layer.urlTemplate}", e)
            }
            null
        }
    }
}

/**
 * Google always lays tiles on a 256 dp grid. A `tileSize` of 256 × 2^levels means each source tile covers
 * 2^levels × 2^levels grid cells, as MapKit draws it: Google's cell (x, y, z) is a crop of source tile
 * (x >> shift, y >> shift, z - shift).
 */
object TileGrid {
    data class Source(val x: Int, val y: Int, val zoom: Int, val column: Int, val row: Int, val divisions: Int)

    fun levelsAbove256(tileSize: Int): Int {
        if (tileSize <= 256 || tileSize % 256 != 0) return 0
        val ratio = tileSize / 256
        return if (ratio and (ratio - 1) == 0) Integer.numberOfTrailingZeros(ratio) else 0
    }

    fun source(x: Int, y: Int, zoom: Int, levels: Int): Source {
        val shift = minOf(levels, zoom)
        val mask = (1 shl shift) - 1
        return Source(x shr shift, y shr shift, zoom - shift, x and mask, y and mask, 1 shl shift)
    }
}

/**
 * Fetches tiles itself rather than through `UrlTileProvider`, which sends no headers, cannot crop larger tiles and
 * cannot tell a missing tile from a server error. The Maps SDK already calls `getTile` on background threads.
 */
class HttpTileProvider(
    private val template: TileUrlTemplate,
    private val headers: Map<String, String>,
    private val levels: Int,
) : TileProvider {
    /** Re-encoding crops as PNG takes tens of ms per tile on the SDK's tile threads. */
    private val losslessFormat =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSLESS else Bitmap.CompressFormat.PNG

    private val sources = object : LruCache<String, Decoded>(16 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Decoded): Int = value.bitmap.byteCount
    }
    private val inFlight = ConcurrentHashMap<String, Any>()

    override fun getTile(x: Int, y: Int, zoom: Int): Tile? {
        if (!template.covers(zoom)) return TileProvider.NO_TILE
        // Runs on the Maps SDK tile thread, where an uncaught exception would crash the app.
        return try {
            val shift = levels + template.levelsAboveMaxZoom(zoom)
            if (shift == 0) {
                val url = template.url(x, y, zoom) ?: return TileProvider.NO_TILE
                when (val result = fetch(url)) {
                    is Fetch.Body -> {
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeByteArray(result.bytes, 0, result.bytes.size, bounds)
                        if (bounds.outWidth <= 0) TileProvider.NO_TILE
                        else Tile(bounds.outWidth, bounds.outHeight, result.bytes)
                    }
                    Fetch.Missing -> TileProvider.NO_TILE
                    Fetch.Retry -> null
                }
            } else {
                croppedTile(TileGrid.source(x, y, zoom, shift))
            }
        } catch (e: Exception) {
            Log.w(TAG, "tile $zoom/$x/$y failed", e)
            null
        }
    }

    private fun croppedTile(source: TileGrid.Source): Tile? {
        val url = template.url(source.x, source.y, source.zoom) ?: return TileProvider.NO_TILE
        val key = "${source.zoom}/${source.x}/${source.y}"
        val decoded = sources.get(key) ?: synchronized(inFlight.computeIfAbsent(key) { Any() }) {
            try {
                sources.get(key) ?: when (val result = fetch(url)) {
                    is Fetch.Body -> decode(result.bytes)?.also { sources.put(key, it) } ?: return TileProvider.NO_TILE
                    Fetch.Missing -> return TileProvider.NO_TILE
                    Fetch.Retry -> return null
                }
            } finally {
                inFlight.remove(key)
            }
        }
        val bitmap = decoded.bitmap
        val width = bitmap.width / source.divisions
        val height = bitmap.height / source.divisions
        if (width <= 0 || height <= 0) return TileProvider.NO_TILE
        val crop = if (source.divisions == 1) bitmap
        else Bitmap.createBitmap(bitmap, source.column * width, source.row * height, width, height)
        val bytes = ByteArrayOutputStream().use { stream ->
            if (decoded.opaque) crop.compress(Bitmap.CompressFormat.JPEG, 90, stream)
            else crop.compress(losslessFormat, 100, stream)
            stream.toByteArray()
        }
        return Tile(width, height, bytes)
    }

    private class Decoded(val bitmap: Bitmap, val opaque: Boolean)

    private fun decode(bytes: ByteArray): Decoded? {
        val options = BitmapFactory.Options()
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
        return Decoded(bitmap, options.outMimeType == "image/jpeg")
    }

    private sealed interface Fetch {
        class Body(val bytes: ByteArray) : Fetch

        data object Missing : Fetch

        data object Retry : Fetch
    }

    private fun fetch(url: URL): Fetch {
        val connection = url.openConnection() as? HttpURLConnection ?: return Fetch.Missing
        connection.connectTimeout = 10_000
        connection.readTimeout = 15_000
        connection.useCaches = true
        headers.forEach { (key, value) -> connection.setRequestProperty(key, value) }
        return try {
            val code = connection.responseCode
            when {
                code == HttpURLConnection.HTTP_OK -> Fetch.Body(connection.inputStream.use { it.readBytes() })
                // A null tile makes the Maps SDK retry with backoff; NO_TILE is final for this coordinate.
                code == 429 || code >= 500 -> Fetch.Retry
                else -> Fetch.Missing
            }
        } catch (e: IOException) {
            Fetch.Retry
        } finally {
            connection.disconnect()
        }
    }
}
