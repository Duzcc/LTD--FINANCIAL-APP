import Flutter
import UIKit
import UserNotifications
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Hiển thị thông báo nhắc nhở cả khi ứng dụng đang mở (flutter_local_notifications)
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReceiptOcrPlugin") {
      ReceiptOcrPlugin.register(with: registrar)
    }
  }
}

/// Nhận dạng chữ trên thiết bị bằng Apple Vision (tiếng Việt từ iOS 17), dùng cho đọc hóa đơn.
/// Kênh "finance/ocr", phương thức "recognize" {path} → {engine, languages, lines: [{text, confidence, x, y, w, h, angle}]}
/// với tọa độ pixel, gốc trên-trái; angle là độ nghiêng của dòng (radian, trục y hướng xuống).
class ReceiptOcrPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "finance/ocr", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ReceiptOcrPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognize",
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage else {
        DispatchQueue.main.async { result(FlutterError(code: "IMAGE", message: "Không đọc được ảnh", details: nil)) }
        return
      }
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      if #available(iOS 16.0, *) { request.revision = VNRecognizeTextRequestRevision3 }
      var supported: [String] = []
      if #available(iOS 15.0, *) {
        supported = (try? request.supportedRecognitionLanguages()) ?? []
      } else {
        supported = ["en-US"]  // iOS < 15: Vision chưa có tiếng Việt
      }
      let languages = ["vi-VT", "vi-VN", "en-US"].filter { supported.contains($0) }
      if !languages.isEmpty { request.recognitionLanguages = languages }

      let orientation = CGImagePropertyOrientation(image.imageOrientation)
      let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
      let width = Double(rotated ? cgImage.height : cgImage.width)
      let height = Double(rotated ? cgImage.width : cgImage.height)
      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "OCR", message: error.localizedDescription, details: nil)) }
        return
      }
      let lines: [[String: Any]] = (request.results ?? []).compactMap { obs in
        guard let candidate = obs.topCandidates(1).first else { return nil }
        let box = obs.boundingBox
        let angle = atan2(-Double(obs.topRight.y - obs.topLeft.y) * height, Double(obs.topRight.x - obs.topLeft.x) * width)
        return [
          "text": candidate.string,
          "confidence": Double(candidate.confidence),
          "x": Double(box.minX) * width,
          "y": (1 - Double(box.maxY)) * height,
          "w": Double(box.width) * width,
          "h": Double(box.height) * height,
          "angle": angle,
        ]
      }
      DispatchQueue.main.async {
        result(["engine": "apple-vision", "languages": languages, "lines": lines])
      }
    }
  }
}

extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
