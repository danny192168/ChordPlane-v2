package app.chordplane.chord_plane

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "app.chordplane.chord_plane/incoming_files"
    }

    private var channel: MethodChannel? = null

    /// A cold-start intent is captured before Dart has registered its handler,
    /// so keep the copied path until Dart asks for it.
    private var pendingPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        )
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingFile" -> {
                    val path = pendingPath
                    pendingPath = null
                    result.success(path)
                }
                else -> result.notImplemented()
            }
        }
        intent?.let(::capture)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        capture(intent)
    }

    private fun capture(intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND) return

        val uri: Uri? = if (action == Intent.ACTION_SEND) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        } else {
            intent.data
        }

        val path = uri?.let(::copyToCache) ?: return
        pendingPath = path
        val activeChannel = channel ?: return
        // If Dart is already listening this is delivered immediately; on a
        // cold start takePendingFile picks it up instead. Only clear the
        // cached path once Dart confirms it handled the call.
        activeChannel.invokeMethod("incomingFile", path, object : MethodChannel.Result {
            override fun success(result: Any?) {
                pendingPath = null
            }
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {}
        })
    }

    /// CONTENT URIs cannot be opened as ordinary files, and the OS may revoke
    /// permission after the intent finishes. Copy into our private cache so
    /// Dart can decode with the normal `.cpl` reader.
    private fun copyToCache(uri: Uri): String? = try {
        val target = File(cacheDir, "incoming-${System.currentTimeMillis()}.cpl")
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
            target.absolutePath
        }
    } catch (error: Exception) {
        null
    }
}
