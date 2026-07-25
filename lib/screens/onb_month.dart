import 'package:flutter/material.dart';

import 'onb_scene_page.dart';

/// Onboarding page 3 — the home feed. The demo hides the balance, draws the
/// balance line, scrolls the payments and opens the subscriptions manager.
///
/// Geometry measured off page3_scene.png (941×1672): glass x 298→648,
/// y 359→1195, corner a clean circle of r=45.1 (fitted, mse 0.11). This render
/// is rectilinear — its left edge lands on 298 in every row — so the rect needs
/// no inward fudge. The status-bar glyphs end 42px down and the artwork's own
/// "Pradžia" header starts at 68, so the ink stamp runs to 58: past the corner
/// curve, clear of the header.
class OnbMonth extends StatelessWidget {
  const OnbMonth({super.key, required this.next});

  final Widget next;

  static const _geometry = SceneGeometry(
    imgW: 941,
    imgH: 1672,
    glassL: 298,
    glassT: 359,
    glassR: 648,
    glassB: 1195,
    corner: 45,
    stampH: 58,
    statusH: 54,
    ringB: 1250,
  );

  @override
  Widget build(BuildContext context) => OnbScenePage(
        next: next,
        sceneAsset: 'assets/onboarding/page3_scene.png',
        stampAsset: 'assets/onboarding/page3_statusbar.png',
        geometry: _geometry,
        badgeIcon: Icons.auto_graph_rounded,
        badge: 'Atsinaujina automatiškai',
        headline: 'Visas tavo mėnuo\nviename ekrane',
        sub: 'Pajamos, išlaidos, prenumeratos ir sąskaitos — viskas susirūšiuoja savaime.',
        dotIndex: 2,
        dotCount: 6,
        warmNext: 'assets/onboarding/page4_scene.png',
      );
}
