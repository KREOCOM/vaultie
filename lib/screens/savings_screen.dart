import 'package:flutter/material.dart';

import '../main.dart' show VaultieColors;
import '../models/subscription.dart';

/// A single money-saving suggestion shown on the "Ways to save" screen.
class SavingTip {
  const SavingTip({
    required this.title,
    required this.detail,
    required this.forSub,
    required this.icon,
    this.estSaving,
    this.specific = false,
  });

  final String title; // the action, e.g. "Get the Family plan"
  final String detail; // one-line explanation
  final String forSub; // which subscription it relates to
  final IconData icon;
  final double? estSaving; // rough €/month, null when it's just a nudge
  final bool specific; // true = brand-specific catalogue tip
}

/// Curated, brand-specific catalogue. Matched by keyword in the subscription
/// name. Hand-maintained and grows with each app update — only the most popular
/// services are covered. Everything else falls back to the generic tips below,
/// so no subscription is ever left without a suggestion.
List<SavingTip> _specificTips(Subscription s, bool lt) {
  final n = s.name.toLowerCase();
  SavingTip t(String title, String detail, IconData icon, double? saving) =>
      SavingTip(
          title: title,
          detail: detail,
          forSub: s.name,
          icon: icon,
          estSaving: saving,
          specific: true);

  if (n.contains('netflix')) {
    return [
      t(lt ? 'Rinkis planą su reklama' : 'Try the ad-supported plan',
          lt ? 'Maždaug €5/mėn pigiau nei Standard' : 'Roughly €5/mo cheaper than Standard',
          Icons.tv_rounded, 5)
    ];
  }
  if (n.contains('spotify')) {
    return [
      t(lt ? 'Dalinkis Duo ar Family planu' : 'Share a Duo or Family plan',
          lt ? 'Pasidalink vienu planu su kitais' : 'Split one plan with others',
          Icons.groups_rounded, 5)
    ];
  }
  if (n.contains('youtube')) {
    return [
      t(lt ? 'Rinkis Family planą' : 'Get the Family plan',
          lt ? 'Iki 5 žmonių — pasidalink kainą' : 'Covers up to 5 people — split the cost',
          Icons.groups_rounded, 6)
    ];
  }
  if (n.contains('chatgpt') || n.contains('openai')) {
    return [
      t(lt ? 'Nemokama versija gali pakakti' : 'The free tier may be enough',
          lt ? 'Nemokama tinka kasdieniam naudojimui' : 'Free covers most everyday use',
          Icons.savings_rounded, 20)
    ];
  }
  if (n.contains('icloud') || n.contains('apple')) {
    return [
      t(lt ? 'Junk į Apple One' : 'Bundle with Apple One',
          lt ? 'Pigiau, jei naudoji kelias Apple paslaugas' : 'Cheaper if you use several Apple services',
          Icons.cloud_rounded, 2)
    ];
  }
  if (n.contains('gym') || n.contains('sport')) {
    return [
      t(lt ? 'Mokėk metinį' : 'Pay annually',
          lt ? 'Metinė narystė dažnai duoda 1–2 mėn. dovanų' : 'Yearly membership often gives 1–2 months free',
          Icons.calendar_month_rounded, 6)
    ];
  }
  if (n.contains('insurance') || n.contains('draud')) {
    return [
      t(lt ? 'Palygink pasiūlymus' : 'Compare quotes this year',
          lt ? 'Draudikai dažnai apdovanoja už perėjimą' : 'Insurers often reward switching',
          Icons.compare_arrows_rounded, 8)
    ];
  }
  return const [];
}

/// Generic tips that apply to ANY subscription — even niche or local ones the
/// catalogue doesn't know (TV3, Delfi, 15min.lt…). Phrased as prompts, never as
/// specific price promises.
SavingTip _genericTip(Subscription s, bool lt) {
  if (s.billingCycle == BillingCycle.monthly && s.monthlyCost >= 3) {
    return SavingTip(
      title: lt ? 'Pasidomėk metiniu planu' : 'Ask about an annual plan',
      detail: lt ? 'Metinis dažnai sutaupo 10–20%' : 'Yearly billing often saves 10–20%',
      forSub: s.name,
      icon: Icons.calendar_month_rounded,
      estSaving: s.monthlyCost * 0.15,
    );
  }
  return SavingTip(
    title: lt ? 'Ar dar naudoji?' : 'Still using it?',
    detail: lt ? 'Jei ne, atsisakius atsilaisvintų šis mokėjimas' : 'If not, cancelling frees up this payment',
    forSub: s.name,
    icon: Icons.help_outline_rounded,
    estSaving: null,
  );
}

