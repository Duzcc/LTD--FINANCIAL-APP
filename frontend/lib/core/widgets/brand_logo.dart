import 'package:flutter/material.dart';

/// Logo thương hiệu: logo ứng dụng (chiếc ví) và logo trợ lý AI (robot, nền trong suốt).
/// Ảnh gốc 1024 px nằm ở `assets/branding/`; ứng dụng dùng bản 256 px cho nhẹ.
class BrandLogo extends StatelessWidget {
  const BrandLogo.app({super.key, this.size = 72})
      : _asset = 'assets/branding/logo_256.png',
        _label = 'Logo ứng dụng';

  /// Logo trợ lý AI (robot) — dùng cho nút, tiêu đề, thanh điều hướng.
  const BrandLogo.ai({super.key, this.size = 24})
      : _asset = 'assets/branding/ai_assistant_256.png',
        _label = 'Trợ lý AI';

  /// Ảnh đại diện của trợ lý AI (robot) — dùng cạnh tin nhắn trong khung chat.
  const BrandLogo.aiAvatar({super.key, this.size = 32})
      : _asset = 'assets/branding/ai_assistant_avatar_256.png',
        _label = 'Trợ lý AI';

  final double size;
  final String _asset;
  final String _label;

  @override
  Widget build(BuildContext context) => Image.asset(_asset,
      width: size,
      height: size,
      semanticLabel: _label,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Icon(Icons.auto_awesome, size: size * .8));
}
