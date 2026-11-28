import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:finance_app/app/app_navigator.dart';
import 'package:finance_app/app/app_routes.dart';

class AuthLinkHandler extends StatefulWidget {
  const AuthLinkHandler({super.key, required this.child});
  final Widget child;

  @override
  State<AuthLinkHandler> createState() => _AuthLinkHandlerState();
}

class _AuthLinkHandlerState extends State<AuthLinkHandler> {
  final _handledLinks = <String>{};
  late final StreamSubscription<Uri> _subscription;

  @override
  void initState() {
    super.initState();
    final links = AppLinks();
    _subscription = links.uriLinkStream.listen(
      _handleUri,
      onError: (Object error) => debugPrint('Không nhận được liên kết email: $error'),
    );
    unawaited(_openInitialLink(links));
  }

  Future<void> _openInitialLink(AppLinks links) async {
    try {
      final uri = await links.getInitialLink();
      if (uri != null) _handleUri(uri);
    } on MissingPluginException catch (error) {
      debugPrint('Deep link chưa được hỗ trợ trên nền tảng này: $error');
    } on PlatformException catch (error) {
      debugPrint('Không đọc được liên kết mở ứng dụng: ${error.message}');
    }
  }

  void _handleUri(Uri uri) {
    String? path;
    if (uri.scheme == 'financeapp' && uri.host == 'auth') {
      path = uri.path;
    } else if (uri.scheme == 'http' && uri.host == '10.0.2.2' && uri.port == 3000) {
      final segments = uri.pathSegments;
      if (segments.length == 4 && segments[0] == 'api' && segments[1] == 'auth' && segments[2] == 'open-app') {
        path = '/${segments[3]}';
      }
    }

    if (path == null) return;
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;

    final route = switch (path) {
      '/verify-email' => AppRoutes.verifyEmail,
      '/reset-password' => AppRoutes.resetPassword,
      _ => null,
    };
    if (route == null || !_handledLinks.add(uri.toString())) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = appNavigatorKey.currentState;
      if (!mounted || navigator == null) {
        _handledLinks.remove(uri.toString());
        return;
      }
      navigator.pushNamedAndRemoveUntil(route, (_) => false, arguments: token);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
