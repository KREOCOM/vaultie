import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock.dart';

const _bg = Color(0xFF160E30);
const _bg2 = Color(0xFF2A1E58);
const _ink = Color(0xFFEDEAF6);
const _dim = Color(0xFF9A93B8);
const _accent = Color(0xFF8B5CF6);

const _pinLength = 4;

/// The unlock gate: verify the existing PIN (with optional Face ID). Shown over
/// the whole app on launch / return from background while a PIN is set.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entry = '';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    // Offer Face ID immediately if the user enabled it.
    if (AppLock.faceIdEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryFaceId());
    }
  }

  Future<void> _tryFaceId() async {
    final ok = await AppLock.authenticateBiometric();
    if (ok && mounted) widget.onUnlocked();
  }

  void _press(String d) {
    if (_entry.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry += d;
      _error = false;
    });
    if (_entry.length == _pinLength) {
      if (AppLock.verifyPin(_entry)) {
        HapticFeedback.mediumImpact();
        widget.onUnlocked();
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _error = true;
          _entry = '';
        });
      }
    }
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return _PinScaffold(
      title: 'Įvesk PIN kodą',
      subtitle: _error ? 'Neteisingas PIN — bandyk dar' : 'Vaultie užrakinta',
      entry: _entry,
      error: _error,
      onDigit: _press,
      onBackspace: _backspace,
      faceIdButton: AppLock.faceIdEnabled ? _tryFaceId : null,
    );
  }
}

/// Set or change the PIN: enter, then confirm. Returns the confirmed PIN, or
/// null if cancelled. Pushed from Settings.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});
  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _entry = '';
  String? _first; // captured first pass, awaiting confirm
  bool _error = false;

  void _press(String d) {
    if (_entry.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry += d;
      _error = false;
    });
    if (_entry.length == _pinLength) _commit();
  }

  void _commit() {
    if (_first == null) {
      setState(() {
        _first = _entry;
        _entry = '';
      });
    } else if (_first == _entry) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(_entry);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = true;
        _entry = '';
        _first = null;
      });
    }
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return _PinScaffold(
      title: _first == null ? 'Naujas PIN kodas' : 'Pakartok PIN',
      subtitle: _error
          ? 'PIN nesutapo — pradėk iš naujo'
          : _first == null
              ? 'Sugalvok 4 skaitmenų kodą'
              : 'Įvesk tą patį kodą dar kartą',
      entry: _entry,
      error: _error,
      onDigit: _press,
      onBackspace: _backspace,
      onClose: () => Navigator.of(context).pop(),
    );
  }
}

/// Shared PIN-pad UI (dots + number grid) used by both screens.
class _PinScaffold extends StatelessWidget {
  const _PinScaffold({
    required this.title,
    required this.subtitle,
    required this.entry,
    required this.error,
    required this.onDigit,
    required this.onBackspace,
    this.faceIdButton,
    this.onClose,
  });
  final String title, subtitle, entry;
  final bool error;
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final Future<void> Function()? faceIdButton;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [_bg, _bg2],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (onClose != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: _ink),
                    onPressed: onClose,
                  ),
                ),
              const Spacer(flex: 2),
              Container(
                width: 58, height: 58, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(Icons.lock_rounded, color: _accent, size: 26),
              ),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 8),
              Text(subtitle, style: TextStyle(fontSize: 14.5, color: error ? const Color(0xFFFF8A9B) : _dim)),
              const SizedBox(height: 30),
              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pinLength; i++)
                    Container(
                      width: 15, height: 15,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < entry.length ? _accent : Colors.transparent,
                        border: Border.all(color: i < entry.length ? _accent : _dim, width: 1.6),
                      ),
                    ),
                ],
              ),
              const Spacer(flex: 3),
              _pad(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pad() {
    Widget key(String label, {VoidCallback? onTap, Widget? child}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: AspectRatio(
              aspectRatio: 1.6,
              child: Material(
                color: label.isEmpty ? Colors.transparent : Colors.white.withValues(alpha: 0.06),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onTap,
                  child: Center(
                    child: child ??
                        Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: _ink)),
                  ),
                ),
              ),
            ),
          ),
        );

    Widget row(List<Widget> children) => Row(children: children);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row([for (final d in ['1', '2', '3']) key(d, onTap: () => onDigit(d))]),
          row([for (final d in ['4', '5', '6']) key(d, onTap: () => onDigit(d))]),
          row([for (final d in ['7', '8', '9']) key(d, onTap: () => onDigit(d))]),
          row([
            faceIdButton != null
                ? key('', onTap: () => faceIdButton!.call(),
                    child: const Icon(Icons.face_retouching_natural_rounded, color: _accent, size: 30))
                : key(''),
            key('0', onTap: () => onDigit('0')),
            key('', onTap: onBackspace, child: const Icon(Icons.backspace_outlined, color: _ink, size: 24)),
          ]),
        ],
      ),
    );
  }
}
