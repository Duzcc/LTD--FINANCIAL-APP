import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:finance_app/core/widgets/finance_ui.dart';

/// Nút micro: đọc giọng nói tiếng Việt thành văn bản (nhận dạng của hệ điều hành,
/// chạy trên thiết bị khi được hỗ trợ). Gọi [onText] liên tục khi đang nghe.
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({super.key, required this.onText, this.onDone});
  final ValueChanged<String> onText;
  final VoidCallback? onDone;
  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  static final _speech = SpeechToText();
  static bool? _ready;
  bool listening = false;

  Future<void> toggle() async {
    if (listening) {
      await _speech.stop();
      setState(() => listening = false);
      return;
    }
    try {
      _ready ??= await _speech.initialize(onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted && listening) {
          setState(() => listening = false);
          widget.onDone?.call();
        }
      });
    } catch (_) {
      _ready = false;
    }
    if (!mounted) return;
    if (_ready != true) {
      message(context, 'Thiết bị chưa cho phép hoặc không hỗ trợ nhận dạng giọng nói.');
      return;
    }
    final locales = await _speech.locales();
    final vi = locales.where((l) => l.localeId.toLowerCase().startsWith('vi')).firstOrNull;
    if (!mounted) return;
    setState(() => listening = true);
    await _speech.listen(
        listenOptions: SpeechListenOptions(
            localeId: vi?.localeId ?? 'vi_VN',
            listenFor: const Duration(seconds: 20),
            pauseFor: const Duration(seconds: 3),
            partialResults: true,
            cancelOnError: true),
        onResult: (SpeechRecognitionResult r) => widget.onText(r.recognizedWords));
  }

  @override
  void dispose() {
    if (listening) _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: listening ? 'Dừng nghe' : 'Nói để nhập',
      onPressed: toggle,
      icon: Icon(listening ? Icons.stop_circle : Icons.mic_none,
          color: listening ? AppColors.accentRed : AppColors.primaryGreen));
}