/// Builds the ranked list of tips for a set of subscriptions.
({List<SavingTip> tips, double total}) buildSavingTips(
    List<Subscription> subs, bool lt) {
  final tips = <SavingTip>[];
  for (final s in subs) {
    final specific = _specificTips(s, lt);
    tips.addAll(specific.isNotEmpty ? specific : [_genericTip(s, lt)]);
  }
  final ent = subs.where((s) => s.category == 'entertainment').toList();
  if (ent.length >= 3) {
    final cheapest =
        ent.map((e) => e.monthlyCost).reduce((a, b) => a < b ? a : b);
    tips.insert(
      0,
      SavingTip(
        title: lt
            ? 'Turi ${ent.length} pramogų prenumeratas'
            : 'You have ${ent.length} entertainment subscriptions',
        detail: lt
            ? 'Rotuojant, o ne kaupiant, galima sutaupyti'
            : 'Rotating instead of stacking could save',
        forSub: lt ? 'Pramogos' : 'Entertainment',
        icon: Icons.auto_awesome_rounded,
        estSaving: cheapest,
      ),
    );
  }
  tips.sort((a, b) {
    if (a.specific != b.specific) return a.specific ? -1 : 1;
    return (b.estSaving ?? 0).compareTo(a.estSaving ?? 0);
  });
  final total = tips.fold<double>(0, (sum, t) => sum + (t.estSaving ?? 0));
  return (tips: tips, total: total);
}

/// Premium "Ways to save" screen: personalised, on-device money-saving tips.
class SavingsScreen extends StatelessWidget {
  const SavingsScreen({super.key, required this.subscriptions});

  static const route = '/savings';

  final List<Subscription> subscriptions;

  @override
  Widget build(BuildContext context) {
    final lt = Localizations.localeOf(context).languageCode == 'lt';
    final result = buildSavingTips(subscriptions, lt);
    return Scaffold(
      backgroundColor: VaultieColors.surface,
      appBar: AppBar(
        backgroundColor: VaultieColors.surface,
        elevation: 0,
        foregroundColor: VaultieColors.ink,
        title: Text(lt ? 'Kaip sutaupyti' : 'Ways to save',
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          _hero(lt, result.total, subscriptions.length),
          const SizedBox(height: 22),
          Text(lt ? 'Pasiūlymai' : 'Suggestions',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: VaultieColors.ink)),
          const SizedBox(height: 12),
          for (final tip in result.tips) ...[
            _tipCard(tip),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          Text(
            lt
                ? 'Patarimai — tik pasiūlymai pagal tavo prenumeratas. Visada '
                    'pasitikrink naujausius planus pas paslaugų teikėją.'
                : 'Tips are suggestions based on your subscriptions — always '
                    'check the latest plans with each provider.',
            style: const TextStyle(
                color: VaultieColors.subtle, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _hero(bool lt, double total, int count) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEDF6F0), Color(0xFFDFEEE6)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFCFE3D6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lt ? 'Galėtum sutaupyti iki' : 'You could save up to',
                      style: const TextStyle(
                          color: Color(0xFF5B7365),
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('€${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Color(0xFF123024),
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          height: 1)),
                  const SizedBox(height: 4),
                  Text(
                      lt
                          ? 'per mėnesį · iš $count prenumeratų'
                          : 'a month · across $count subscriptions',
                      style: const TextStyle(
                          color: Color(0xFF5B7365), fontSize: 13)),
                ],
              ),
            ),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: VaultieColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.savings_rounded,
                  color: Colors.white, size: 32),
            ),
          ],
        ),
      );

  Widget _tipCard(SavingTip tip) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: VaultieColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: VaultieColors.brightGreen.withValues(alpha: 0.40),
              width: 1.5),
          boxShadow: [
            BoxShadow(
              color: VaultieColors.brightGreen.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: VaultieColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: VaultieColors.primary.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(tip.icon, color: Colors.white, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tip.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: VaultieColors.ink)),
                  const SizedBox(height: 3),
                  Text('${tip.detail} · ${tip.forSub}',
                      style: const TextStyle(
                          color: VaultieColors.subtle,
                          fontSize: 12.5,
                          height: 1.3)),
                ],
              ),
            ),
            if (tip.estSaving != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: VaultieColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('~€${tip.estSaving!.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ),
            ],
          ],
        ),
      );
}
