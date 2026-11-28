import 'package:flutter/material.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/ai/domain/services/insights.dart';
import 'package:finance_app/features/ledger/presentation/screens/ledger_screen.dart';

class InsightTile extends StatelessWidget {
  const InsightTile({super.key, required this.insight});
  final Insight insight;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (insight.level) {
      InsightLevel.danger => (Icons.error_outline, AppColors.accentRed),
      InsightLevel.warning => (Icons.warning_amber_rounded, AppColors.accentYellow),
      InsightLevel.good => (Icons.verified_outlined, AppColors.primaryGreen),
      InsightLevel.info => (Icons.lightbulb_outline, const Color(0xFF8D7564)),
    };
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
                tileColor: Colors.transparent,
                leading: RoundIcon(icon, color: color),
                title: Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(insight.detail, style: const TextStyle(height: 1.4)),
                onTap: insight.categoryId != null
                    ? () => openPage(context, LedgerScreen(initialCategoryId: insight.categoryId))
                    : null)));
  }
}
