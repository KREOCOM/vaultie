import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../i18n.dart';
import '../services/notification_service.dart';
import 'login_screen.dart' show authBrand, authInk, authPaper, authSub;

/// Asks for notification permission — at a moment when there is something to
/// be notified ABOUT.
///
/// The permission was never requested at all: [NotificationService.init]
/// deliberately initialises without prompting, deferring to "the onboarding
/// reminders step", and that step did not exist. Every reminder the app
/// scheduled was therefore dropped by iOS in silence.
///
/// It is asked here, straight after the first bank connect, rather than during
/// onboarding: the OS prompt can be answered exactly once per install, so a
/// "no" is permanent. Before the connect there is nothing to promise; after it
/// the scan has just found the person's actual payments, and the examples below
/// are describing something they have already seen.
class OnbNotifications extends StatefulWidget {
  const OnbNotifications({super.key, required this.next});

  /// Shown once the answer — either answer — is in.
  final Widget next;

  @override
  State<OnbNotifications> createState() => _OnbNotificationsState();
}

class _OnbNotificationsState extends State<OnbNotifications> {
  bool _busy = false;

  Future<void> _finish({required bool ask}) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Recorded BEFORE the prompt. If the OS sheet somehow never returns, the
    // person still gets into the app rather than meeting this screen forever.
    await AppPrefs.setNotifIntroShown(true);
    if (ask) {
      try {
        await NotificationService.instance.requestPermission();
      } catch (_) {
        // Denied, unavailable, or no platform implementation — either way the
        // app continues. Reminders simply stay off.
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => widget.next),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: authPaper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 12),
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          color: authBrand, shape: BoxShape.circle),
                      child: const Icon(Icons.notifications_rounded,
                          color: Colors.white, size: 38),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      tr('Priminsime prieš laiką'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: authInk,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr('Pranešime prieš mokėjimą, kai baigsis banko prieiga ir kai bus paruošta mėnesio ataskaita.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: authSub, fontSize: 13.5, height: 1.45),
                    ),
                    const SizedBox(height: 26),
                    // Real examples rather than a list of promises: the point is
                    // that a reminder arrives while there is still time to act.
                    _example(
                      icon: Icons.event_repeat_rounded,
                      title: 'Netflix · 12,99 €',
                      body: tr('Mokėjimas po 2 d.'),
                      when: tr('dabar'),
                    ),
                    const SizedBox(height: 10),
                    _example(
                      icon: Icons.link_off_rounded,
                      title: tr('Banko prieiga baigiasi'),
                      body: tr('Po 7 d. reikės prisijungti iš naujo, kad duomenys nesustotų.'),
                      when: tr('vakar'),
                    ),
                    const SizedBox(height: 10),
                    _example(
                      icon: Icons.bar_chart_rounded,
                      title: tr('Mėnesio ataskaita paruošta'),
                      body: tr('Pažiūrėk, kiek išleidai praėjusį mėnesį.'),
                      when: tr('prieš 3 d.'),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Column(
                children: [
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => _finish(ask: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: authBrand,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF1B2A55),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(
                            fontSize: 16.5, fontWeight: FontWeight.w800),
                      ),
                      child: Text(tr('Įjungti priminimus')),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy ? null : () => _finish(ask: false),
                    child: Text(tr('Ne dabar'),
                        style: const TextStyle(
                            color: authSub, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _example({
    required IconData icon,
    required String title,
    required String body,
    required String when,
  }) =>
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1740),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E2F66)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: authBrand.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 18, color: const Color(0xFF7FA6FF)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: authInk,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                      Text(when,
                          style: const TextStyle(
                              color: authSub, fontSize: 11.5)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          color: authSub, fontSize: 12.5, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );
}
