import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Một khối chữ do OCR trả về, tọa độ gốc trên-trái (đơn vị pixel của ảnh).
class OcrLine {
  const OcrLine(this.text, this.x, this.y, this.w, this.h,
      {this.confidence = 1, this.angle});
  final String text;
  final double x, y, w, h, confidence;

  /// Độ nghiêng của khối (radian) nếu engine cung cấp.
  final double? angle;

  factory OcrLine.fromMap(Map<dynamic, dynamic> m) => OcrLine(
      '${m['text']}',
      (m['x'] as num).toDouble(),
      (m['y'] as num).toDouble(),
      (m['w'] as num).toDouble(),
      (m['h'] as num).toDouble(),
      confidence: (m['confidence'] as num?)?.toDouble() ?? 1,
      angle: (m['angle'] as num?)?.toDouble());
}

class OcrResult {
  const OcrResult(this.engine, this.lines);
  final String engine;
  final List<OcrLine> lines;

  /// Văn bản đã dựng lại theo dòng (khối bên trái và bên phải cùng hàng được nối).
  String get text => groupRows(lines).join('\n');
}

/// Nhận dạng chữ ngay trên điện thoại, không cần mạng:
/// iOS dùng Apple Vision (hỗ trợ tiếng Việt từ iOS 17), Android dùng Google ML Kit.
class TextRecognizer {
  const TextRecognizer();
  static const _channel = MethodChannel('finance/ocr');

  /// Trả về null nếu nền tảng không hỗ trợ (web, desktop) hoặc nhận dạng lỗi.
  Future<OcrResult?> recognize(String imagePath) async {
    if (kIsWeb) return null;
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('recognize', {'path': imagePath});
      if (r == null) return null;
      final lines = [
        for (final l in (r['lines'] as List? ?? const []))
          if (l is Map) OcrLine.fromMap(l)
      ];
      return OcrResult('${r['engine'] ?? 'device'}', lines);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// Độ nghiêng ảnh = trung vị góc của các khối *dài* (OCR thường báo góc 0 cho khối ngắn như "20.000").
double estimateSkew(List<OcrLine> boxes) {
  final withAngle = boxes.where((b) => b.angle != null && b.w > 3 * b.h).toList();
  if (withAngle.isEmpty) return 0;
  final longest = withAngle.map((b) => b.w).reduce(math.max);
  final angles = [
    for (final b in withAngle)
      if (b.w >= 0.4 * longest) b.angle!
  ]..sort();
  return angles[angles.length ~/ 2];
}

/// Gom các khối chữ thành dòng: xoay tâm khối theo độ nghiêng trung vị của ảnh,
/// khối có tâm dọc gần nhau (≤ 55% chiều cao) thuộc cùng một dòng, sắp xếp trái → phải.
List<String> groupRows(List<OcrLine> lines, {double? skew}) {
  final boxes = lines.where((b) => b.text.trim().isNotEmpty && b.h > 0).toList();
  if (boxes.isEmpty) return const [];
  skew ??= estimateSkew(boxes);
  final c = math.cos(-skew), s = math.sin(-skew);
  final items = [
    for (final b in boxes)
      (
        x: (b.x + b.w / 2) * c - (b.y + b.h / 2) * s,
        y: (b.x + b.w / 2) * s + (b.y + b.h / 2) * c,
        box: b
      )
  ]..sort((a, b) => a.y.compareTo(b.y));
  final rows = <List<({double x, double y, OcrLine box})>>[];
  for (final it in items) {
    var placed = false;
    for (final row in rows.reversed.take(3)) {
      final ry = row.map((r) => r.y).reduce((a, b) => a + b) / row.length;
      final rh = row.map((r) => r.box.h).reduce((a, b) => a + b) / row.length;
      if ((it.y - ry).abs() <= 0.55 * math.min(rh, it.box.h)) {
        row.add(it);
        placed = true;
        break;
      }
    }
    if (!placed) rows.add([it]);
  }
  return [
    for (final row in rows)
      (row..sort((a, b) => a.x.compareTo(b.x))).map((r) => r.box.text.trim()).join('  ')
  ];
}
