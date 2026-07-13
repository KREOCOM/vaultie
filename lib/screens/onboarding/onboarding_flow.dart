import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../app_prefs.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../user_session.dart';
import '../auth_screen.dart';
import '../bank_info_screen.dart';
import 'account_screen.dart';
import 'annual_bars_screen.dart';
import 'bank_scale_screen.dart';
import 'landing_screen.dart';
import 'paywall_screen.dart';
import 'reminders_screen.dart';
import 'subscription_stream_screen.dart';
import 'two_paths_screen.dart';

/// Phase-1 onboarding coordinator: a button-driven PageView through
/// landing → empathy → diagnostics → value → account → two paths → paywall.
/// Survey answers are collected in [answers] (stored locally later).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    this.initialPage = 0,
    this.debugNav = false,
  });

  /// Preview-only: jump straight to a screen (used by main_preview).
  final int initialPage;

  /// Preview-only: show a floating ‹ i/total › control to step through screens.
  final bool debugNav;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late final _controller = PageController(initialPage: widget.initialPage);
  final Map<String, Object> answers = {};
  late int _index = widget.initialPage;

  // Lazy so the preview harness (no Firebase) can render the flow without
  // constructing FirebaseAuth; only built when a sign-in button is tapped.
  late final _auth = AuthService();

  /// Path chosen on "Two paths": bank (→ paywall after account) vs manual
  /// (→ straight to the app). Remembered across the account screen.
  bool _bankPath = true;

  /// True while a social sign-in round-trip is in flight (blocks input, shows
  /// a spinner overlay).
  bool _authBusy = false;

  static const _twoPathsIndex = 5;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  void _animateTo(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // --- Auth (Google/Apple inline; email reuses the existing AuthScreen) ---

  Future<void> _authGoogle() => _social(_auth.signInWithGoogle,
      failMsg: _isLt ? 'Nepavyko prisijungti su Google.' : 'Google sign-in failed.');

  Future<void> _authApple() => _social(_auth.signInWithApple,
      failMsg: _isLt ? 'Nepavyko prisijungti su Apple.' : 'Apple sign-in failed.');

  /// Runs a social sign-in; on success continues the flow (bank → paywall,
  /// manual → dashboard). A null result means the user cancelled the picker.
  Future<void> _social(Future<Object?> Function() signIn,
      {required String failMsg}) async {
    if (_authBusy) return;
    setState(() => _authBusy = true);
    try {
      final cred = await signIn();
      if (cred == null) return; // cancelled
      if (!mounted) return;
      await _afterAccount();
    } catch (_) {
      if (mounted) _snack(failMsg);
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  /// Email path reuses the existing (fully wired) AuthScreen, which handles
  /// register/sign-in + email verification and lands on the dashboard. We mark
  /// onboarding done first so its post-login routing skips the old choice
  /// screen. (Phase 1: the email path doesn't thread through the new paywall.)
  Future<void> _authEmail() async {
    await _markOnboarded();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  /// After the account screen succeeds: bank path → paywall; manual → dashboard.
  Future<void> _afterAccount() async {
    if (_bankPath) {
      next(); // → paywall
    } else {
      await _finishOnboarding(bank: false, pro: false);
    }
  }

  /// Persists that onboarding + the start-choice are done, so the next launch
  /// goes straight to the dashboard instead of repeating onboarding.
  Future<void> _markOnboarded() async {
    await Hive.box(HiveBoxes.settings).put('onboarded', true);
    await AppPrefs.setOnboardingComplete(true);
  }

  /// Ends onboarding: scope the local vault to this account, then land on the
  /// bank flow. The green DashboardScreen is temporarily hidden (kept in code;
  /// final home decided later) — the only visible path is bank → new dashboard.
  Future<void> _finishOnboarding(
      {required bool bank, required bool pro}) async {
    await _markOnboarded();
    if (pro) {
      // Mock Pro grant (real entitlement comes from RevenueCat later).
      await Hive.box(HiveBoxes.settings).put('premium', true);
    }
    await ensureLocalDataForCurrentUser();
    if (!mounted) return;
    // Land straight on the bank intro (was: DashboardScreen with BankInfoScreen
    // pushed on top). `bank` is retained for when the manual path returns.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const BankInfoScreen()),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void next() {
    if (_index < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void back() {
    if (_index > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // Screens are appended here as they're built (Phase 1, screen by screen).
  List<Widget> get _pages => [
        LandingScreen(onStart: next, onHaveAccount: _authEmail),
        AnnualBarsScreen(onNext: next, onBack: back),
        SubscriptionStreamScreen(onNext: next, onBack: back),
        RemindersScreen(onNext: next, onBack: back),
        BankScaleScreen(onNext: next, onBack: back),
        TwoPathsScreen(
          onBank: () {
            _bankPath = true;
            next();
          },
          onManual: () {
            _bankPath = false;
            next();
          },
          onBack: back,
        ),
        AccountScreen(
          onGoogle: _authGoogle,
          onApple: _authApple,
          onEmail: _authEmail,
          onSignIn: _authEmail,
          onBack: back,
        ),
        PaywallScreen(
          onSubscribed: (_) => _finishOnboarding(bank: true, pro: true),
          onClose: () => _animateTo(_twoPathsIndex),
        ),
      ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageView = PageView(
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(), // button-only
      onPageChanged: (i) => setState(() => _index = i),
      children: _pages,
    );
    return Stack(
      children: [
        pageView,
        if (_authBusy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
        if (widget.debugNav)
          Positioned(
            right: 10,
            bottom: 10,
            child: _DebugNav(
              index: _index,
              total: _pages.length,
              onBack: back,
              onNext: next,
            ),
          ),
      ],
    );
  }
}

/// Preview-only floating navigator: ‹ current/total ›.
class _DebugNav extends StatelessWidget {
  const _DebugNav({
    required this.index,
    required this.total,
    required this.onBack,
    required this.onNext,
  });

  final int index;
  final int total;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left, color: Colors.white),
            ),
            Text('${index + 1}/$total',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
