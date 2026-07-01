import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../main.dart';
import 'auth_screen.dart';

/// Three-screen image onboarding with localized artwork. The user swipes (or
/// taps the CTA) through 1 → 2 → 3, then lands on the auth screen. Lithuanian
/// devices get the LT images and button copy; everyone else gets EN.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const route = '/onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // `--dart-define=ONBOARD_PAGE=2` opens straight to a given screen (preview aid).
  final _controller =
      PageController(initialPage: const int.fromEnvironment('ONBOARD_PAGE'));

  @override
  void initState() {
    super.initState();
    // Full-bleed artwork: hide the status bar while onboarding is on screen.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    await Hive.box(HiveBoxes.settings).put('onboarded', true);
    // Restore the system bars for the rest of the app.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Lithuanian device → LT assets + copy; anything else → EN.
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final lang = isLt ? 'lt' : 'en';
    final continueLabel = isLt ? 'Toliau →' : 'Continue →';
    final getStartedLabel = isLt ? 'Pradėti →' : 'Get Started →';

    final pages = <_OnboardPage>[
      _OnboardPage('assets/images/1$lang.png', continueLabel, _next),
      _OnboardPage('assets/images/2$lang.png', continueLabel, _next),
      _OnboardPage('assets/images/3$lang.png', getStartedLabel, _finish),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: PageView.builder(
        controller: _controller,
        // Navigation is button-only — swiping is disabled.
        physics: const NeverScrollableScrollPhysics(),
        itemCount: pages.length,
        itemBuilder: (_, i) {
          final page = pages[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Full-colour artwork fills the top portion — no overlay/fade.
              Expanded(
                child: Image.asset(
                  page.image,
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),
              // Pure white panel beneath the image holding the button.
              // 16px gap above the button, 32px below (clears the nav bar).
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: _CtaButton(label: page.label, onPressed: page.onPressed),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One onboarding screen: a full-bleed image and its bottom CTA.
class _OnboardPage {
  const _OnboardPage(this.image, this.label, this.onPressed);
  final String image;
  final String label;
  final VoidCallback onPressed;
}

/// The shared dark-green pill button used at the bottom of every screen.
class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        // Subtle green glow so the button reads softer against the artwork.
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF174E35).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF174E35),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
