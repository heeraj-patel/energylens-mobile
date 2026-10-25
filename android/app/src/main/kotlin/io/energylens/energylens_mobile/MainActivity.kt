package io.energylens.energylens_mobile

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.energylens/navigation_frame",
        ).setMethodCallHandler { call, result ->
            if (call.method != "capture") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            captureNavigationFrame(result)
        }
    }

    private fun captureNavigationFrame(result: MethodChannel.Result) {
        val root = window.decorView.rootView
        val webView = visibleWebViews(root).maxByOrNull { (_, area) -> area }?.first
        if (webView == null || webView.width == 0 || webView.height == 0) {
            result.error("unavailable", "The visible WebView is not laid out.", null)
            return
        }
        val bitmap = Bitmap.createBitmap(
            webView.width,
            webView.height,
            Bitmap.Config.ARGB_8888,
        )
        bitmap.eraseColor(0xFFF9F9FF.toInt())
        webView.draw(Canvas(bitmap))
        returnBitmap(result, bitmap)
    }

    private fun visibleWebViews(view: View): List<Pair<WebView, Long>> {
        val matches = mutableListOf<Pair<WebView, Long>>()
        if (view is WebView && view.isShown) {
            val visible = Rect()
            if (view.getGlobalVisibleRect(visible)) {
                matches += view to visible.width().toLong() * visible.height().toLong()
            }
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                matches += visibleWebViews(view.getChildAt(index))
            }
        }
        return matches
    }

    private fun returnBitmap(result: MethodChannel.Result, bitmap: Bitmap) {
        Thread {
            val jpeg = bitmap.toJpeg()
            runOnUiThread { result.success(jpeg) }
        }.start()
    }

    private fun Bitmap.toJpeg(): ByteArray {
        val output = ByteArrayOutputStream()
        compress(Bitmap.CompressFormat.JPEG, 80, output)
        recycle()
        return output.toByteArray()
    }
}
