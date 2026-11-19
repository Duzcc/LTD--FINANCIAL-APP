import 'package:flutter/material.dart';

// Ảnh gốc 1024 px ở assets/branding/, app dùng bản 256 px cho nhẹ.
class BrandLogo extends StatelessWidget {
  const BrandLogo.app({super.key, this.size = 72})
      : _asset = 'assets/branding/logo_256.png',
        _label = 'Logo ứng dụng';

  const BrandLogo.ai({super.key, this.size = 24})
      : _asset = 'assets/branding/ai_assistant_256.png',
        _label = 'Trợ lý AI';

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
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      semanticLabel: _label,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Icon(Icons.auto_awesome, size: size * .8));
}
