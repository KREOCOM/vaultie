import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../app_prefs.dart';
import '../content_theme.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/banking_service.dart';
import '../services/dashboard_store.dart';
import '../services/feature_flags.dart';
import '../user_session.dart';
import 'bank_import_screen.dart';
import 'login_screen.dart';
import 'preview/dashboard_preview.dart';

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
  final scan = await BankingService.instance.finishBankAuth(
      code, aiEnrichment: AppPrefs.aiEnrichment, bank: bank, monthsBack: 3);
  final conn = scan.connection;
  if (conn != null) {
    await DashboardStore.addConnection(
      bank: bank ?? conn['bank'] as String? ?? 'Bankas',
      sessionId: conn['sessionId'] as String?,
      accounts: (((conn['accounts'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList()),
    );
  }
  Map<String, dynamic>? dash = scan.dash;
  if (DashboardStore.bankCount > 1) {
    try {
      final combined = await BankingService.instance.refreshDashboard(
          DashboardStore.accountRefs(),
          aiEnrichment: AppPrefs.aiEnrichment, monthsBack: 3);
      if (combined != null) dash = combined;
    } on BankingException {
      // keep the single-bank dash as a fallback
    }
  }
  if (dash != null) {
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

enum _Phase { country, loading, list, connecting, analysing, error }

class _BankConnectScreenState extends State<BankConnectScreen> {
  /// Starts on [_Phase.loading], not on the country picker.
  ///
  /// Enable Banking needs a country from us — /aspsps takes it as a parameter
  /// and start_auth requires it alongside the bank — but asking for it is a
  /// step almost nobody needs: the default is Lithuania and the chip at the top
  /// of the list changes it. The picker itself is untouched, just no longer the
  /// first thing between a person and their bank.
  _Phase _phase = _Phase.loading;
  List<Bank> _banks = const [];
  String? _error;
  String? _connectingBank;

  _Country _country = _countries.first; // Lithuania by default
  final _countrySearch = TextEditingController();

  // A cycling "we're working" progress while the scan runs, so a 40–80s scan
  // never feels frozen. Advances every few seconds and holds on the last stage.
  Timer? _stageTimer;
  int _stage = 0;
  static const _stagesLt = [
    'Saugiai jungiamės prie banko…',
    'Traukiame tavo sandorius…',
    'Analizuojame išlaidas, pajamas ir sąskaitas…',
    'Beveik baigėm…',
  ];
  static const _stagesEn = [
    'Securely connecting to your bank…',
    'Fetching your transactions…',
    'Analysing spending, income and bills…',
    'Almost done…',
  ];

  void _startStages() {
    _stage = 0;
    _stageTimer?.cancel();
    _stageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        if (_stage < 3) _stage++;
      });
    });
  }

  void _stopStages() {
    _stageTimer?.cancel();
    _stageTimer = null;
  }

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
    _stopStages();
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
    _loadBanks();
  }

  void _pickCountry(_Country c) {
    setState(() => _country = c);
    _loadBanks();
  }

  Future<void> _loadBanks() async {
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
        _phase = _Phase.error;
      });
      return;
    }
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final banks = await BankingService.instance.listBanks(country: _country.code);
      if (!mounted) return;
      setState(() {
        _banks = banks;
        _phase = _Phase.list;
      });
    } on BankingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _connect(Bank bank) async {
    // Hard re-entrancy guard. The phase change below hides the bank list within
    // a frame, but two taps inside that frame — or during the await — started
    // two consent flows: two authorisation sessions at the bank, two entries
    // against its daily quota, and a second browser session iOS then refuses.
    if (_phase == _Phase.connecting || _phase == _Phase.analysing) return;
    setState(() {
      _phase = _Phase.connecting;
      _connectingBank = bank.name;
      _error = null;
    });
    try {
      // Remember which bank this is BEFORE the browser opens: if it hands off to
      // its own app and the return cold-launches Vaultie, the callback carries
      // only a code, and the resume path recovers the label from here.
      await DashboardStore.setPendingConnect(bank.name);
      final url = await BankingService.instance.startBankAuth(bank.name,
          country: bank.country.isNotEmpty ? bank.country : _country.code);
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
        _stopStages();
        return;
      }
      if (!mounted) return;
      setState(() => _phase = _Phase.analysing);
      _startStages();
      // Everything past the code is shared with the deep-link resume path.
      final r = await completeBankConnection(code, bank: bank.name);
      _stopStages();
      if (!mounted) return;
      // Land straight in the new dashboard. Fall back to the legacy import screen
      // only if the backend couldn't build the dashboard payload.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => r.dash != null
              ? DashboardPreview(data: r.dash!, deeper: r.deeper)
              : BankImportScreen(result: r.scan),
        ),
      );
    } on PlatformException catch (e) {
      _stopStages();
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
      _stopStages();
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _Phase.error;
      });
    } catch (e) {
      // Everything else. Between the bank's approval and the dashboard there is
      // a Hive write, a jsonEncode and several casts of the bank's payload —
      // none of them a PlatformException or a BankingException. One of those
      // throwing left the screen stuck on "analysing" forever, with the stage
      // ticker still cycling "Almost done…" so it looked alive, under a hint
      // telling the user not to close the app. The bank was already connected
      // by then, so their only move — force-quit and retry — burned a second
      // consent.
      _stopStages();
      if (!mounted) return;
      setState(() {
        _error = _isLt
            ? 'Bankas prisijungė, bet duomenų parsisiųsti nepavyko. Bandyk dar kartą.'
            : "Your bank connected, but we couldn't load the data. Please try again.";
        _phase = _Phase.error;
      });
    } finally {
      // Belt and braces: no path out of this method leaves the ticker running.
      _stopStages();
      // Deliberately does NOT clear the pending-connect marker here. When a bank
      // hands off to its own app, this session reports CANCELED and lands in the
      // catch above — but the connection isn't cancelled, it's continuing via
      // the universal link, and BankCallbackScreen still needs the bank name
      // this marker holds. Clearing it here set it to null before the deep-link
      // path read it, so the bank came back labelled "Bankas". It's overwritten
      // at the start of the next connect and cleared on success, so a stale
      // marker after a real cancel is harmless.
    }
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
    final atRoot = _phase == _Phase.country;
    // Reached in two contexts: during onboarding the stack is empty (nowhere to
    // pop to — the old dead-end), while the in-app "+ add bank" flow pushes this
    // on top of the dashboard (a real route beneath). Offer an exit accordingly.
    final canPop = Navigator.of(context).canPop();
    return Theme(
      data: contentTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: cBg,
        appBar: AppBar(
          leading: atRoot
              ? (canPop
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null)
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() => _phase = _Phase.country),
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
      case _Phase.country:
        return _countryList();
      case _Phase.loading:
        return _busy(_isLt ? 'Kraunami bankai…' : 'Loading banks…');
      case _Phase.connecting:
        return _busy(_isLt
            ? 'Atveriamas ${_connectingBank ?? 'banko'} puslapis…\nPatvirtink prisijungimą ir grįžk į programėlę.'
            : 'Opening ${_connectingBank ?? 'the bank'}…\nApprove access, then return to the app.');
      case _Phase.analysing:
        final stages = _isLt ? _stagesLt : _stagesEn;
        return _busy(
          stages[_stage.clamp(0, stages.length - 1)],
          hint: _isLt
              ? 'Tai gali užtrukti iki minutės — analizuojame visus tavo sandorius. Neuždaryk programėlės.'
              : 'This can take up to a minute — we\'re analysing all your transactions. Keep the app open.',
        );
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
        onTap: () => _connect(bank),
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
                  child: Text('TESTAS',
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
