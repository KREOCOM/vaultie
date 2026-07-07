import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../content_theme.dart';
import '../main.dart';
import '../services/banking_service.dart';
import 'bank_import_screen.dart';

/// Pro-only flow: pick a bank → approve on the bank's site → land back here via
/// the `vaultie://banking/callback` deep link → detect recurring payments.
class BankConnectScreen extends StatefulWidget {
  const BankConnectScreen({super.key});

  static const route = '/bank-connect';

  @override
  State<BankConnectScreen> createState() => _BankConnectScreenState();
}

enum _Phase { loading, list, connecting, analysing, error }

class _BankConnectScreenState extends State<BankConnectScreen> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  _Phase _phase = _Phase.loading;
  List<Bank> _banks = const [];
  String? _error;
  String? _connectingBank;

  @override
  void initState() {
    super.initState();
    // Listen for the bank's redirect the whole time this screen is open.
    _linkSub = _appLinks.uriLinkStream.listen(_onLink, onError: (_) {});
    _loadBanks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  Future<void> _loadBanks() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final banks = await BankingService.instance.listBanks();
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
      final url = await BankingService.instance.startBankAuth(bank.name);
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw BankingException(_isLt
            ? 'Nepavyko atidaryti banko puslapio.'
            : 'Could not open the bank page.');
      }
      // Now we wait for _onLink to fire with the callback code.
    } on BankingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _Phase.error;
      });
    }
  }

  /// Handles the bank's redirect back into the app.
  Future<void> _onLink(Uri uri) async {
    final code = BankingService.codeFromCallback(uri);
    if (code == null) return; // not our callback
    if (_phase == _Phase.analysing) return; // already processing
    setState(() => _phase = _Phase.analysing);
    try {
      final candidates = await BankingService.instance.finishBankAuth(code);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BankImportScreen(candidates: candidates),
        ),
      );
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
    return Theme(
      data: contentTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: cBg,
        appBar: AppBar(
          title: Text(_isLt ? 'Prijungti banką' : 'Connect your bank'),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
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

  Widget _bankList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
                    _isLt ? 'Bankų nerasta.' : 'No banks found.',
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
