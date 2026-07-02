import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../l10n/localized_labels.dart';
import '../main.dart';
import '../models/subscription.dart';

/// Spending breakdown: totals, a category donut, and a ranked list.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  static const route = '/analytics';

  static final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  static const _palette = [
    VaultieColors.primary,
    VaultieColors.primaryLight,
    VaultieColors.accent,
    Color(0xFFE9A23B),
    Color(0xFF4A6FA5),
    Color(0xFF8E5BA6),
    Color(0xFFD9534F),
    Color(0xFF6B7E74),
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final box = Hive.box<Subscription>(HiveBoxes.subscriptions);

    return Scaffold(
      appBar: AppBar(title: Text(l.analyticsTitle)),
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: box.listenable(),
          builder: (context, Box<Subscription> b, _) {
            final subs = b.values.toList();
            if (subs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    l.analyticsEmpty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: VaultieColors.subtle),
                  ),
                ),
              );
            }

            final monthly =
                subs.fold<double>(0, (sum, s) => sum + s.monthlyCost);
            final yearly = monthly * 12;

            // Aggregate monthly spend per category.
            final byCategory = <String, double>{};
            for (final s in subs) {
              byCategory.update(
                s.category,
                (v) => v + s.monthlyCost,
                ifAbsent: () => s.monthlyCost,
              );
            }
            final entries = byCategory.entries.toList()
              ..sort((a, c) => c.value.compareTo(a.value));

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: l.perMonth,
                        value: _money.format(monthly),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: l.perYear,
                        value: _money.format(yearly),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: CustomPaint(
                      painter: _DonutPainter(
                        values: [for (final e in entries) e.value],
                        colors: _palette,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _money.format(monthly),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                              ),
                            ),
                            Text(l.slashMonth,
                                style: const TextStyle(
                                    color: VaultieColors.subtle)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l.byCategory,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ...List.generate(entries.length, (i) {
                  final e = entries[i];
                  final pct = monthly == 0 ? 0.0 : e.value / monthly;
                  return _CategoryRow(
                    color: _palette[i % _palette.length],
                    label: categoryLabel(l, e.key),
                    amount: _money.format(e.value),
                    fraction: pct,
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: VaultieColors.subtle)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.color,
    required this.label,
    required this.amount,
    required this.fraction,
  });

  final Color color;
  final String label;
  final String amount;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('${(fraction * 100).round()}%  ',
                  style: const TextStyle(color: VaultieColors.subtle)),
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: const Color(0xFFE1E8E3),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight donut chart so we don't need a charting dependency.
class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;

    final stroke = size.width * 0.16;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - stroke) / 2,
    );

    var start = -math.pi / 2;
    const gap = 0.04;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * (2 * math.pi);
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start + gap / 2, sweep - gap, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values;
}
