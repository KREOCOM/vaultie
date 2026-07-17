import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../theme/vaultie_theme.dart';

/// Two paths — connect a bank (recommended) or start manually. Split layout:
/// a green top (~62%) with the bank CTA, a light bottom (~38%) with the manual
/// card. No prices / "Premium" / trial mentioned here.
class TwoPathsScreen extends StatelessWidget {
  const TwoPathsScreen({
    super.key,
    required this.onBank,
    required this.onManual,
    this.onBack,
  });

  final VoidCallback onBank;
  final VoidCallback onManual;
  final VoidCallback? onBack;

  static const _lightBg = Color(0xFFF1F4EF);
  static const _tint = Color(0xFFE4F0E7); // light green square/arrow bg

  /// Manual path is temporarily hidden — only the bank CTA is shown. Flip to
  /// true (and the `_bottom` manual card returns) when the manual product is
  /// decided. `_bottom` / `onManual` are kept in code, referenced below.
  static const bool _manualEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightBg,
      body: _manualEnabled
          ? Column(
              children: [
                Expanded(flex: 62, child: _greenTop(context)),
                Expanded(flex: 38, child: _bottom(context)),
              ],
            )
          : SizedBox.expand(child: _greenTop(context)),
    );
  }

  Widget _greenTop(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
        gradient: RadialGradient(
          center: Alignment(-0.6, -0.8),
          radius: 1.5,
          colors: [
            Color(0xFF2E8560),
            Color(0xFF1C6045),
            Color(0xFF154A34),
            Color(0xFF0E3324),
          ],
          stops: [0.0, 0.42, 0.72, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Row(
                children: [
                  if (onBack != null)
                    _RoundBack(onTap: onBack!)
                  else
                    const SizedBox(width: 40),
                  const Spacer(),
                ],
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(Icons.account_balance_outlined,
                            color: Colors.white, size: 27),
                      ),
                      const SizedBox(height: 22),
                      Text(tr('Prijunk banką'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4)),
                      const SizedBox(height: 12),
                      Text(
                        tr('Vaultie automatiškai suras visas tavo prenumeratas ir pasikartojančius mokėjimus.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w400),
                      ),
                      const SizedBox(height: 26),
                      _WhiteButton(label: tr('Prijungti banką'), onTap: onBank),
                      const SizedBox(height: 14),
                      _SecurityLine(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottom(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Center(
          child: Material(
            color: VT.card,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onManual,
              child: Ink(
                decoration: BoxDecoration(
                  color: VT.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: VT.line),
                  boxShadow: VT.softShadow,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _tint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.playlist_add_rounded,
                            color: VT.brand, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tr('Pradėti rankiniu būdu'),
                                style: const TextStyle(
                                    color: VT.ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              tr('Nemokamai iki 5 prenumeratų. Banką galėsi prijungti bet kuriuo metu.'),
                              style: const TextStyle(
                                  color: VT.subtle,
                                  fontSize: 12,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: _tint,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_rounded,
                            color: VT.brand, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundBack extends StatelessWidget {
  const _RoundBack({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.arrow_back_ios_new_rounded,
              size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  const _WhiteButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Container(
            height: 54,
            width: double.infinity,
            alignment: Alignment.center,
            child: Text(label,
                style: const TextStyle(
                    color: VT.brand,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}

class _SecurityLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_rounded,
            size: 12, color: Colors.white.withValues(alpha: 0.72)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            tr('Saugus prisijungimas per Enable Banking — licencijuotą ES partnerį.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
