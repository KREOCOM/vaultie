import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'verify_email_screen.dart';

/// Email/password sign-in & registration backed by Firebase Auth.
///
/// Cinematic dark theme: a floating logo over a green glow, with the form in a
/// bottom-sheet-style panel. Registration collects the password twice and sends
/// a verification email; users are let in immediately and reminded to verify.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  static const route = '/auth';

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _isLogin = true;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  // Gentle up/down float for the logo.
  late final AnimationController _floatController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  // One-shot slide-up for the bottom panel.
  late final AnimationController _panelController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();

  static const _bg = Color(0xFF050F08);
  static const _accent = Color(0xFF4CAF72);

  @override
  void dispose() {
    _floatController.dispose();
    _panelController.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final isLt = _isLt;
    try {
      if (_isLogin) {
        await _auth.signIn(email: _email.text, password: _password.text);
        if (!mounted) return;
        // Signed-in but unverified accounts are held at the verify screen.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => _auth.isEmailVerified
                ? const DashboardScreen()
                : const VerifyEmailScreen(),
          ),
        );
      } else {
        // register() already fires the verification email; land the user on
        // the verify screen until they click the link.
        await _auth.register(email: _email.text, password: _password.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isLt
                ? 'Patvirtinimo laiškas išsiųstas į ${_email.text.trim()}.'
                : 'Verification email sent to ${_email.text.trim()}.'),
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authErrorMessage(e, isLithuanian: isLt)),
          backgroundColor: VaultieColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLt = _isLt;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // Subtle green radial glow in the centre.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.35),
                    radius: 0.95,
                    colors: [Color(0x59206B41), Color(0x00050F08)],
                    stops: [0.0, 0.72],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Hero: floating logo + wordmark.
                  Expanded(
                    child: Align(
                      alignment: const Alignment(0, -0.1),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              AnimatedBuilder(
                                animation: _floatController,
                                builder: (context, child) {
                                  final t = Curves.easeInOut
                                      .transform(_floatController.value);
                                  return Transform.translate(
                                    offset: Offset(0, 6 - 12 * t),
                                    child: child,
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: Image.asset(
                                    'assets/icon/app_icon.png',
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              const Text(
                                'Vaultie',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isLt
                                    ? 'Tavo prenumeratų sekiklis'
                                    : 'Your subscription tracker',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildPanel(l, isLt),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The dark bottom-sheet-style panel that slides up on entry.
  Widget _buildPanel(AppLocalizations l, bool isLt) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic));

    return SlideTransition(
      position: slide,
      child: FadeTransition(
        opacity: _panelController,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF0B160F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(
              top: BorderSide(color: Color(0x1AFFFFFF)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isLogin
                      ? (isLt ? 'Prisijunk, kad tęstum' : 'Sign in to continue')
                      : (isLt ? 'Sukurk paskyrą' : 'Create your account'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                _field(
                  controller: _email,
                  hint: l.email,
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return l.emailEmptyError;
                    if (!v.contains('@')) return l.emailInvalidError;
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _password,
                  focusNode: _passwordFocus,
                  hint: l.password,
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                  onToggleObscure: () => setState(() => _obscure = !_obscure),
                  textInputAction:
                      _isLogin ? TextInputAction.done : TextInputAction.next,
                  onSubmitted: (_) {
                    if (_isLogin) {
                      _submit();
                    } else {
                      _confirmFocus.requestFocus();
                    }
                  },
                  validator: (v) {
                    if (v == null || v.length < 6) return l.passwordError;
                    return null;
                  },
                ),
                if (!_isLogin) ...[
                  const SizedBox(height: 14),
                  _field(
                    controller: _confirm,
                    focusNode: _confirmFocus,
                    hint: isLt ? 'Pakartokite slaptažodį' : 'Confirm password',
                    icon: Icons.lock_outline,
                    obscure: _obscureConfirm,
                    onToggleObscure: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    validator: (v) {
                      if (v != _password.text) {
                        return isLt
                            ? 'Slaptažodžiai nesutampa.'
                            : 'Passwords do not match.';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 24),
                _openVaultButton(l, isLt),
                const SizedBox(height: 16),
                _toggleLink(isLt),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A dark "glass" input field.
  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    FocusNode? focusNode,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: !_busy,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: _accent,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.5)),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                onPressed: onToggleObscure,
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE57373)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE57373), width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFE57373)),
      ),
    );
  }

  /// The green-gradient primary action.
  Widget _openVaultButton(AppLocalizations l, bool isLt) {
    final label = _isLogin
        ? (isLt ? 'Prisijungti →' : 'Sign in →')
        : (isLt ? 'Sukurti paskyrą →' : 'Create account →');
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D4F), Color(0xFF4CAF72)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : _submit,
          child: SizedBox(
            height: 56,
            child: Center(
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggleLink(bool isLt) {
    final prefix = _isLogin
        ? (isLt ? 'Neturi paskyros? ' : 'No account? ')
        : (isLt ? 'Jau turi paskyrą? ' : 'Have an account? ');
    final action = _isLogin
        ? (isLt ? 'Sukurk nemokamai' : 'Create one free')
        : (isLt ? 'Prisijunk' : 'Sign in');
    return Center(
      child: GestureDetector(
        onTap: _busy
            ? null
            : () => setState(() {
                  _isLogin = !_isLogin;
                  _confirm.clear();
                }),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: prefix,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
              ),
              TextSpan(
                text: action,
                style: const TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
