// ══════════════════════════════════════════════════════════════════════════════
// INVESTAVIMAS — manually-tracked stock holdings (Phase 1 prototype)
// ══════════════════════════════════════════════════════════════════════════════
//
// PROTOTYPE (2026-08-27). Deliberately isolated so it can be deleted cleanly
// if it doesn't work out — nothing outside this file, stock_service.dart,
// stock_catalog.dart, functions/stock_quote.py, and its one registration
// line in functions/main.py touches this feature. To remove it entirely:
//   1. Delete this file, stock_service.dart, stock_catalog.dart.
//   2. Delete functions/stock_quote.py and its import + @https_fn.on_call
//      block in functions/main.py, then `firebase deploy --only functions`
//      (or just leave the deployed function running unused — it costs
//      nothing when idle).
//   3. Remove the "Investavimas" nav item + IndexedStack entry in
//      dashboard_preview.dart (search "InvestingTab").
//   4. DashboardStore.investments()/setInvestments() can stay — dead code,
//      harmless, or delete them too.
//
// No shared state with the rest of the dashboard: reads/writes its own Hive
// key (DashboardStore.investments()) and never touches `_d`/`all`/budgets/
// anything else. A user with zero holdings sees an empty state; nothing
// elsewhere in the app changes behaviour because this file exists.
//
// Data cost: $0 per lookup by design — see stock_service.dart's and
// functions/stock_quote.py's own docs for why (Stooq, free, keyless,
// cached server-side). FX (USD→EUR) reuses the app's existing free ECB
// feed (FxRates), same one Money/display-currency already runs on.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/stock_catalog.dart';
import '../../i18n.dart';
import '../../services/dashboard_store.dart';
import '../../services/fx_rates.dart';
import '../../services/stock_service.dart';
import '../../ui/design_system.dart';

// ── local theme tokens ──────────────────────────────────────────────────────
// Can't import dashboard_preview.dart's private _ink/_card/etc (Dart's `_`
// prefix is library-private) — mirrors the exact same hex values from its
// _applyTheme so this tab is visually indistinguishable from the rest of the
// app despite being a separate file. If those values ever change there,
// update here too (search "mirrors _applyTheme").
// 2026-08-28: switched to a FIXED dark palette, deliberately independent of
// AppPrefs.darkMode — per explicit request to match the "01 Robinhood
// classic" concept from the 5-design comparison specifically, which is a
// near-black trading-app look, not our usual light/dark toggle. This tab
// commits to it regardless of the rest of the app's theme, the same way
// Robinhood/Webull's own trading screens don't follow a light iOS system
// setting either.
class _Pal {
  const _Pal();
  Color get bg => const Color(0xFF0A0A0F);
  Color get card => const Color(0xFF16171D);
  Color get ink => const Color(0xFFF2F3F5);
  Color get muted => const Color(0xFFBDB7CE);
  Color get faint => const Color(0xFF8B8D96);
  Color get hair => const Color(0xFF23242C);
  Color get soft => const Color(0xFF1C1D24);
  Color get purple => const Color(0xFF8B5CF6);
  Color get purpleDeep => const Color(0xFF6D3EE0);
  Color get purpleSoft => const Color(0xFF2A2150);
  // The app's own blue (matches the brand accent used elsewhere) — used for
  // primary calls-to-action inside the add-holding flow (Pridėti/Keisti,
  // Kiekis/Suma) and the welcome screen's CTA, per explicit request, while
  // the rest of the tab (icons, spinners, chart) keeps the purple "01"
  // accent it was designed around.
  Color get blue => const Color(0xFF2F7CF6);
  Color get blueSoft => const Color(0xFF1B2A4A);
  static const good = Color(0xFF34D399);
  static const bad = Color(0xFFF87171);
}

/// A colored initials circle for a ticker with no known logo yet (a live
/// search hit before it's been picked — see stock_profile's one-call-on-
/// pick design). Deterministic per symbol (hashed to one of a small fixed
/// palette) so the same ticker always gets the same color, the same trick
/// Robinhood/eToro use for symbols they don't have artwork for.
class _TickerBadge extends StatelessWidget {
  const _TickerBadge({required this.symbol, required this.pal});
  final String symbol;
  final _Pal pal;

