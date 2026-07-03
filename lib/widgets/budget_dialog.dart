import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../main.dart';

/// Opens the monthly-budget editor and applies the result.
///
/// The budget is entirely manual and optional: the user types an amount to set
/// it, taps Clear to remove it, or cancels to leave it unchanged.
Future<void> editMonthlyBudget(BuildContext context, {required bool isLt}) async {
  // Returns: null = cancel, -1 = clear, > 0 = new budget.
  final result = await showDialog<double>(
    context: context,
    builder: (_) => _BudgetDialog(isLt: isLt, initial: AppPrefs.budget.value),
  );
  if (result == null) return;
  if (result < 0) {
    await AppPrefs.setBudget(null);
  } else if (result > 0) {
    await AppPrefs.setBudget(result);
  }
}

/// Monthly-budget entry dialog. A StatefulWidget so its controller is disposed
/// by the framework (disposing inline after `await showDialog` crashes).
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.isLt, required this.initial});

  final bool isLt;
  final double? initial;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _controller =
      TextEditingController(text: widget.initial?.toStringAsFixed(0) ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? _parse() =>
      double.tryParse(_controller.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final isLt = widget.isLt;
    return AlertDialog(
      title: Text(isLt ? 'Mėnesio biudžetas' : 'Monthly budget'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLt
                ? 'Neprivaloma — nustatyk sau tikslą, kiek nori išleisti per mėnesį.'
                : 'Optional — set yourself a target for how much to spend per month.',
            style: const TextStyle(fontSize: 13, color: VaultieColors.subtle),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '${AppPrefs.currency.value} ',
              hintText: '0',
            ),
            onSubmitted: (_) => Navigator.of(context).pop(_parse()),
          ),
        ],
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(-1.0),
            style: TextButton.styleFrom(foregroundColor: VaultieColors.danger),
            child: Text(isLt ? 'Pašalinti' : 'Clear'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isLt ? 'Atšaukti' : 'Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_parse()),
          child: Text(isLt ? 'Išsaugoti' : 'Save'),
        ),
      ],
    );
  }
}
