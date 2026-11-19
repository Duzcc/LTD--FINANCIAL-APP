import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/security/data/services/app_lock.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/security/presentation/screens/lock_screen.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLock>();
    return FinancePage(
        title: 'Khóa ứng dụng',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SwitchListTile(
                    tileColor: Colors.transparent,
                    secondary: const RoundIcon(Icons.lock_outline),
                    title: const Text('Khóa bằng mã PIN'),
                    subtitle: const Text('Yêu cầu mã khi mở ứng dụng hoặc quay lại sau 30 giây'),
                    value: lock.enabled,
                    onChanged: (v) async {
                      if (v) {
                        await openPage(context, const PinSetupScreen());
                      } else {
                        final ok = await openPage<bool>(context, const PinSetupScreen(verifyOnly: true));
                        if (ok == true) await lock.disable();
                      }
                    }),
                if (lock.enabled) ...[
                  const Divider(indent: 60),
                  ListTile(
                      tileColor: Colors.transparent,
                      leading: const RoundIcon(Icons.password),
                      title: const Text('Đổi mã PIN'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openPage(context, const PinSetupScreen())),
                ],
              ])),
          const SizedBox(height: 12),
          const Text(
              'Mã PIN được mã hóa và chỉ lưu trên điện thoại này. Nếu quên mã, hãy cài lại ứng dụng và đăng nhập để khôi phục dữ liệu từ tài khoản.',
              style: TextStyle(fontSize: 12, height: 1.5)),
        ]));
  }
}
