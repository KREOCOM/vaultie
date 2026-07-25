import 'package:flutter/material.dart';

import 'onb_scene_page.dart';
import 'preview/dashboard_preview.dart';

/// Onboarding page 6 — budgets and settings, the last page before the bank
/// connect. The demo opens the add-budget sheet, then walks into the account
/// tab and shows the app turning dark.
///
/// Nothing it touches is written: the theme is flipped through the notifier and
/// the palette rather than `AppPrefs.setDarkMode`, and restored when the page
/// goes away. A page that sells the app must not leave the viewer's own app
/// dark — the same rule that keeps the demo off the bank APIs and off the
/// assistant.
///
/// Geometry measured off page6_scene.png (853×1844): glass x 256→590,
/// y 484→1305, corner a circle of r=47.0 (fitted, mse 3.38). The status-bar
/// glyphs end 41px down and the artwork's own "Planavimas" header starts at 74,
/// so the ink stamp runs to 58 — past the corner curve, clear of the header.
class OnbBudget extends StatelessWidget {
  const OnbBudget({super.key, required this.next});

  final Widget next;

  static const _geometry = SceneGeometry(
    imgW: 853,
    imgH: 1844,
    // Pulled 2px in on each side: like the first render, this one is not
    // rectilinear — its screen edge sits at 256 down the straight run but at
    // 258 up in the corners, so a rect on 256 spilled the live screen onto the
    // black bezel and showed as a sliver along the frame.
    glassL: 258,
    glassT: 485,
    glassR: 588,
    glassB: 1304,
    corner: 45,
    stampH: 58,
    statusH: 60,
    ringB: 1360,
    // The render leaves a quarter of its height as empty sky above the phone.
    // Drawn from the top that emptied the page and pushed the phone down into
    // the copy; cropping it lifts the phone and frees the room the copy needs.
    topCrop: 0.13,
  );

  @override
  Widget build(BuildContext context) => OnbScenePage(
        next: next,
        sceneAsset: 'assets/onboarding/page6_scene.png',
        stampAsset: 'assets/onboarding/page6_statusbar.png',
        geometry: _geometry,
        script: DemoScript.budget,
        badgeIcon: Icons.tune_rounded,
        badge: 'Tu nustatai ribas',
        headline: 'Susidėk biudžetą\nir laikykis jo',
        sub: 'Limitą pasiūlome pagal tavo tikrą vidurkį. PIN, valiuta ir tamsi tema — tavo nuožiūra.',
        dotIndex: 5,
        dotCount: 6,
      );
}
