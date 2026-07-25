import 'package:flutter/material.dart';

import 'onb_scene_page.dart';
import 'preview/dashboard_preview.dart';

/// Onboarding page 5 — the AI assistant. The phone opens already ON the chat
/// tab with a conversation in it, then asks another question and answers it.
///
/// The artwork's own screen shows the Overview, not a chat, so letting it stand
/// in while the live screen builds would show one screen turning into a
/// different one — the thing that read as "a picture first, then the app".
/// Mounting instantly fixed that but put the whole build inside the entry
/// transition, which is worse: a stutter here costs more than a blank moment.
/// So the glass is filled with the app's own background until the chat lands.
///
/// Geometry measured off page5_scene.png (1023×1537): glass x 330→684,
/// y 336→1189, corner a circle of r=45.7 (fitted, mse 0.42). The status-bar
/// glyphs end 41px down and the artwork's own header starts at 77, so the ink
/// stamp runs to 58 — past the corner curve, clear of the header.
class OnbAiChat extends StatelessWidget {
  const OnbAiChat({super.key, required this.next});

  final Widget next;

  static const _geometry = SceneGeometry(
    imgW: 1023,
    imgH: 1537,
    glassL: 330,
    glassT: 336,
    glassR: 684,
    glassB: 1189,
    corner: 46,
    stampH: 58,
    statusH: 62,
    ringB: 1235,
  );

  @override
  Widget build(BuildContext context) => OnbScenePage(
        next: next,
        sceneAsset: 'assets/onboarding/page5_scene.png',
        stampAsset: 'assets/onboarding/page5_statusbar.png',
        geometry: _geometry,
        script: DemoScript.chat,
        blankUntilLive: const Color(0xFFEEF1F7),
        badgeIcon: Icons.auto_awesome_rounded,
        badge: 'Atsako apie tavo pinigus',
        headline: 'Paklausk savo\nfinansų bet ko',
        sub: 'Kur išleidau daugiausia? Ar viršijau biudžetą? Atsakymas — iš tavo tikrų duomenų.',
        dotIndex: 4,
        dotCount: 6,
        warmNext: 'assets/onboarding/page6_scene.png',
      );
}