  static const _palette = [
    Color(0xFF5B6EF5),
    Color(0xFFE0574F),
    Color(0xFF2FA34E),
    Color(0xFFE9A23B),
    Color(0xFF00897B),
    Color(0xFF8B5CF6),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[symbol.hashCode.abs() % _palette.length];
    final initials = symbol.length >= 2 ? symbol.substring(0, 2) : symbol;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(13)),
      child: Text(initials,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}

/// The portfolio hero's "today" chart — a bold filled area/line, sized and
/// styled to match the "01 Robinhood classic" reference, but built from
/// exactly THREE real numbers (see _totalCard's own doc): today's open, the
/// extreme that actually happened (high if the day is up, low if down), and
/// the current value. No fourth point is invented, and no ordering beyond
/// "open, then now" is implied — Finnhub's free tier has no intraday time
/// series to draw a real multi-tick line from.
///
/// 2026-08-28 rework, per explicit correction: the previous 3-point version
/// (open → today's extreme → current) could visually slope DOWN at the end
/// even on a net-up day, whenever the extreme happened to sit above both
/// endpoints — exactly backwards from what the green/red label above it
/// said. A straight line has no such failure mode: its slope IS the sign of
/// `current - open`, always.
///
/// The low/high range used to also draw as a flat shaded rectangle behind
/// the line — removed per explicit correction ("nereikia to permatomo
/// šviesaus bloko"): it read as a stray translucent panel, not part of the
/// chart. high/low still shape the Y-AXIS SCALE below (so the line's own
/// slope is honestly proportioned against the day's real range instead of
/// stretching a tiny move to fill the whole card), they just aren't drawn
/// as their own shape anymore.
class _PortfolioTodayChartPainter extends CustomPainter {
  _PortfolioTodayChartPainter({
    required this.open,
    required this.high,
    required this.low,
    required this.current,
    required this.color,
  });
  final double open, high, low, current;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = [open, high, low, current].reduce((a, b) => a > b ? a : b);
    final minV = [open, high, low, current].reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : maxV - minV;
    const padTop = 34.0, padBottom = 22.0;
    final h = size.height - padTop - padBottom;
    double yOf(double v) => padTop + h - (v - minV) / range * h;

    final startY = yOf(open), endY = yOf(current);
    final line = Path()..moveTo(0, startY)..lineTo(size.width, endY);
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    // Soft fill under the line — same trick every real trading app uses
    // (Robinhood, Apple Stocks): the line itself is what reads as "the
    // chart", this just gives it a body instead of floating on flat colour.
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    // A faint blurred duplicate under the crisp line reads as a glow, so the
    // white line pops even over the gradient's lighter top-left corner, not
    // just the darker one.
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(Offset(size.width, endY), 6, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(Offset(size.width, endY), 4.5, Paint()..color = color);

    // Money labels ON the chart — "Atidarymas €X" at the start, the current
    // value repeated at the end (redundant with the big number above it,
    // same convention every real chart app uses on its endpoint anyway).
    void label(String text, double x, double y, TextAlign align) {
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.85))),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = align == TextAlign.left ? x : x - tp.width;
      tp.paint(canvas, Offset(dx, y));
    }

    label(Money.format(open), 0, (startY - 20).clamp(0, size.height - 16), TextAlign.left);
    label(Money.format(current), size.width, (endY - 20).clamp(0, size.height - 16),
        TextAlign.right);
  }

  @override
  bool shouldRepaint(covariant _PortfolioTodayChartPainter old) =>
      old.open != open ||
      old.high != high ||
      old.low != low ||
      old.current != current ||
      old.color != color;
}

class InvestingTab extends StatefulWidget {
  const InvestingTab({super.key, required this.onExit});
  // 2026-08-31: the empty welcome screen hides the app's own bottom nav bar
  // (see dashboard_preview.dart's bottomNavigationBar condition) so it reads
  // as a full-bleed screen, same as the Grynieji/Kvitas intro. With the nav
  // bar gone there is no other way back to Home, so the welcome screen's own
  // close (X) button calls this to switch the outer tab back itself.
  final VoidCallback onExit;
  @override
  State<InvestingTab> createState() => _InvestingTabState();
}

class _InvestingTabState extends State<InvestingTab> {
  final List<Map<String, dynamic>> _holdings = DashboardStore.investments();
  // symbol -> quote data ({'price','prevClose','history'}), or null while
  // loading, absent entirely if the fetch failed (shows a retry state).
  final Map<String, Map<String, dynamic>?> _quotes = {};
  final Set<String> _failed = {};

  @override
  void initState() {
    super.initState();
    for (final h in _holdings) {
      _fetchQuote(h['symbol'] as String);
    }
    // 2026-09-01: without this, prices computed via _eurFieldOf stayed
    // wrong (or blank, after the fix just above) until something ELSE
    // triggered a rebuild — the real FX rate landing a few seconds after
    // launch was never itself a reason to redraw. This is exactly what
    // FxRates.rates (a ValueNotifier) exists for.
    FxRates.instance.rates.addListener(_onFxRatesChanged);
  }

