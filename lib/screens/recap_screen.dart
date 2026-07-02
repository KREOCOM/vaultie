import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../main.dart';
import '../services/recap_service.dart';

const _monthsEn = [
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];
// Genitive forms so "Tavo liepos apžvalga" reads correctly.
const _monthsLt = [
  '',
  'sausio',
  'vasario',
  'kovo',
  'balandžio',
  'gegužės',
  'birželio',
  'liepos',
  'rugpjūčio',
  'rugsėjo',
  'spalio',
  'lapkričio',
  'gruodžio'
];

/// Shows the once-a-month recap of the just-ended month.
Future<void> showMonthlyRecap(BuildContext context, MonthlyRecap recap) {
  final isLt = Localizations.localeOf(context).languageCode == 'lt';
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _RecapDialog(recap: recap, isLt: isLt),
  );
}

class _RecapDialog extends StatelessWidget {
  const _RecapDialog({required this.recap, required this.isLt});

  final MonthlyRecap recap;
  final bool isLt;

  String get _title {
    final m = (isLt ? _monthsLt : _monthsEn)[recap.monthNumber];
    return isLt ? 'Tavo $m apžvalga' : 'Your $m recap';
  }

  ({String text, Color color}) _message() {
    final change = recap.changePercent;
    if (change == null) {
      return (
        text: isLt
            ? 'Štai kaip atrodė praėjęs mėnuo.'
            : "Here's how last month looked.",
        color: VaultieColors.subtle,
      );
    }
    if (change < -5) {
      return (
        text: isLt
            ? 'Šaunu — išleidai mažiau nei ankstesnį mėnesį! 🎉'
            : 'Nice — you spent less than the month before! 🎉',
        color: VaultieColors.primary,
      );
    }
    if (change > 5) {
      return (
        text: isLt
            ? 'Išlaidos šiek tiek paaugo — gal ką nors apkarpyti?'
            : 'Spending crept up a bit — anything to trim?',
        color: VaultieColors.danger,
      );
    }
    return (
      text: isLt ? 'Stabilu — beveik kaip anksčiau.' : 'Steady as she goes.',
      color: VaultieColors.subtle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final change = recap.changePercent;
    final msg = _message();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header band.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D4A2E), Color(0xFF1A6B45)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Text(isLt ? '🎉 Mėnesio apžvalga' : '🎉 Monthly recap',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text(_title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Text(isLt ? 'Iš viso išleista' : 'Total spent',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        letterSpacing: 0.5)),
                Text(formatMoney(recap.total),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800)),
                if (change != null) ...[
                  const SizedBox(height: 8),
                  _ChangePill(change: change, isLt: isLt),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              children: [
                _statRow(
                  '📦',
                  isLt ? 'Prenumeratos' : 'Subscriptions',
                  '${recap.count}',
                ),
                const Divider(height: 22),
                _statRow(
                  '💸',
                  isLt ? 'Brangiausia' : 'Most expensive',
                  recap.topName == null
                      ? '—'
                      : '${recap.topName} · ${formatMoney(recap.topCost)}',
                ),
                const Divider(height: 22),
                _statRow(
                  '📅',
                  isLt ? 'Per dieną' : 'Per day',
                  formatMoney(recap.perDay),
                ),
                const SizedBox(height: 18),
                Text(
                  msg.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: msg.color,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(isLt ? 'Supratau' : 'Got it'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String emoji, String label, String value) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(color: VaultieColors.subtle, fontSize: 14)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: VaultieColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.change, required this.isLt});

  final double change;
  final bool isLt;

  @override
  Widget build(BuildContext context) {
    final down = change < 0;
    final pct = change.abs().round();
    final label = isLt
        ? '${down ? '↓' : '↑'} $pct% nei ankstesnį mėn.'
        : '${down ? '↓' : '↑'} $pct% vs prior month';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
