import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../screens/bank_callback_screen.dart';
import '../screens/bank_connect_screen.dart';
import 'auth_service.dart';
import 'banking_service.dart';

/// Catches a bank's authorisation callback when it arrives as an app link.
///
/// The in-app flow intercepts the return inside its ASWebAuthenticationSession
/// and never needs this. But a bank that hands off to its own app (SEB,
/// Swedbank) returns through the universal link instead, (re)launching Vaultie —
/// and nothing consumed it, so the user landed on the home screen with the
/// connection silently dropped. This wires that path to [BankCallbackScreen].
///
/// It is a strict no-op for every launch that isn't a banking callback: the
/// filter is [BankingService.codeFromCallback], which returns null for anything
/// else.
class BankingDeepLinks {
  BankingDeepLinks._();
  static final BankingDeepLinks instance = BankingDeepLinks._();

  final _links = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Wire this once at startup, passing the app's navigator key. Never awaited —
  /// a slow platform channel must not hold up the first frame.
  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    if (_started) return;
    _started = true;

    // Cold launch: the link that started the app.
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) _handle(initial, navigatorKey);
    } catch (_) {/* no initial link, or channel unavailable */}

    // Warm: links delivered while the app is already running.
    _sub = _links.uriLinkStream.listen(
      (uri) => _handle(uri, navigatorKey),
      onError: (_) {/* ignore malformed link events */},
    );
  }

  void _handle(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    final code = BankingService.codeFromCallback(uri);
    if (code == null) return; // not our callback — leave the launch untouched

    // finish_bank_auth requires a signed-in caller. On a cold launch the session
    // is restored from the Keychain before this runs, so a returning user is
    // signed in. If somehow not, drop it rather than crash mid-flow — the user
    // can reconnect from inside the app.
    if (!AuthService().isLoggedIn) return;

    // If the in-app flow already claimed this code (the bank delivered the
    // callback through both the session and the universal link), back off — the
    // code is single-use and a second exchange 422s over a working connection.
    if (!BankConnectClaim.claim(code)) return;

    // Defer to after the current frame so the navigator exists and isn't locked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => BankCallbackScreen(code: code)),
      );
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
