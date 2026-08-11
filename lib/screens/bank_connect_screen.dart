import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../app_prefs.dart';
import '../content_theme.dart';
import '../i18n.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/banking_service.dart';
import '../services/dashboard_store.dart';
import '../services/feature_flags.dart';
import '../services/fx_rates.dart';
import '../user_session.dart';
import 'bank_callback_screen.dart';
import 'bank_how_it_works.dart';
import 'login_screen.dart';

/// Ensures one authorisation code is exchanged exactly once.
///
/// A bank can deliver its callback through BOTH channels at once: the in-session
/// ASWebAuthenticationSession the in-app flow is waiting on, AND the universal
/// link the deep-link handler listens for. Each then tries to complete the same
/// connection. The code is single-use — the first exchange connects the bank,
/// the second gets HTTP 422 and shows a spurious "couldn't finish" over a
/// connection that already succeeded (observed with SEB). Whichever path claims
/// the code first completes it; the other backs off silently.
class BankConnectClaim {
  BankConnectClaim._();
  static final Set<String> _claimed = <String>{};

  /// True the first time [code] is seen this session, false for every repeat.
  static bool claim(String code) => _claimed.add(code);
}

/// What [completeBankConnection] hands back: the fast dashboard to show now, the
/// background 12-month backfill to swap in later, and the raw scan for the
/// legacy import fallback.
typedef BankConnectionResult = ({
  Map<String, dynamic>? dash,
  Future<Map<String, dynamic>?>? deeper,
  BankScanResult scan,
});

