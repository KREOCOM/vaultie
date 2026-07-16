import 'package:flutter/material.dart';

/// Reactive "content" palette for the toggleable screens (dashboard, analytics,
/// settings, add-subscription). These are plain mutable globals reassigned by
/// [applyContentTheme] whenever the light/dark preference changes; widgets on
/// those screens read them directly (which is why those widgets can't be
/// `const`). Auth, splash and the paywall keep their own fixed colours and do
/// NOT use these — the toggle never touches them.

// ── Light ("Frost") — the primary look: airy blue-tinted page, dark ink ───────
const _lBg = Color(0xFFEEF1F7);
const _lCard = Color(0xFFFFFFFF);
const _lInk = Color(0xFF14203A);
const _lSubtle = Color(0xFF5C6A85);
const _lLine = Color(0xFFE3E9F2);
const _lHiBg = Color(0xFFEAF1FF);
const _lHiBorder = Color(0xFFBBD0F5);
const _lFeatTop = Color(0xFFEAF1FF); // soft blue hero
const _lFeatBottom = Color(0xFFE1EAFB);
const _lFeatBorder = Color(0xFFCFDDF6);
const _lFeatInk = Color(0xFF14203A); // text on the featured card
const _lFeatSubtle = Color(0xFF5C6A85);
const _lAccent = Color(0xFF2F6BFF); // electric royal blue on light

// ── Dark (violet twilight — matches the home gradient) ──────────────────────
const _dBg = Color(0xFF201545);
const _dCard = Color(0xFF2A1E54);
const _dInk = Color(0xFFEDEAF6);
const _dSubtle = Color(0xFFC0B8DA);
const _dLine = Color(0xFF3B2D66);
const _dHiBg = Color(0xFF2A2412);
const _dHiBorder = Color(0xFF6B5424);
const _dFeatTop = Color(0xFF34246E);
const _dFeatBottom = Color(0xFF231856);
const _dFeatBorder = Color(0xFF443376);
const _dFeatInk = Color(0xFFEDEAF6);
const _dFeatSubtle = Color(0xFFC0B8DA);
const _dAccent = Color(0xFF8B5CF6);

// ── Live values (default to light) ──────────────────────────────────────────
Color cBg = _lBg;
Color cCard = _lCard;
Color cInk = _lInk;
Color cSubtle = _lSubtle;
Color cLine = _lLine;
Color cHiBg = _lHiBg;
Color cHiBorder = _lHiBorder;
Color cFeatTop = _lFeatTop;
Color cFeatBottom = _lFeatBottom;
Color cFeatBorder = _lFeatBorder;
Color cFeatInk = _lFeatInk;
Color cFeatSubtle = _lFeatSubtle;
Color cAccent = _lAccent;

/// Reassign the live values. Call before building the app (see main.dart) so the
/// content screens pick up the current light/dark choice.
void applyContentTheme(bool dark) {
  cBg = dark ? _dBg : _lBg;
  cCard = dark ? _dCard : _lCard;
  cInk = dark ? _dInk : _lInk;
  cSubtle = dark ? _dSubtle : _lSubtle;
  cLine = dark ? _dLine : _lLine;
  cHiBg = dark ? _dHiBg : _lHiBg;
  cHiBorder = dark ? _dHiBorder : _lHiBorder;
  cFeatTop = dark ? _dFeatTop : _lFeatTop;
  cFeatBottom = dark ? _dFeatBottom : _lFeatBottom;
  cFeatBorder = dark ? _dFeatBorder : _lFeatBorder;
  cFeatInk = dark ? _dFeatInk : _lFeatInk;
  cFeatSubtle = dark ? _dFeatSubtle : _lFeatSubtle;
  cAccent = dark ? _dAccent : _lAccent;
}

/// A [ThemeData] for the content screens, built from the current live palette so
/// default-coloured widgets (Cards, inputs, dialogs, sheets, AppBars, text)
/// follow the light/dark choice. Wrap dashboard + add-subscription in this.
ThemeData contentTheme(ThemeData base) {
  return base.copyWith(
    // Material widgets (ListTile titles, etc.) take their text colour from the
    // colour scheme, so it must follow the toggle too — otherwise dark-mode
    // rows keep the light theme's dark onSurface and vanish on dark cards.
    colorScheme: base.colorScheme.copyWith(
      surface: cBg,
      onSurface: cInk,
      onSurfaceVariant: cSubtle,
    ),
    scaffoldBackgroundColor: cBg,
    canvasColor: cCard,
    cardTheme: base.cardTheme.copyWith(color: cCard),
    textTheme: base.textTheme.apply(bodyColor: cInk, displayColor: cInk),
    iconTheme: IconThemeData(color: cInk),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: cBg,
      foregroundColor: cInk,
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(color: cCard),
    dialogTheme: base.dialogTheme.copyWith(backgroundColor: cCard),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(backgroundColor: cCard),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: cCard,
      hintStyle: TextStyle(color: cSubtle),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cLine),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cLine),
      ),
    ),
    datePickerTheme: base.datePickerTheme.copyWith(backgroundColor: cCard),
  );
}
