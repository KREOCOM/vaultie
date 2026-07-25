import 'package:flutter/material.dart';

import 'onb_scene_page.dart';
import 'preview/dashboard_preview.dart';

/// Onboarding page 4 — the Overview tab. The demo walks to Apžvalga and opens
/// the savings-rate breakdown, which is the number the page is selling.
///
/// Geometry measured off page4_scene.png (940×1672): glass x 289→647,
/// y 371→1260, corner a circle of r=46.8 (fitted, mse 0.32). The status-bar
/// glyphs end 44px down and the artwork's own "Apžvalga" header starts at 73,
/// so the ink stamp runs to 60 — past the corner curve, clear of the header.
class OnbOverview extends StatelessWidget {
  const OnbOverview({super.key, required this.next});

  final Widget next;

  static const _geometry = SceneGeometry(
    imgW: 940,
    imgH: 1672,
    glassL: 289,
    glassT: 371,
    glassR: 647,
    glassB: 1260,
    corner: 47,
    stampH: 60,
    statusH: 59,
    ringB: 1300,
  );

  @override
  Widget build(BuildContext context) => OnbScenePage(
        next: next,
        sceneAsset: 'assets/onboarding/page4_scene.png',
        stampAsset: 'assets/onboarding/page4_statusbar.png',
        geometry: _geometry,
        script: DemoScript.overview,
        badgeIcon: Icons.donut_large_rounded,
        badge: 'Kur nuėjo pinigai',
        headline: 'Matai, kiek atsidėjai\nir kur išleidai',
        sub: 'Kiekviena kategorija, santaupų norma ir mėnesio rezultatas — vienoje vietoje.',
        dotIndex: 3,
        dotCount: 5,
        warmNext: 'assets/onboarding/page5_scene.png',
      );
}