  void _onFxRatesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FxRates.instance.rates.removeListener(_onFxRatesChanged);
    super.dispose();
  }

  Future<void> _fetchQuote(String symbol) async {
    _failed.remove(symbol);
    final q = await StockService.instance.quote(symbol);
    if (!mounted) return;
    setState(() {
      if (q == null) {
        _failed.add(symbol);
      } else {
        // 2026-09-01: real bug, found in audit — only the TOP of this
        // function cleared `_failed`, not this success branch. Two
        // concurrent fetches for the same symbol (e.g. a duplicate ticker
        // in _holdings, both fetched from initState's loop) could race: an
        // earlier call's failure lands in `_failed` AFTER a later call's
        // success already ran, leaving both `_failed.contains(symbol)` and
        // `_quotes[symbol] != null` true at once — the row shows "Bandyti
        // vėl" while the total silently already counts it. A success is
        // authoritative regardless of arrival order, so it always clears
        // any stale failure mark here too, not just at the top.
        _failed.remove(symbol);
        _quotes[symbol] = q;
      }
    });
  }

  Future<void> _save() async {
    await DashboardStore.setInvestments(_holdings);
  }

  // 2026-09-01: real bug, found in audit — FxRates.rateFor('USD') silently
  // returns 1.0 (its own documented "soft failure" contract) whenever the
  // real rate hasn't loaded yet or the fetch failed, which this function
  // used to divide by directly. That doesn't fail soft here — it prices a
  // $150 stock as €150.00 with total confidence, off by the whole EUR/USD
  // spread, with no visual difference from a correct number. Using
  // hasRateFor's explicit check instead: no real rate yet is treated the
  // exact same way as "no quote yet" (q == null already returns 0 above) —
  // every existing caller already has to tolerate a transient 0 while
  // things load, so this reuses that same, already-correct contract rather
  // than inventing a new one.
  double _eurFieldOf(String symbol, String field) {
    final q = _quotes[symbol];
    final usd = (q?[field] as num?)?.toDouble() ?? 0;
    if (!FxRates.instance.hasRateFor('USD')) return 0;
    final usdRate = FxRates.instance.rateFor('USD');
    return usdRate > 0 ? usd / usdRate : 0;
  }

  double _eurPriceOf(String symbol) => _eurFieldOf(symbol, 'price');
  double _eurPrevCloseOf(String symbol) => _eurFieldOf(symbol, 'prevClose');
  double _eurOpenOf(String symbol) => _eurFieldOf(symbol, 'open');
  double _eurHighOf(String symbol) => _eurFieldOf(symbol, 'high');
  double _eurLowOf(String symbol) => _eurFieldOf(symbol, 'low');

  Future<void> _addHolding() async {
    final result =
        await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddHoldingSheet(),
    );
    if (result == null) return;
    setState(() => _holdings.add(result));
    await _save();
    _fetchQuote(result['symbol'] as String);
  }

  Future<void> _removeHolding(Map<String, dynamic> h) async {
    setState(() => _holdings.remove(h));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    const p = _Pal();
    // Fixed dark palette (see _Pal's own doc) → the status bar needs to be
    // forced light (white icons) here too, independent of the app's actual
    // theme setting, or the clock/battery icons go invisible-dark-on-dark.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: p.bg,
        body: _holdings.isEmpty
            ? _emptyIntro(p)
            : SafeArea(
                bottom: false,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    _header(p),
                    const SizedBox(height: 4),
                    _totalCard(p),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: p.hair),
                    for (final h in _holdings) _holdingRow(p, h),
                    const SizedBox(height: 18),
                    _addButton(p),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(_Pal p) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
        child: Row(children: [
          Text(tr('Investicijos'),
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                  letterSpacing: -0.5)),
        ]),
      );

  /// First-run welcome screen — a full-bleed hero photo with the copy sitting
  /// directly on the photo's own darkened bottom edge (a gradient fade, not a
  /// separate card below it), matching the app's onboarding pages rather than
  /// the card-based empty states used elsewhere in the dashboard. Deliberately
  /// NOT wrapped in the outer SafeArea (see build()) — the image needs to run
  /// edge-to-edge under the status bar; only the text block below insets for
  /// the safe area.
  Widget _trustRow(_Pal p, IconData icon, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: p.blueSoft, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 14.5, color: p.blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFFE4E1EC))),
          ),
        ]),
      );

  Widget _emptyIntro(_Pal p) => LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Shifted up — this photo's own top ~26% is plain black before
              // the bull/bear art starts, and cover (image/box aspect are
              // near-identical) shows almost the whole photo, so that empty
              // stretch was reported as wasted space at the top. Unlike the
              // earlier chart photo (whose top had real content, so any shift
              // left a visible seam), this photo's top is flat black either
              // side of the crop line — so shifting the art up is safe: the
              // strip it exposes at the bottom is the SAME flat black,
              // covered by the gradient/background below anyway.
              Positioned(
                // 2026-08-31: was `height: h` — left the box's bottom edge
                // 15% short of the screen's own bottom, exposing a solid
                // block of the raw background there. That gap used to sit
                // behind the bottom nav bar (invisible), which is now hidden
                // on this screen (see dashboard_preview.dart's
                // bottomNavigationBar condition) — so the gap itself needed
                // fixing, not just something that happened to hide it.
                top: -h * 0.15,
                left: 0,
                right: 0,
                height: h * 1.15,
                child: Image.asset('assets/onboarding/investing_intro_bg.png',
                    fit: BoxFit.cover),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  // 2026-08-29: was darkening from as early as 22% down,
                  // reaching 90% opacity by 38% — right where the bull/bear
                  // art itself sits, so the whole photo read as washed-out
                  // and dim next to the crisp, saturated original (reported,
                  // real — a side-by-side comparison against the source
                  // file). Now stays almost fully bright through 30% (only
                  // a light 12% tint), then ramps fast into solid right
                  // before the text starts at 46%, so the art keeps its own
                  // vividness and only the text's own backdrop gets dark.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.30, 0.40, 0.46, 1.0],
                    colors: [
                      p.bg.withValues(alpha: 0),
                      p.bg.withValues(alpha: 0.12),
                      p.bg.withValues(alpha: 0.85),
                      p.bg,
                      p.bg,
                    ],
                  ),
                ),
              ),
              // 2026-08-31: with the outer bottom nav bar now hidden while
              // this welcome screen shows (see dashboard_preview.dart), this
              // is the ONLY way back to Home — kept bright red specifically
              // so it reads as "the way out", not just a generic dismiss.
              Positioned(
                top: 8,
                right: 12,
                child: SafeArea(
                  bottom: false,
                  child: GestureDetector(
                    onTap: widget.onExit,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE0334D),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
              // Anchored by a fixed FRACTION of the screen height, not the
              // bottom edge — bottom-anchoring left a long stretch of empty
              // photo between the chart artwork and the text. Two short
              // trust lines were added below the subtitle so this block
              // reads as deliberately composed, not just stretched to fill
              // space.
              // top-only (no explicit height/bottom) — the child gets a LOOSE
              // height constraint and sizes to its own content, so bigger
              // copy can never trigger a hard overflow error; Stack's own
              // default clip just trims it if it ever ran past the screen.
              Positioned(
                top: h * 0.46,
                left: 24,
                right: 24,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Investicijos'),
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: p.blue)),
                      const SizedBox(height: 10),
                      Text(tr('Turi investavęs į kryptovaliutą ar akcijas?'),
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.16,
                              letterSpacing: -0.3,
                              color: p.ink)),
                      const SizedBox(height: 10),
                      Text(
                          tr('Sek savo akcijas bei kriptovaliutą ir matyk jų pokyčius realiu laiku.'),
                          style: TextStyle(fontSize: 16, height: 1.42, color: p.muted)),
                      const SizedBox(height: 14),
                      _trustRow(p, Icons.trending_up_rounded,
                          tr('Tikros rinkos kainos, konvertuotos į eurus')),
                      _trustRow(p, Icons.lock_outline_rounded,
                          tr('Tik sekimas — jokių sujungimų su brokeriu')),
                      _trustRow(p, Icons.category_rounded,
                          tr('Tinka ir akcijoms, ir kriptovaliutai')),
                      _trustRow(p, Icons.dashboard_customize_rounded,
                          tr('Viskas vienoje vietoje su tavo finansais')),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _addHolding,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: p.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15.5),
                          ),
                          child: Text(tr('Pridėti pirmą investiciją')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                            tr('Kaina gali vėluoti kelias minutes nuo tikros rinkos kainos.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: p.faint)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );

  Widget _totalCard(_Pal p) {
    double totalValue = 0, totalPrevValue = 0, totalOpen = 0, totalHigh = 0, totalLow = 0;
    var anyLoaded = false;
    // 2026-08-28: this used to gate the spinner on `anyLoaded` alone — if
    // EVERY holding's fetch failed (the real bug: stock_quote required auth,
    // so any build without a real signed-in session rejected every single
    // quote), anyLoaded never became true and the spinner ran forever with
    // no way out. `settled` tracks "every holding has either a quote or a
    // recorded failure", so the card always resolves to SOME state.
    var settled = true;
    for (final h in _holdings) {
      final sym = h['symbol'] as String;
      if (_quotes[sym] != null) {
        anyLoaded = true;
        final shares = (h['shares'] as num).toDouble();
        totalValue += shares * _eurPriceOf(sym);
        totalPrevValue += shares * _eurPrevCloseOf(sym);
        totalOpen += shares * _eurOpenOf(sym);
        totalHigh += shares * _eurHighOf(sym);
        totalLow += shares * _eurLowOf(sym);
      } else if (!_failed.contains(sym)) {
        settled = false;
      }
    }
    final change = totalValue - totalPrevValue;
    final changePct = totalPrevValue > 0 ? (change / totalPrevValue * 100) : 0;
    final up = change >= 0;
    // 2026-08-28: matches "01 Robinhood classic" faithfully now, per
    // explicit request — a genuinely dark trading-app look (see _Pal's own
    // doc), so the line is back to semantic green/red rather than the
    // forced-white compromise the blue-gradient version needed. On this
    // near-black background either colour has excellent contrast on its
    // own; there's no "blends into blue" problem to work around anymore.
    final changeColor = up ? _Pal.good : _Pal.bad;
    // No separate card/gradient/shadow here — the reference is one
    // continuous dark canvas from the portfolio number straight into the
    // holdings list below (a Divider marks the seam, not a box).
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Portfelio vertė'),
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.faint)),
      const SizedBox(height: 12),
      if (!settled)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: p.purple),
            ),
          ),
        )
      else if (!anyLoaded)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(children: [
            Icon(Icons.wifi_off_rounded, size: 18, color: p.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('Nepavyko įkelti kainų — patikrink ryšį ir bandyk vėl.'),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.muted)),
            ),
          ]),
        )
      else ...[
        Text(Money.format(totalValue),
            style: TextStyle(
                fontSize: 42, fontWeight: FontWeight.w800, color: p.ink, letterSpacing: -0.8)),
        const SizedBox(height: 8),
        Row(children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 14, color: changeColor),
          const SizedBox(width: 3),
          Text(
              '${Money.format(change.abs())} (${changePct.abs().toStringAsFixed(1)}%) ${tr('šiandien')}',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: changeColor)),
        ]),
        // 2026-09-01: real bug, found in audit — a holding whose quote
        // permanently failed to load was just silently left out of
        // totalValue/change with zero visual cue, so the portfolio number
        // read as complete when it wasn't. _failed already tracks exactly
        // which symbols that is (each row's own "Bandyti vėl" state) — this
        // just surfaces the SAME fact once more at the total, where it's
        // most likely to be misread as "this is everything".
        if (_failed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.error_outline_rounded, size: 13, color: p.faint),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                    _failed.length == 1
                        ? tr('1 pozicija neįtraukta — nepavyko gauti kainos')
                        : '${_failed.length} ${tr('pozicijos neįtrauktos — nepavyko gauti kainų')}',
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: p.faint)),
              ),
            ]),
          ),
        SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(
            painter: _PortfolioTodayChartPainter(
              open: totalOpen,
              high: totalHigh,
              low: totalLow,
              current: totalValue,
              color: changeColor,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          for (final label in const ['1D', '1W', '1M', '3M', 'VISI'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              // 2026-08-28: tapping 1W/1M/etc used to do literally nothing
              // — indistinguishable from a broken button. They stay
              // visually disabled (still no real data behind them — see
              // the painter's own doc), but now say so instead of going
              // silent.
              child: GestureDetector(
                onTap: label == '1D'
                    ? null
                    : () {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                              content:
                                  Text(tr('Netrukus — kol kas turime tik šiandienos kainą.')),
                              duration: const Duration(seconds: 2)));
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: label == '1D' ? p.soft : null,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: label == '1D' ? p.ink : p.faint)),
                ),
              ),
            ),
        ]),
      ],
    ]);
  }

  Widget _addButton(_Pal p) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: GestureDetector(
          onTap: _addHolding,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.hair)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_rounded, size: 21, color: p.blue),
              const SizedBox(width: 8),
              Text(tr('Pridėti akciją, kriptovaliutą'),
                  style: TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700, color: p.blue)),
            ]),
          ),
        ),
      );

  Widget _holdingRow(_Pal p, Map<String, dynamic> h) {
    final symbol = h['symbol'] as String;
    final name = h['name'] as String;
    final domain = h['domain'] as String;
    final shares = (h['shares'] as num).toDouble();
    final loading = !_quotes.containsKey(symbol) && !_failed.contains(symbol);
    final failed = _failed.contains(symbol);
    final price = _eurPriceOf(symbol);
    final prevClose = _eurPrevCloseOf(symbol);
    final value = shares * price;
    final change = shares * (price - prevClose);
    final changePct = prevClose > 0 ? ((price - prevClose) / prevClose * 100) : 0;
    final up = change >= 0;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _HoldingDetailScreen(
          holding: h,
          quote: _quotes[symbol],
          onDelete: () {
            Navigator.pop(context);
            _removeHolding(h);
          },
        ),
      )),
      // 2026-08-28: was its own bordered card per row — the "01" reference
      // is thin, borderless rows separated by a hairline, not a stack of
      // boxes. Matches that now that the whole tab is one dark canvas.
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hair))),
        child: Row(children: [
          CategoryIcon(
              icon: Icons.show_chart_rounded,
              color: p.purple,
              size: 40,
              circle: false,
              merchant: name,
              domain: domain),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: p.ink)),
                const SizedBox(height: 2),
                Text('${_fmtShares(shares)} ${tr('vnt.')}',
                    style: TextStyle(fontSize: 12.5, color: p.muted)),
              ],
            ),
          ),
          if (loading)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.purple),
            )
          else if (failed)
            GestureDetector(
              onTap: () => _fetchQuote(symbol),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh_rounded, size: 16, color: p.faint),
                const SizedBox(width: 4),
                Text(tr('Bandyti vėl'),
                    style: TextStyle(fontSize: 12.5, color: p.faint)),
              ]),
            )
          else
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Money.format(value),
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: p.ink)),
              const SizedBox(height: 2),
              Text(
                  '${up ? '+' : ''}${changePct.toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: up ? _Pal.good : _Pal.bad)),
            ]),
        ]),
      ),
    );
  }

  static String _fmtShares(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

// ── add-holding sheet: pick from the catalog, enter share count ────────────
class _AddHoldingSheet extends StatefulWidget {
  const _AddHoldingSheet();
  @override
  State<_AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends State<_AddHoldingSheet> {
  // Search results are ({symbol, name}) whether they came from the live
  // Finnhub search or the static "popular" list shown before typing — one
  // shape either way. _picked additionally carries a domain once resolved
  // (immediate for the static list, one extra call for a search result —
  // see _resolveDomain).
  ({String symbol, String name})? _picked;
  String? _domain;
  bool _resolvingDomain = false;

  // 2026-08-28: "kartais žmogus nežino kiek akcijų turi" — let them say
  // "how much I paid" instead and back into the share count from the
  // current price, fetched the same moment the logo is (see _pick).
  bool _byAmount = false;
  double? _priceEur;
  bool _loadingPrice = false;
  final TextEditingController _amount = TextEditingController();

  final TextEditingController _search = TextEditingController();
  final TextEditingController _shares = TextEditingController();
  List<({String symbol, String name})> _results = [];
  bool _searching = false;
  Timer? _debounce;

  // Popular stocks first, then popular cryptos — the default list shown
  // before the user types anything.
  static final List<({String symbol, String name})> _defaults = [
    for (final s in kStockCatalog) (symbol: s.symbol, name: s.name),
    for (final c in kCryptoCatalog) (symbol: c.symbol, name: c.name),
  ];

  /// Crypto isn't covered by live search (see stock_catalog.dart's doc) — a
  /// query matches this small local list by name or symbol instead. Cheap
  /// enough to run on every keystroke (15 entries, no network).
  List<({String symbol, String name})> _cryptoMatches(String q) {
    final needle = q.toLowerCase();
    return [
      for (final c in kCryptoCatalog)
        if (c.name.toLowerCase().contains(needle) ||
            c.symbol.toLowerCase().contains(needle))
          (symbol: c.symbol, name: c.name),
    ];
  }

  @override
  void initState() {
    super.initState();
    _results = _defaults;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _shares.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _results = _defaults;
        _searching = false;
      });
      return;
    }
    // Crypto matches show immediately (local, no network) — the live stock
    // search below them arrives a beat later.
    setState(() {
      _results = _cryptoMatches(q);
      _searching = true;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final res = await StockService.instance.search(q);
      if (!mounted) return;
      setState(() {
        _results = [
          ..._cryptoMatches(q),
          for (final r in res) (symbol: r['symbol']!, name: r['name']!),
        ];
        _searching = false;
      });
    });
  }

  // The catalog symbol format ('BINANCE:BTCUSDT') is Finnhub's own, not
  // something to show a user — strips it down to what they'd recognise.
  static String _displaySymbol(String symbol) {
    final withoutExchange = symbol.contains(':') ? symbol.split(':').last : symbol;
    return withoutExchange.endsWith('USDT')
        ? withoutExchange.substring(0, withoutExchange.length - 4)
        : withoutExchange;
  }

  Future<void> _pick(({String symbol, String name}) s) async {
    // Both static catalogs already carry a known-good domain — skip the
    // extra network round trip for those, matching what worked before.
    // Only a LIVE search result (a real stock search hit, never crypto —
    // crypto always comes from the local list) needs stock_profile.
    StockInfo? catalogMatch;
    for (final c in [...kStockCatalog, ...kCryptoCatalog]) {
      if (c.symbol == s.symbol) {
        catalogMatch = c;
        break;
      }
    }
    setState(() {
      _picked = s;
      _domain = catalogMatch?.domain;
      _resolvingDomain = catalogMatch == null;
      _priceEur = null;
    });
    _fetchPrice(s.symbol);
    if (catalogMatch == null) {
      final domain = await StockService.instance.domainFor(s.symbol);
      if (!mounted || _picked?.symbol != s.symbol) return;
      setState(() {
        _domain = domain;
        _resolvingDomain = false;
      });
    }
  }

  Future<void> _fetchPrice(String symbol) async {
    setState(() => _loadingPrice = true);
    final q = await StockService.instance.quote(symbol);
    if (!mounted || _picked?.symbol != symbol) return;
    final usd = (q?['price'] as num?)?.toDouble();
    // 2026-09-01: real bug, found in audit — this is the MOST dangerous of
    // the three FX-fallback spots: in "Suma (€)" mode the share count saved
    // to the holding is computed from _priceEur ONCE, here, and never
    // recomputed — a stale/missing-rate window doesn't just mis-DISPLAY a
    // number, it permanently bakes a wrong share count into what gets
    // persisted. hasRateFor's explicit check (instead of trusting
    // rateFor's soft 1.0 fallback) means a not-yet-loaded rate correctly
    // falls into the SAME "null price" branch _priceEur already has — the
    // existing "Nepavyko gauti dabartinės kainos" / save-blocked state
    // below already handles that correctly, this just stops a fake 1.0
    // rate from slipping past it as if it were real.
    final usdRate = FxRates.instance.rateFor('USD');
    final hasRate = FxRates.instance.hasRateFor('USD');
    setState(() {
      _priceEur = (usd != null && usd > 0 && hasRate && usdRate > 0)
          ? usd / usdRate
          : null;
      _loadingPrice = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const p = _Pal();
    // 2026-08-28 rework, per explicit correction ("X yra pasislėpęs už safe
    // zonos" — twice). The previous version sized itself to its CONTENT
    // (mainAxisSize.min) and got pushed up bodily by the keyboard inset —
    // once a tall results list plus the keyboard together exceeded the
    // screen height, the title bar and close X went right off the top
    // edge, under the status bar, exactly the bug reported. A FIXED height
    // (85% of the screen, keyboard-independent) means the title bar always
    // sits at the same safe position no matter what the keyboard or the
    // results list are doing — the keyboard inset is absorbed INSIDE, by
    // the scrollable body's own bottom padding, never by resizing or
    // repositioning this outer sheet.
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.85;
    return SizedBox(
      height: sheetHeight,
      child: Container(
        decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
              width: 40,
              height: 4,
              decoration:
                  BoxDecoration(color: p.faint, borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(children: [
              Text(_picked == null ? tr('Pridėti akciją, kriptovaliutą') : tr('Kiek turi?'),
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: p.ink)),
              const Spacer(),
              GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close_rounded, color: p.faint)),
            ]),
          ),
          Expanded(
            child: _picked == null ? _pickerBody(p) : _sharesBody(p),
          ),
        ]),
      ),
    );
  }

  Widget _pickerBody(_Pal p) {
    final results = _results;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: p.soft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.hair)),
          child: Row(children: [
            Icon(Icons.search_rounded, size: 18, color: p.faint),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _search,
                // 2026-08-28: was autofocus: true — the keyboard used to pop
                // up the instant this sheet opened, before the user asked
                // for it. Now it only appears once they actually tap the
                // field, like every other search box.
                onChanged: _onSearchChanged,
                style: TextStyle(fontSize: 15.5, color: p.ink),
                // 2026-08-28: the app's shared InputDecorationTheme paints
                // its own coloured focusedBorder AND its own fillColor for
                // real form fields — `border: InputBorder.none` alone
                // doesn't override either, so this field showed a visibly
                // different-shaded rectangle (the theme's own fill) nested
                // inside this Container's own background the moment it
                // rendered. filled: false turns that fill off entirely, so
                // only this Container's own colour shows.
                decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    // 2026-08-28: live global search now (any stock, not a
                    // fixed list) — see stock_search in functions/main.py.
                    hintText: tr('Ieškok pvz. Tesla, Apple...'),
                    hintStyle: TextStyle(color: p.faint)),
              ),
            ),
            if (_searching)
              SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2, color: p.purple)),
          ]),
        ),
      ),
      if (_search.text.trim().isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(tr('Populiariausios'),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: p.faint)),
          ),
        ),
      Expanded(
        // 2026-08-28: was a ConstrainedBox(maxHeight: 50% of screen) inside
        // a mainAxisSize.min Column — sized itself independent of the
        // keyboard, so keyboard + this list together could exceed the
        // sheet's own (now fixed) height. Expanded fills exactly what's
        // left after the search bar, and the keyboard's own inset is added
        // as bottom padding below instead, so the last row scrolls clear
        // of the keyboard rather than the whole sheet growing past it.
        child: results.isEmpty && !_searching
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Text(tr('Nieko nerasta.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted)))
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(10, 0, 10, keyboardInset + 18),
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final s = results[i];
                  // A catalog entry (popular stock, or ANY crypto match —
                  // crypto never comes from live search) already carries a
                  // real domain, free — show its real logo immediately, not
                  // just after picking. A live search hit with no known
                  // domain yet gets a ticker-initials badge instead of a
                  // vague chart icon, so it reads as "this symbol, no logo
                  // yet" rather than "broken".
                  String? knownDomain;
                  for (final c in [...kStockCatalog, ...kCryptoCatalog]) {
                    if (c.symbol == s.symbol) {
                      knownDomain = c.domain;
                      break;
                    }
                  }
                  return ListTile(
                    onTap: () => _pick(s),
                    leading: knownDomain != null
                        ? CategoryIcon(
                            icon: Icons.show_chart_rounded,
                            color: p.purple,
                            size: 40,
                            circle: false,
                            merchant: s.name,
                            domain: knownDomain)
                        : _TickerBadge(symbol: _displaySymbol(s.symbol), pal: p),
                    title: Text(s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: p.ink)),
                    subtitle: Text(_displaySymbol(s.symbol),
                        style: TextStyle(fontSize: 12.5, color: p.muted)),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _modeChip(_Pal p,
      {required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.blueSoft : p.soft,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: selected ? p.blue : p.hair),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? p.blue : p.muted)),
      ),
    );
  }

  String _amountHelperText(_Pal p) {
    if (_loadingPrice) return tr('Kraunama kaina...');
    if (_priceEur == null || _priceEur! <= 0) return tr('Nepavyko gauti dabartinės kainos.');
    final amt = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (amt == null || amt <= 0) {
      return '${tr('Dabartinė kaina')}: ${Money.format(_priceEur!)}';
    }
    final shares = amt / _priceEur!;
    return '≈ ${_InvestingTabState._fmtShares(shares)} ${tr('vnt.')} (${Money.format(_priceEur!)}/${tr('vnt.')})';
  }

  Widget _sharesBody(_Pal p) {
    final s = _picked!;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    // SingleChildScrollView (not a plain Padding) so the numeric keyboard
    // showing (autofocus on the shares field) can't cover the "Pridėti"
    // button below it — same fixed-sheet-height reasoning as build()'s own
    // doc: the keyboard inset is absorbed here, not by moving the sheet.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 6, 18, 22 + keyboardInset),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _resolvingDomain
              ? Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: p.purpleSoft, borderRadius: BorderRadius.circular(15)),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: p.purple)),
                )
              : CategoryIcon(
                  icon: Icons.show_chart_rounded,
                  color: p.purple,
                  size: 46,
                  circle: false,
                  merchant: s.name,
                  domain: _domain),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.w800, color: p.ink)),
              Text(_displaySymbol(s.symbol), style: TextStyle(fontSize: 12.5, color: p.muted)),
            ]),
          ),
          GestureDetector(
            onTap: () => setState(() => _picked = null),
            child: Text(tr('Keisti'),
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: p.blue)),
          ),
        ]),
        const SizedBox(height: 22),
        // 2026-08-28: "kartais žmogus nežino kiek akcijų turi" — a toggle
        // between "I know the share count" and "I know what I paid", the
        // second backing into shares via the price fetched in _pick.
        Row(children: [
          _modeChip(p, label: tr('Kiekis'), selected: !_byAmount,
              onTap: () => setState(() => _byAmount = false)),
          const SizedBox(width: 8),
          _modeChip(p, label: tr('Suma (€)'), selected: _byAmount,
              onTap: () => setState(() => _byAmount = true)),
        ]),
        const SizedBox(height: 16),
        Text(_byAmount ? tr('Už kiek pirkai?') : tr('Kiek akcijų turi?'),
            style: TextStyle(fontSize: 13.5, color: p.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: p.soft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.hair)),
          child: TextField(
            key: ValueKey(_byAmount),
            controller: _byAmount ? _amount : _shares,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            onChanged: _byAmount ? (_) => setState(() {}) : null,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.ink),
            decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '0',
                suffixText: _byAmount ? '€' : null,
                suffixStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.muted)),
          ),
        ),
        if (_byAmount) ...[
          const SizedBox(height: 8),
          Text(_amountHelperText(p), style: TextStyle(fontSize: 12.5, color: p.faint)),
        ],
        const SizedBox(height: 22),
        GestureDetector(
          onTap: () {
            double n;
            if (_byAmount) {
              final amt = double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
              if (amt <= 0 || _priceEur == null || _priceEur! <= 0) return;
              n = amt / _priceEur!;
            } else {
              n = double.tryParse(_shares.text.replaceAll(',', '.')) ?? 0;
            }
            if (n <= 0) return;
            Navigator.pop(context, {
              'symbol': s.symbol,
              'name': s.name,
              'domain': _domain ?? '',
              'shares': n,
              'addedAt': DateTime.now().toIso8601String(),
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: p.blue, borderRadius: BorderRadius.circular(14)),
            child: Text(tr('Pridėti'),
                style: const TextStyle(
                    fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// ── holding detail: hero + history chart ────────────────────────────────────
class _HoldingDetailScreen extends StatelessWidget {
  const _HoldingDetailScreen(
      {required this.holding, required this.quote, required this.onDelete});
  final Map<String, dynamic> holding;
  final Map<String, dynamic>? quote;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const p = _Pal();
    final name = holding['name'] as String;
    final domain = holding['domain'] as String;
    final shares = (holding['shares'] as num).toDouble();
    // See _InvestingTabState._eurFieldOf's own doc — same fallback-1.0 bug,
    // fixed the same way: hasRateFor gates it instead of trusting rateFor's
    // soft fallback, so a not-yet-loaded rate shows 0 (a state every price
    // reader here already has to tolerate) instead of a wrong confident
    // number.
    final hasRate = FxRates.instance.hasRateFor('USD');
    final usdRate = FxRates.instance.rateFor('USD');
    final priceUsd = (quote?['price'] as num?)?.toDouble() ?? 0;
    final prevUsd = (quote?['prevClose'] as num?)?.toDouble() ?? 0;
    final price = (hasRate && usdRate > 0) ? priceUsd / usdRate : 0.0;
    final prevClose = (hasRate && usdRate > 0) ? prevUsd / usdRate : 0.0;
    final value = shares * price;
    final change = shares * (price - prevClose);
    final changePct = prevClose > 0 ? ((price - prevClose) / prevClose * 100) : 0;
    final up = change >= 0;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        foregroundColor: p.ink,
        title: Text(name, style: TextStyle(fontWeight: FontWeight.w800, color: p.ink)),
        actions: [
          IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded, color: p.faint)),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Center(
              child: CategoryIcon(
                  icon: Icons.show_chart_rounded,
                  color: p.purple,
                  size: 64,
                  circle: false,
                  merchant: name,
                  domain: domain),
            ),
            const SizedBox(height: 14),
            if (quote == null)
              Center(
                  child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: CircularProgressIndicator(color: p.purple),
              ))
            else ...[
              Center(
                child: Text(Money.format(value),
                    style: TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w800, color: p.ink)),
              ),
              const SizedBox(height: 6),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 16, color: up ? _Pal.good : _Pal.bad),
                  const SizedBox(width: 3),
                  Text(
                      '${Money.format(change.abs())} (${changePct.abs().toStringAsFixed(1)}%) ${tr('šiandien')}',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: up ? _Pal.good : _Pal.bad)),
                ]),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: DS.e1),
                child: Column(children: [
                  _infoRow(p, tr('Kiek turi'), '${_InvestingTabState._fmtShares(shares)} ${tr('vnt.')}'),
                  Divider(height: 22, color: p.hair),
                  _infoRow(p, tr('Kaina už 1 vnt.'), Money.format(price)),
                  Divider(height: 22, color: p.hair),
                  _infoRow(p, tr('Vakarykštė kaina'), Money.format(prevClose)),
                ]),
              ),
              const SizedBox(height: 14),
              Text(tr('Kaina gali vėluoti kelias minutes nuo tikros rinkos kainos.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: p.faint, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(_Pal p, String label, String value) => Row(children: [
        Text(label, style: TextStyle(fontSize: 14, color: p.muted)),
        const Spacer(),
        Text(value,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.ink)),
      ]);
}

// 2026-08-28: the price-history chart that used to live here was removed —
// Finnhub's free tier returns "You don't have access to this resource" for
// both /stock/candle and /crypto/candle (historical OHLC is a paid-plan
// feature there), verified directly. See stock_quote.py's module doc for
// the free path back to a chart (record our own daily snapshot over time,
// rather than buying someone else's history).
