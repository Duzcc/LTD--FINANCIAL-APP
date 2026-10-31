import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/security/app_lock.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

/// Đặt trên toàn ứng dụng: hiện màn khóa khi mở app hoặc quay lại sau thời gian ở nền.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  DateTime? _pausedAt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<AppLock>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final at = _pausedAt;
      _pausedAt = null;
      if (at != null && DateTime.now().difference(at) >= lock.relockAfter) lock.lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = context.watch<AppLock>().locked;
    return Stack(children: [
      Offstage(offstage: locked, child: TickerMode(enabled: !locked, child: widget.child)),
      if (locked) const Positioned.fill(child: LockScreen()),
    ]);
  }
}

/// Bàn phím nhập mã PIN dùng chung cho mở khóa và đặt mã.
class PinPad extends StatelessWidget {
  const PinPad(
      {super.key,
      required this.title,
      required this.value,
      required this.onChanged,
      this.subtitle,
      this.error,
      this.length = 4});
  final String title;
  final String? subtitle, error;
  final String value;
  final int length;
  final ValueChanged<String> onChanged;

  Widget _key(String label, {IconData? icon, VoidCallback? onTap}) => SizedBox.square(
      dimension: 72,
      child: TextButton(
          style: TextButton.styleFrom(shape: const CircleBorder()),
          onPressed: onTap,
          child: icon != null
              ? Icon(icon, color: AppColors.textPrimary)
              : Text(label,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.textPrimary))));

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        const CircleAvatar(
            radius: 30,
            backgroundColor: Color(0xFFE6D8CB),
            child: Icon(Icons.lock_outline, color: Color(0xFF917560), size: 28)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < length; i++)
            Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < value.length ? AppColors.primaryGreen : Colors.transparent,
                    border: Border.all(color: AppColors.primaryGreen, width: 2))),
        ]),
        SizedBox(
            height: 40,
            child: Center(
                child: Text(error ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.accentRed)))),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9']
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final d in row)
              _key(d, onTap: value.length < length ? () => onChanged(value + d) : null)
          ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox.square(dimension: 72),
          _key('0', onTap: value.length < length ? () => onChanged('${value}0') : null),
          _key('', icon: Icons.backspace_outlined,
              onTap: value.isEmpty ? null : () => onChanged(value.substring(0, value.length - 1))),
        ]),
      ]);
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String pin = '';
  String? error;
  @override
  Widget build(BuildContext context) {
    final lock = Provider.of<AppLock>(context, listen: false);
    return Material(
        color: AppColors.backgroundBeige,
        child: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    child: PinPad(
                        title: 'Nhập mã PIN',
                        subtitle: 'Ứng dụng đang được khóa để bảo vệ dữ liệu tài chính.',
                        value: pin,
                        error: error,
                        onChanged: (v) {
                          setState(() {
                            pin = v;
                            error = null;
                          });
                          if (v.length == 4) {
                            final e = lock.unlock(v);
                            if (e != null) {
                              setState(() {
                                pin = '';
                                error = e;
                              });
                            }
                          }
                        })))));
  }
}

/// Đặt mã PIN mới (nhập hai lần) hoặc xác nhận mã hiện tại trước khi tắt/đổi.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key, this.verifyOnly = false});
  final bool verifyOnly;
  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String value = '', first = '';
  String? error;
  late bool verifying;
  @override
  void initState() {
    super.initState();
    verifying = widget.verifyOnly || context.read<AppLock>().enabled;
  }

  Future<void> onChanged(String v) async {
    setState(() {
      value = v;
      error = null;
    });
    if (v.length < 4) return;
    final lock = context.read<AppLock>();
    if (verifying) {
      if (!lock.check(v)) {
        setState(() {
          value = '';
          error = 'Mã PIN hiện tại không đúng.';
        });
        return;
      }
      if (widget.verifyOnly) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        verifying = false;
        value = '';
      });
      return;
    }
    if (first.isEmpty) {
      setState(() {
        first = v;
        value = '';
      });
      return;
    }
    if (v != first) {
      setState(() {
        first = '';
        value = '';
        error = 'Hai lần nhập không khớp, vui lòng đặt lại.';
      });
      return;
    }
    await lock.setPin(v);
    if (!mounted) return;
    message(context, 'Đã bật khóa ứng dụng bằng mã PIN.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Mã PIN')),
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  child: PinPad(
                      title: verifying
                          ? 'Nhập mã PIN hiện tại'
                          : first.isEmpty
                              ? 'Đặt mã PIN 4 số'
                              : 'Nhập lại mã PIN',
                      subtitle: verifying
                          ? null
                          : 'Mã PIN chỉ lưu trên thiết bị này (đã mã hóa).',
                      value: value,
                      error: error,
                      onChanged: onChanged)))));
}
