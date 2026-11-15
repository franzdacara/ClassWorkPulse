package com.nikko.classwork.classwork_pulse

import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // llama.cpp needs the GGUF model as a regular file, but Android keeps
        // Flutter assets inside the APK. This channel streams the bundled
        // model out to app storage without loading it into memory.
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "classwork_pulse/model",
        )
        channel.setMethodCallHandler { call, result ->
            val asset = call.argument<String>("asset")
            if (asset == null) {
                result.error("bad_args", "Missing 'asset' argument", null)
                return@setMethodCallHandler
            }
            val assetPath = FlutterInjector.instance().flutterLoader()
                .getLookupKeyForAsset(asset)

            when (call.method) {
                "assetLength" -> result.success(assetLength(assetPath))
                "copyAsset" -> {
                    val dest = call.argument<String>("dest")
                    if (dest == null) {
                        result.error("bad_args", "Missing 'dest' argument", null)
                        return@setMethodCallHandler
                    }
                    ioExecutor.execute {
                        try {
                            copyAsset(assetPath, File(dest)) { copied, total ->
                                mainHandler.post {
                                    channel.invokeMethod(
                                        "copyProgress",
                                        mapOf("copied" to copied, "total" to total),
                                    )
                                }
                            }
                            mainHandler.post { result.success(null) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("copy_failed", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        ioExecutor.shutdown()
        super.onDestroy()
    }

    /** Size of the asset in bytes, or -1 if it is stored compressed. */
    private fun assetLength(assetPath: String): Long =
        try {
            assets.openFd(assetPath).use { it.length }
        } catch (e: IOException) {
            -1L
        }

    /**
     * Copies the asset to [dest] through a `.part` file, so [dest] only ever
     * exists as a complete copy.
     */
    private fun copyAsset(
        assetPath: String,
        dest: File,
        onProgress: (copied: Long, total: Long) -> Unit,
    ) {
        val total = assetLength(assetPath)
        val part = File(dest.path + ".part")
        dest.parentFile?.mkdirs()
        try {
            assets.open(assetPath).use { input ->
                FileOutputStream(part).use { output ->
                    val buffer = ByteArray(1 shl 20)
                    var copied = 0L
                    var reported = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        copied += read
                        if (copied - reported >= PROGRESS_STEP_BYTES) {
                            reported = copied
                            onProgress(copied, total)
                        }
                    }
                    output.fd.sync()
                }
            }
            if (!part.renameTo(dest)) {
                throw IOException("Could not move the model into place")
            }
        } finally {
            part.delete()
        }
    }

    private companion object {
        const val PROGRESS_STEP_BYTES = 8L * 1024 * 1024
    }
}
