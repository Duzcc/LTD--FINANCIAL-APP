import 'package:flutter/material.dart';
import 'package:finance_app/app/app_routes.dart';
import 'package:finance_app/core/theme/app_colors.dart';
import 'package:finance_app/core/widgets/brand_logo.dart';

/// Người đã dùng app (có dữ liệu trên máy) vào thẳng màn chính, người mới vào màn đăng nhập.
/// Dùng pushReplacementNamed để nút Back không quay lại Splash.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.returning});
  final bool returning;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
          context, widget.returning ? AppRoutes.home : AppRoutes.login);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
      backgroundColor: AppColors.backgroundBeige,
      body: Center(child: BrandLogo.app(size: 96)));
}