/// Turns an authorisation [code] into a connected, saved dashboard.
///
/// Everything after we hold the code lives here so the two ways of getting one
/// — the in-app ASWebAuthenticationSession, and a universal-link return that
/// cold-launches the app — finish identically: fetch a fast 3-month scan,
/// record the connection, build a combined dashboard when more than one bank is
/// linked, persist it, and kick off the full 12-month backfill in the
/// background. Throws [BankingException] on failure; the caller shows it.
Future<BankConnectionResult> completeBankConnection(String code,
    {String? bank}) async {
  // The dashboard as it stood before this connect — used to make sure the
  // combined re-fetch below never overwrites it by dropping a bank we already had.
  final prevDash = DashboardStore.load();
  final scan = await BankingService.instance.finishBankAuth(
      code, aiEnrichment: AppPrefs.aiEnrichment, bank: bank, monthsBack: 3);
  final conn = scan.connection;
  final connAccounts = (((conn?['accounts'] as List?) ?? const [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList());
  // A consent that returned ZERO accounts must not create a connection: it would
  // increment bankCount with an empty account set, so every later refresh no-ops
  // (refs empty) and the user is stuck with a permanent empty "connected" bank
  // they can only clear via disconnect-all. Skip it; the caller shows the empty
  // result screen instead.
  // Read BEFORE addConnection, which is about to change it — this is what
  // tells "first bank ever" apart from "just added a second one".
  final wasFirstBank = DashboardStore.bankCount == 0;
  if (conn != null && connAccounts.isNotEmpty) {
    await DashboardStore.addConnection(
      bank: bank ?? conn['bank'] as String? ?? 'Bankas',
      sessionId: conn['sessionId'] as String?,
      accounts: connAccounts,
    );
    // The bank's own expiry date, so the user can be warned before it stops
    // answering. Recorded only for a connection that actually produced
    // accounts — the empty-consent case above is not access to anything.
    await DashboardStore.markConsentGranted(
      bank ?? conn['bank'] as String? ?? 'Bankas',
      conn['validUntil'] as String?,
    );
    // A Norwegian user connecting their first bank saw every figure in the
    // app — including their own kroner balance — converted to euros, because
    // the display currency defaults to EUR and nothing ever pointed it
    // anywhere else. Everything still SUMS in EUR underneath (fx.py: mixed
    // currencies cannot be added together, so a common base is not
    // optional) — this only changes what the base is display-side, using
    // the exact mechanism Settings' own "Bazinė valiuta" picker already
    // calls.
    //
    // Only on the FIRST bank, and only away from the untouched EUR default:
    // by the second bank the user has already seen and accepted whatever
    // currency the app opened in, and overriding it again would undo a
    // choice rather than make one for them. One tap in Settings reverses
    // this either way, so getting the guess wrong here is cheap.
    if (wasFirstBank && AppPrefs.currencyCode.value == 'EUR') {
      final detected = detectFirstBankCurrency(connAccounts);
      if (detected != null) await AppPrefs.setCurrencyCode(detected);
    }
  }
  Map<String, dynamic>? dash = scan.dash;
  // Set when the combined re-fetch came back missing a bank we already had (e.g.
  // a bank rate-limited us in the connect burst). We still SHOW that dash, but we
  // must not PERSIST it over the good one — the `deeper` refresh restores the full
  // set, and until then the last good save (with every bank) stays on disk.
  var combinedDroppedABank = false;
  if (DashboardStore.bankCount > 1) {
    try {
      final combined = await BankingService.instance.refreshDashboard(
          DashboardStore.accountRefs(),
          aiEnrichment: AppPrefs.aiEnrichment, monthsBack: 3);
      if (combined != null) {
        dash = combined;
        combinedDroppedABank =
            _banksOf(prevDash).difference(_banksOf(combined)).isNotEmpty;
      }
    } on BankingException {
      // keep the single-bank dash as a fallback
    }
  }
  if (dash != null && !combinedDroppedABank) {
    await DashboardStore.save(dash, bank: bank);
  }
  final deeper = (dash != null)
      ? BankingService.instance.refreshDashboard(DashboardStore.accountRefs(),
          aiEnrichment: AppPrefs.aiEnrichment, monthsBack: 6)
      : null;
  // The flow is finished — clear the pending marker either path set.
  await DashboardStore.setPendingConnect(null);
  return (dash: dash, deeper: deeper, scan: scan);
}

/// The majority non-EUR currency among a first bank connection's accounts, or
/// null if there isn't a real one to switch to (all EUR, no accounts, or the
/// one that "wins" isn't a code the app's currency picker actually carries a
/// name/symbol/live-rate for).
///
/// Majority by ACCOUNT COUNT, not balance — [accounts] here is connection-time
/// metadata ({uid, iban, name, currency}, from finish_bank_auth's response)
/// and carries no amount to weigh by. A Revolut connect returning one EUR
/// wallet and two NOK wallets picks NOK; imperfect for someone who actually
/// keeps most of their money in the one EUR wallet, but a reasonable guess for
/// a screen the user can flip in one tap either way.
///
/// EUR is counted like any other currency and wins ties: a Revolut connect
/// that hands back one EUR wallet and one SEK wallet in the SAME response
/// (Revolut returns every wallet from one consent at once, so there's no
/// real "connected first") used to switch away from EUR on a 1-1 tie, since
/// EUR was excluded from the count entirely and so could never win. EUR is
/// already the screen the user is looking at — a coin-flip switch away from
/// it is worse than a coin-flip switch into it, so only a STRICT non-EUR
/// majority moves the base currency.
@visibleForTesting
String? detectFirstBankCurrency(List<Map<String, dynamic>> accounts) {
  final counts = <String, int>{};
  for (final a in accounts) {
    final c = (a['currency'] as String? ?? '').toUpperCase();
    if (c.isNotEmpty) counts[c] = (counts[c] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final eur = counts['EUR'] ?? 0;
  final nonEur = counts.entries.where((e) => e.key != 'EUR').toList()
    ..sort((x, y) => y.value.compareTo(x.value));
  if (nonEur.isEmpty) return null; // all EUR — nothing to switch to
  final top = nonEur.first;
  if (top.value <= eur) return null; // EUR wins outright or ties
  // currencyByCode() falls back to the EUR entry for a code the picker
  // doesn't carry (e.g. an exotic wallet currency fx.py still prices for
  // totals) — comparing the resolved code back against `top` is what keeps
  // that silent fallback from being reported as a real match.
  return currencyByCode(top.key).code == top.key ? top.key : null;
}

/// The set of bank names present in a saved dashboard payload (lowercased), read
/// from its balance accounts. Used to detect a combined re-fetch that dropped a
/// previously-connected bank.
Set<String> _banksOf(Map<String, dynamic>? d) {
  final accts = ((d?['balance'] as Map?)?['accounts'] as List?) ?? const [];
  return accts
      .map((a) => ((a as Map)['bank'] as String?)?.toLowerCase().trim())
      .whereType<String>()
      .where((b) => b.isNotEmpty)
      .toSet();
}

/// A country Vaultie can list banks for (Enable Banking coverage).
class _Country {
  const _Country(this.code, this.flag, this.lt, this.en);
  final String code, flag, lt, en;
}

/// Pro-only flow: pick a country → pick a bank → approve inside an
/// ASWebAuthenticationSession → the session intercepts the
/// `vaultie://banking/callback` return → detect recurring payments.
class BankConnectScreen extends StatefulWidget {
  const BankConnectScreen({super.key});

  static const route = '/bank-connect';

  @override
  State<BankConnectScreen> createState() => _BankConnectScreenState();
}

enum _Phase { intro, country, loading, list, redirect, connecting, error }

class _BankConnectScreenState extends State<BankConnectScreen> {
  /// Starts on [_Phase.loading], not on the country picker.
  ///
  /// Enable Banking needs a country from us — /aspsps takes it as a parameter
  /// and start_auth requires it alongside the bank — but asking for it is a
  /// step almost nobody needs: the default is Lithuania and the chip at the top
  /// of the list changes it. The picker itself is untouched, just no longer the
  /// first thing between a person and their bank.
  /// First connection opens on [_Phase.intro] — the three-step explanation of
  /// what is about to happen. Someone adding a SECOND bank has already been
  /// through it, so they skip straight to the list.
  late _Phase _phase =
      DashboardStore.bankCount == 0 ? _Phase.intro : _Phase.loading;
  List<Bank> _banks = const [];
  String? _error;
  String? _connectingBank;
  Bank? _pendingBank; // shown on _Phase.redirect, then connected

  // Defaults to the device's own Region when Vaultie recognises it (checked
  // against the WHOLE locale preference list, same reasoning as
  // localeForRegion() in app_prefs.dart — a phone's Region often rides along
  // with a specific language variant a person picked once, e.g. "English
  // (United Kingdom)"). Falls back to Lithuania when nothing matches.
  //
  // Before this, every tester opened straight onto Lithuania regardless of
  // where they actually bank, and Enable Banking lists a country's OWN
  // "Swedbank"/"SEB" as a same-named but entirely separate bank from a
  // neighbouring country's — a Norwegian picking the Lithuanian Swedbank from
  // the un-switched default authenticated against the wrong bank entirely,
  // which just fails silently rather than reading as "wrong country".
  static _Country _defaultCountry() {
    final locales = WidgetsBinding.instance.platformDispatcher.locales;
    for (final l in locales) {
      final cc = l.countryCode;
      if (cc == null) continue;
      for (final c in _countries) {
        if (c.code == cc) return c;
      }
    }
    return _countries.first; // Lithuania
  }

  late _Country _country = _defaultCountry();
  final _countrySearch = TextEditingController();

  // Enable Banking coverage — Baltics + Nordics first, then the rest of Europe.
  static const _countries = <_Country>[
    _Country('LT', '🇱🇹', 'Lietuva', 'Lithuania'),
    _Country('LV', '🇱🇻', 'Latvija', 'Latvia'),
    _Country('EE', '🇪🇪', 'Estija', 'Estonia'),
    _Country('FI', '🇫🇮', 'Suomija', 'Finland'),
    _Country('SE', '🇸🇪', 'Švedija', 'Sweden'),
    _Country('NO', '🇳🇴', 'Norvegija', 'Norway'),
    _Country('DK', '🇩🇰', 'Danija', 'Denmark'),
    _Country('IS', '🇮🇸', 'Islandija', 'Iceland'),
    _Country('DE', '🇩🇪', 'Vokietija', 'Germany'),
    _Country('PL', '🇵🇱', 'Lenkija', 'Poland'),
    _Country('GB', '🇬🇧', 'Jungtinė Karalystė', 'United Kingdom'),
    _Country('IE', '🇮🇪', 'Airija', 'Ireland'),
    _Country('NL', '🇳🇱', 'Nyderlandai', 'Netherlands'),
    _Country('BE', '🇧🇪', 'Belgija', 'Belgium'),
    _Country('LU', '🇱🇺', 'Liuksemburgas', 'Luxembourg'),
    _Country('FR', '🇫🇷', 'Prancūzija', 'France'),
    _Country('ES', '🇪🇸', 'Ispanija', 'Spain'),
    _Country('PT', '🇵🇹', 'Portugalija', 'Portugal'),
    _Country('IT', '🇮🇹', 'Italija', 'Italy'),
    _Country('AT', '🇦🇹', 'Austrija', 'Austria'),
    _Country('CZ', '🇨🇿', 'Čekija', 'Czechia'),
    _Country('SK', '🇸🇰', 'Slovakija', 'Slovakia'),
    _Country('SI', '🇸🇮', 'Slovėnija', 'Slovenia'),
    _Country('HU', '🇭🇺', 'Vengrija', 'Hungary'),
    _Country('HR', '🇭🇷', 'Kroatija', 'Croatia'),
    _Country('RO', '🇷🇴', 'Rumunija', 'Romania'),
    _Country('BG', '🇧🇬', 'Bulgarija', 'Bulgaria'),
    _Country('GR', '🇬🇷', 'Graikija', 'Greece'),
    _Country('CY', '🇨🇾', 'Kipras', 'Cyprus'),
    _Country('MT', '🇲🇹', 'Malta', 'Malta'),
  ];

  @override
  void dispose() {
    _countrySearch.dispose();
    super.dispose();
  }

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  List<_Country> get _filteredCountries {
    final q = _countrySearch.text.trim().toLowerCase();
    if (q.isEmpty) return _countries;
    return _countries
        .where((c) =>
            c.lt.toLowerCase().contains(q) ||
            c.en.toLowerCase().contains(q) ||
            c.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadBanks(prefetch: _phase == _Phase.intro);
  }

  void _pickCountry(_Country c) {
    setState(() => _country = c);
    _loadBanks();
  }

  /// [prefetch] loads the list WITHOUT taking over the screen — used while the
  /// intro is being read, so tapping "Tęsti" opens a list that is already there
  /// instead of a spinner. Errors are held until the user actually asks for the
  /// list; failing at them while they are reading an explanation would be noise.
  Future<void> _loadBanks({bool prefetch = false}) async {
    // The kill-switch, finally connected to something. It was fetched from
    // Remote Config, updated in realtime, and read by nothing — flipping it in
    // the Firebase console changed precisely nothing in the app. This is the
    // one screen it needs to reach: during an Enable Banking outage, saying so
    // beats sending everyone into a flow that cannot succeed.
    if (!FeatureFlags.instance.bankingEnabled.value) {
      setState(() {
        _error = _isLt
            ? 'Banko prijungimas laikinai nepasiekiamas. Pabandyk vėliau.'
            : 'Bank connection is temporarily unavailable. Please try later.';
        if (!prefetch) _phase = _Phase.error;
      });
      return;
    }
    setState(() {
      if (!prefetch) _phase = _Phase.loading;
      _error = null;
    });
    try {
      final banks = await BankingService.instance.listBanks(country: _country.code);
      if (!mounted) return;
      setState(() {
        _banks = banks;
        if (!prefetch) _phase = _Phase.list;
      });
    } on BankingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        if (!prefetch) _phase = _Phase.error;
      });
    }
  }

  /// One step before leaving the app. Being thrown onto a bank's website with no
  /// warning is where people abandon — and where a careful person suspects a
  /// scam. This names the bank, shows its real logo and says what will happen.
  void _confirm(Bank bank) {
    if (_phase == _Phase.connecting) return;
    setState(() {
      _pendingBank = bank;
      _phase = _Phase.redirect;
    });
  }

  /// "You are about to leave for <bank>" — the last screen before the browser.
  ///
  /// Centred, and built around a hand-off: Vaultie's mark, an arrow, the bank's
  /// own. Left-aligned with the logo floating above it, this read as two
  /// unrelated things stacked; the pair with an arrow between them says what is
  /// actually happening in one glance, before the sentence is read.
  Widget _redirectView(Bank bank) {
    final lt = _isLt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _markTile(
                child: Image.asset('assets/icon/app_icon.png',
                    width: 64, height: 64, fit: BoxFit.cover),
                padded: false,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 22, color: Color(0xFF9FB0D8)),
              ),
              _bankLogoLarge(bank),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            lt ? 'Nukreipiame į ${bank.name}' : 'Taking you to ${bank.name}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -0.5,
                color: cxInk),
          ),
          const SizedBox(height: 12),
          Text(
            lt
                ? 'Dabar trumpam paliksi Vaultie ir atsidursi savo banke. Ten prisijungi ir patvirtini prieigą prie sąskaitos. Kai baigsi — automatiškai grįši atgal.'
                : "You'll leave Vaultie for a moment and land in your bank. Sign in there and approve access to your account. When you're done you'll come straight back.",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, height: 1.5, color: cxSubtle),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: cxCard,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 18, color: Color(0xFF9FB0D8)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lt
                      ? 'Prisijungimo duomenis įvedi tik savo banke. Vaultie jų nemato ir nesaugo.'
                      : 'You enter your credentials only at your bank. Vaultie never sees or stores them.',
                  style:
                      const TextStyle(fontSize: 12.5, height: 1.45, color: cxSubtle),
                ),
              ),
            ]),
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => _connect(bank),
              style: ElevatedButton.styleFrom(
                backgroundColor: VaultieColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(lt ? 'Prisijungti banke' : 'Continue to bank',
                  style: const TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _phase = _Phase.list),
            child: Text(lt ? 'Rinktis kitą banką' : 'Choose a different bank',
                style: const TextStyle(fontSize: 13.5, color: cxSubtle)),
          ),
        ],
      ),
    );
  }

  Widget _markTile({required Widget child, bool padded = true}) => Container(
        width: 64,
        height: 64,
        clipBehavior: Clip.antiAlias,
        padding: padded ? const EdgeInsets.all(9) : EdgeInsets.zero,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: child,
      );

  /// The bank's own mark. Enable Banking returns a logo for the banks people
  /// actually use; smaller ASPSPs sometimes have none, which is why the initial
  /// tile stays as a fallback rather than being deleted.
  Widget _bankLogoLarge(Bank bank) {
    final logo = bank.logo;
    final fallback = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: cxCard, borderRadius: BorderRadius.circular(18)),
      child: Text(
        bank.name.isNotEmpty ? bank.name.characters.first.toUpperCase() : '?',
        style: const TextStyle(
            fontSize: 27, fontWeight: FontWeight.w800, color: cxInk),
      ),
    );
    if (logo == null || logo.isEmpty) return fallback;
    return _markTile(
      child: Image.network(logo,
          fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback),
    );
  }

  Future<void> _connect(Bank bank) async {
    // Hard re-entrancy guard. The phase change below hides the bank list within
    // a frame, but two taps inside that frame — or during the await — started
    // two consent flows: two authorisation sessions at the bank, two entries
    // against its daily quota, and a second browser session iOS then refuses.
    if (_phase == _Phase.connecting) return;
    setState(() {
      _phase = _Phase.connecting;
      _connectingBank = bank.name;
      _error = null;
    });
    try {
      // Remember which bank this is BEFORE the browser opens: if it hands off to
      // its own app and the return cold-launches Vaultie, the callback carries
      // only a code, and the resume path recovers the label from here.
      await DashboardStore.setPendingConnect(bank.name, logo: bank.logo);
      final url = await BankingService.instance.startBankAuth(bank.name,
          country: bank.country.isNotEmpty ? bank.country : _country.code);
      // REVERTED (2026-08-11): tried ephemeralIntentFlags
      // (FLAG_ACTIVITY_NO_HISTORY) here to stop the Custom Tab falling back
      // to the bank's own page on a failed hand-off. On a MIUI device it
      // produced a WORSE, different symptom instead: `adb logcat` caught
      // WindowManagerShell entering `PipTransitionState(mState=exiting-pip…)`
      // for Chrome's CustomTabActivity — the tab shrinks into a small
      // floating Picture-in-Picture bubble rather than closing, hiding the
      // ALREADY-correct BankCallbackScreen underneath it. The deep link
      // hand-off itself was confirmed working the whole time (the app screen
      // was right, just visually obscured) — this flag change is what
      // triggered MIUI's PiP transition, not a fix for anything. Back to
      // flutter_web_auth_2's own default flags. If touching Custom Tab
      // launch flags again, verify with `adb logcat | grep PipTransitionState`
      // on a real MIUI device before trusting a screenshot alone — the
      // failure mode is easy to misread as "button doesn't work".
      final result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: kBankingCallbackScheme,
      );
      final code = BankingService.codeFromCallback(Uri.parse(result));
      if (code == null) {
        throw BankingException(_isLt
            ? 'Negavome prisijungimo kodo iš banko.'
            : 'The bank didn\'t return a sign-in code.');
      }
      // If the deep-link handler already claimed this code (the bank fired both
      // channels), let it finish — don't exchange the same single-use code
      // twice. Its BankCallbackScreen is on top and will land on the dashboard.
      if (!BankConnectClaim.claim(code)) {
        // Drop back to the list instead of returning mid-phase.
        //
        // The deep-link path got to the code first and its screen is now on top,
        // finishing the connection. This screen stayed frozen on "Opening
        // <bank>…" underneath it, so if the user ever came back here — or if the
        // callback screen closed — they found a spinner that would never resolve.
        if (mounted) setState(() => _phase = _Phase.list);
        return;
      }
      if (!mounted) return;
      // From here on, BankCallbackScreen owns everything — the SAME screen the
      // universal-link resume path uses. This flow used to show its own plain,
      // logo-less "analysing" spinner instead, so the exact same moment (a bank
      // just approved) looked completely different depending on which of the
      // two paths happened to complete it — that mismatch was read as "broken,
      // random logos/colours" by testers, when both were actually working, just
      // inconsistently dressed. One path, one screen, only the bank's own logo
      // changes.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => BankCallbackScreen(code: code)),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'CANCELED') {
        setState(() => _phase = _Phase.list);
      } else {
        setState(() {
          _error = _isLt
              ? 'Nepavyko prijungti banko.'
              : 'Could not connect the bank.';
          _phase = _Phase.error;
        });
      }
    } on BankingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _Phase.error;
      });
    }
    // No generic catch-all here anymore. Everything past a claimed code —
    // including the "bank approved but the data fetch itself threw" case this
    // used to guard against — is now BankCallbackScreen's job; it has its own
    // catch-all and its own visible error/retry state.
    //
    // Deliberately does NOT clear the pending-connect marker on any path here.
    // When a bank hands off to its own app, this session reports CANCELED —
    // but the connection isn't cancelled, it's continuing via the universal
    // link, and BankCallbackScreen still needs the bank name this marker
    // holds. It's overwritten at the start of the next connect and cleared on
    // success, so a stale marker after a real cancel is harmless.
  }

  /// Escape hatch when this screen is the whole stack (onboarding, or a
  /// wrong-account sign-in): sign out and return to the sign-in choices so the
  /// user isn't trapped. Only offered when there's no route beneath (see build).
  Future<void> _switchAccount() async {
    try {
      await AuthService().signOut();
      await onSignedOut();
    } catch (_) {
      // Best-effort — leaving the trap must still work.
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // From the bank list / error, "back" returns to country selection rather
    // than leaving the flow entirely.
    final dark = _phase == _Phase.redirect || _phase == _Phase.intro;
    final atRoot = _phase == _Phase.country;
    // Reached in two contexts: during onboarding the stack is empty (nowhere to
    // pop to — the old dead-end), while the in-app "+ add bank" flow pushes this
    // on top of the dashboard (a real route beneath). Offer an exit accordingly.
    final canPop = Navigator.of(context).canPop();
    return Theme(
      data: contentTheme(Theme.of(context)),
      child: Scaffold(
        // The trust screens are deep navy in BOTH themes (see cxBg): white copy
        // on the light theme's white background would be invisible.
        backgroundColor: dark ? cxBg : cBg,
        appBar: AppBar(
          backgroundColor: dark ? cxBg : null,
          foregroundColor: dark ? cxInk : null,
          leading: atRoot
              ? (canPop
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null)
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  // From the redirect screen, back means the bank list — the
                  // country picker is two steps behind and is not what was left.
                  onPressed: () => setState(() => _phase =
                      _phase == _Phase.redirect ? _Phase.list : _Phase.country),
                ),
          // No route beneath = onboarding/wrong-account: give a way out instead
          // of trapping the user until they delete the app.
          actions: (atRoot && !canPop)
              ? [
                  TextButton(
                    onPressed: _switchAccount,
                    child: Text(_isLt ? 'Kita paskyra' : 'Switch account'),
                  ),
                ]
              : null,
          title: Text(atRoot
              ? (_isLt ? 'Pasirink šalį' : 'Choose a country')
              : (_isLt ? 'Prijungti banką' : 'Connect your bank')),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.intro:
        return BankHowItWorks(onContinue: () {
          // The prefetch usually finished while this was being read.
          if (_banks.isNotEmpty && _error == null) {
            setState(() => _phase = _Phase.list);
          } else {
            setState(() => _phase = _Phase.loading);
            _loadBanks();
          }
        });
      case _Phase.redirect:
        return _redirectView(_pendingBank!);
      case _Phase.country:
        return _countryList();
      case _Phase.loading:
        return _busy(_isLt ? 'Kraunami bankai…' : 'Loading banks…');
      case _Phase.connecting:
        return _busy(_isLt
            ? 'Atveriamas ${_connectingBank ?? 'banko'} puslapis…\nPatvirtink prisijungimą ir grįžk į programėlę.'
            : 'Opening ${_connectingBank ?? 'the bank'}…\nApprove access, then return to the app.');
      case _Phase.error:
        return _errorView();
      case _Phase.list:
        return _bankList();
    }
  }

  Widget _busy(String message, {String? hint}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Text(
                message,
                key: ValueKey(message),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cInk, fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 10),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(color: cSubtle, fontSize: 13, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: VaultieColors.danger, size: 40),
            const SizedBox(height: 16),
            Text(
              _error ?? (_isLt ? 'Įvyko klaida.' : 'Something went wrong.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cInk, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadBanks,
              child: Text(_isLt ? 'Bandyti dar kartą' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }

  // ── COUNTRY SELECTION ──
  Widget _countryList() {
    final list = _filteredCountries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Text(
            _isLt
                ? 'Kurioje šalyje tavo bankas? Rodysim tos šalies bankus.'
                : 'Which country is your bank in? We\'ll show that country\'s banks.',
            style: TextStyle(color: cSubtle, fontSize: 13, height: 1.4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: TextField(
            controller: _countrySearch,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, color: cSubtle, size: 20),
              hintText: _isLt ? 'Ieškoti šalies' : 'Search country',
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(_isLt ? 'Nerasta.' : 'No matches.',
                      style: TextStyle(color: cSubtle)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _countryTile(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _countryTile(_Country c) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _pickCountry(c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cLine),
          ),
          child: Row(
            children: [
              Text(c.flag, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _isLt ? c.lt : c.en,
                  style: TextStyle(
                      color: cInk, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: cSubtle, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── BANK LIST ──
  Widget _bankList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected country + quick "change".
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _phase = _Phase.country),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(_country.flag, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(_isLt ? _country.lt : _country.en,
                      style: TextStyle(
                          color: cInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text(_isLt ? '· Keisti' : '· Change',
                      style: const TextStyle(
                          color: VaultieColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            _isLt
                ? 'Pasirink savo banką. Prisijungsi saugiai banko puslapyje — mes niekada nematome tavo slaptažodžio.'
                : 'Pick your bank. You sign in securely on the bank\'s own page — we never see your password.',
            style: TextStyle(color: cSubtle, fontSize: 13, height: 1.4),
          ),
        ),
        Expanded(
          child: _banks.isEmpty
              ? Center(
                  child: Text(
                    _isLt ? 'Šioje šalyje bankų nerasta.' : 'No banks found here.',
                    style: TextStyle(color: cSubtle),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  itemCount: _banks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _bankTile(_banks[i]),
                ),
        ),
        _consentFooter(),
      ],
    );
  }

  /// The two facts that used to live on BankInfoScreen and nowhere else.
  ///
  /// The 90-day limit in particular existed on that one screen only: drop it
  /// and nothing in the app would ever tell a person their bank access expires
  /// and has to be granted again. Sitting here, it is read at the moment
  /// consent is actually given rather than two screens earlier.
  Widget _consentFooter() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: cSubtle),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _isLt
                    ? 'Duomenys saugomi tik tavo telefone · Sutikimas galioja 90 dienų'
                    : 'Data is stored only on your phone · Consent lasts 90 days',
                style: TextStyle(color: cSubtle, fontSize: 11.5, height: 1.35),
              ),
            ),
          ],
        ),
      );

  Widget _bankTile(Bank bank) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _confirm(bank),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cLine),
          ),
          child: Row(
            children: [
              _bankLogo(bank),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  bank.name,
                  style: TextStyle(
                    color: cInk,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (bank.sandbox)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: cHiBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(tr('TESTAS'),
                      style: TextStyle(
                          color: cSubtle,
                          fontWeight: FontWeight.w700,
                          fontSize: 10)),
                ),
              Icon(Icons.arrow_forward_ios_rounded, color: cSubtle, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bankLogo(Bank bank) {
    final logo = bank.logo;
    if (logo != null && logo.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          logo,
          width: 36,
          height: 36,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _logoFallback(bank),
        ),
      );
    }
    return _logoFallback(bank);
  }

  Widget _logoFallback(Bank bank) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: VaultieColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.account_balance,
          color: VaultieColors.primary, size: 20),
    );
  }
}
