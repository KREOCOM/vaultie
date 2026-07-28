import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../screens/bank_callback_screen.dart';
import '../screens/bank_connect_screen.dart';
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

  Future<void> _handle(Uri uri, GlobalKey<NavigatorState> navigatorKey) async {
    final code = BankingService.codeFromCallback(uri);
    if (code == null) return; // not our callback — leave the launch untouched

    // If the in-app flow already claimed this code (the bank delivered the
    // callback through both the session and the universal link), back off — the
    // code is single-use and a second exchange 422s over a working connection.
    if (!BankConnectClaim.claim(code)) return;

    // Show the callback screen NOW, whatever the auth state.
    //
    // There used to be an 8-second wait here for Firebase to restore the session
    // before pushing, and on timeout it simply `return`ed. That was the silent
    // failure: the user came back from their bank to an app showing nothing at
    // all, with the single-use code already spent, so retrying cost a whole new
    // consent. BankCallbackScreen does its own (longer) wait and, crucially, has
    // a visible error state with a retry — it is the right owner for both.
    _push(navigatorKey, code);
  }

  /// Pushes the callback screen once the navigator exists.
  ///
  /// On a cold launch the first frame can arrive before the navigator does, and
  /// `currentState?.push` on a null navigator is a silent no-op — which would
  /// strand a code that this method has ALREADY claimed, so nothing else could
  /// pick it up either. Retries briefly instead of dropping it.
  void _push(GlobalKey<NavigatorState> navigatorKey, String code,
      [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav == null) {
        if (attempt < 20) {
          Future<void>.delayed(const Duration(milliseconds: 150),
              () => _push(navigatorKey, code, attempt + 1));
        }
        return;
      }
      nav.push(
        MaterialPageRoute(builder: (_) => BankCallbackScreen(code: code)),
      );
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
