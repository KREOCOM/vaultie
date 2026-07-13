import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../content_theme.dart';
import '../main.dart';
import '../services/banking_service.dart';
import 'bank_import_screen.dart';
import 'preview/dashboard_preview.dart';

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
  _Phase _phase = _Phase.country;
  List<Bank> _banks = const [];
  String? _error;
  String? _connectingBank;

  _Country _country = _countries.first; // Lithuania by default
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

  void _pickCountry(_Country c) {
    setState(() => _country = c);
    _loadBanks();
  }

  Future<void> _loadBanks() async {
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
    setState(() {
      _phase = _Phase.connecting;
      _connectingBank = bank.name;
      _error = null;
    });
    try {
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
      if (!mounted) return;
      setState(() => _phase = _Phase.analysing);
      final scan = await BankingService.instance.finishBankAuth(code);
      if (!mounted) return;
      // Land straight in the new dashboard with the classified transactions.
      // Fall back to the legacy import screen only if the backend couldn't
      // build the dashboard payload.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => scan.dash != null
              ? DashboardPreview(data: scan.dash)
              : BankImportScreen(result: scan),
        ),
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
  }

  @override
  Widget build(BuildContext context) {
    // From the bank list / error, "back" returns to country selection rather
    // than leaving the flow entirely.
    final atRoot = _phase == _Phase.country;
    return Theme(
      data: contentTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: cBg,
        appBar: AppBar(
          leading: atRoot
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() => _phase = _Phase.country),
                ),
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
        return _busy(_isLt
            ? 'Ieškome pasikartojančių mokėjimų…'
            : 'Finding your recurring payments…');
      case _Phase.error:
        return _errorView();
      case _Phase.list:
        return _bankList();
    }
  }

  Widget _busy(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cSubtle, fontSize: 15, height: 1.4),
            ),
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
                      style: TextStyle(
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
      ],
    );
  }

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
                  child: Text('TEST',
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
