import 'package:flutter/material.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

class CurrencySelectionScreen extends StatefulWidget {
  const CurrencySelectionScreen({super.key, this.selectedCurrency = 'VND'});
  final String selectedCurrency;
  static const units = {
    'VND': '🇻🇳  Việt Nam Đồng',
    'USD': '🇺🇸  United States Dollar',
    'EUR': '🇪🇺  Euro',
    'GBP': '🇬🇧  Pound',
    'JPY': '🇯🇵  Japanese Yen',
    'CNY': '🇨🇳  Yuan Renminbi'
  };
  @override
  State<CurrencySelectionScreen> createState() =>
      _CurrencySelectionScreenState();
}

class _CurrencySelectionScreenState extends State<CurrencySelectionScreen> {
  String query = '';
  @override
  Widget build(BuildContext context) => FinancePage(
      title: 'Đơn vị tiền tệ',
      child: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            onChanged: (v) => setState(() => query = v.toLowerCase()),
            decoration: const InputDecoration(
                hintText: 'Tìm tiền tệ', prefixIcon: Icon(Icons.search))),
        const SizedBox(height: 16),
        for (final e in CurrencySelectionScreen.units.entries
            .where((e) => '${e.key} ${e.value}'.toLowerCase().contains(query)))
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                  title: Text(e.value),
                  subtitle: Text(e.key),
                  trailing: e.key == widget.selectedCurrency
                      ? const Icon(Icons.check, color: AppColors.primaryGreen)
                      : null,
                  onTap: () => Navigator.pop(context, e.key))),
      ]));
}
