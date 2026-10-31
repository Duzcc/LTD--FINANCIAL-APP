package com.nhom3.finance_app

import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Nhận dạng chữ trên thiết bị bằng Google ML Kit (chạy ngoại tuyến), dùng cho đọc hóa đơn.
 * Kênh "finance/ocr", phương thức "recognize" {path} → {engine, lines: [{text, confidence, x, y, w, h, angle}]}.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "finance/ocr").setMethodCallHandler { call, result ->
            if (call.method != "recognize") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("ARGS", "Thiếu đường dẫn ảnh", null)
                return@setMethodCallHandler
            }
            val image = try {
                InputImage.fromFilePath(this, Uri.fromFile(File(path)))
            } catch (e: Exception) {
                result.error("IMAGE", e.message, null)
                return@setMethodCallHandler
            }
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(image)
                .addOnSuccessListener { text ->
                    val lines = ArrayList<Map<String, Any>>()
                    for (block in text.textBlocks) {
                        for (line in block.lines) {
                            val box = line.boundingBox ?: continue
                            lines.add(
                                mapOf(
                                    "text" to line.text,
                                    "confidence" to line.confidence.toDouble(),
                                    "x" to box.left.toDouble(),
                                    "y" to box.top.toDouble(),
                                    "w" to box.width().toDouble(),
                                    "h" to box.height().toDouble(),
                                    "angle" to Math.toRadians(line.angle.toDouble()),
                                )
                            )
                        }
                    }
                    result.success(mapOf("engine" to "mlkit", "lines" to lines))
                    recognizer.close()
                }
                .addOnFailureListener { e ->
                    result.error("OCR", e.message, null)
                    recognizer.close()
                }
        }
    }
}
