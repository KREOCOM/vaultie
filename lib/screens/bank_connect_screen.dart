import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../content_theme.dart';
import '../main.dart';
import '../services/banking_service.dart';
import 'bank_import_screen.dart';

/// Pro-only flow: pick a bank → approve inside an ASWebAuthenticationSession →
/// the session intercepts the `vaultie://banking/callback` return (no "Open in
/// Vaultie?" prompt) → detect recurring payments.
class BankConnectScreen extends StatefulWidget {
  const BankConnectScreen({super.key});

  static const route = '/bank-connect';

  @override
  State<BankConnectScreen> createState() => _BankConnectScreenState();
}

enum _Phase { loading, list, connecting, analysing, error }

class _BankConnectScreenState extends State<BankConnectScreen> {
  _Phase _phase = _Phase.loading;
  List<Bank> _banks = const [];
  String? _error;
  String? _connectingBank;

  @override
  void initState() {
    super.initState();
    _loadBanks();
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
      // Open the bank's page in an ASWebAuthenticationSession (iOS) / Custom
      // Tab (Android). The session itself intercepts the vaultie:// callback and
      // hands it straight back here — no "Open in Vaultie?" prompt, no bounce
      // out to Safari.
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
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BankImportScreen(result: scan),
        ),
      );
    } on PlatformException catch (e) {
      // The user dismissed the bank sheet — quietly return to the bank list.
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
