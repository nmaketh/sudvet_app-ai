import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/validators.dart';
import '../../../widgets/sudvet_circle_logo.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

const _devServerSettingsEnabled = bool.fromEnvironment(
  'ENABLE_DEV_SERVER_SETTINGS',
  defaultValue: false,
);

// ── Brand palette (always applied, regardless of app theme) ──────────────────
const _bg1   = Color(0xFF0C2318);  // deep forest top-left
const _bg2   = Color(0xFF0F2B1E);  // deep forest bottom
const _glowG = Color(0xFF1F8A66);  // primary green
const _brightG = Color(0xFF4BC997);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  String? _inlineError;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _inlineError = null);
    context.read<AuthBloc>().add(
      AuthLoginRequested(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  bool get _hasConnectionIssue {
    final m = _inlineError?.toLowerCase() ?? '';
    if (m.isEmpty) return false;
    return m.contains('unable to reach') ||
        m.contains('server unavailable') ||
        m.contains('server is unavailable') ||
        m.contains('timed out') ||
        m.contains('waking up') ||
        m.contains('internet connection');
  }

  String get _displayErrorMessage {
    if (!_hasConnectionIssue) return _inlineError ?? '';
    return 'SudVet server unavailable. Retry or check connection.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Form card colors (switches with app theme; brand top is always dark)
    final formBg  = isDark ? const Color(0xFF0F1B14) : Colors.white;
    final labelC  = isDark ? const Color(0xFFDFECE2) : const Color(0xFF1D2A25);
    final mutedC  = isDark ? const Color(0xFF7A9C85) : const Color(0xFF65756F);
    final borderC = isDark ? const Color(0xFF253529) : const Color(0xFFD3E7DA);
    final fillC   = isDark ? const Color(0xFF162019) : const Color(0xFFF4FBF7);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthFailure) setState(() => _inlineError = state.message);
      },
      child: Scaffold(
        // ── Background: full-screen brand gradient ───────────────────────────
        backgroundColor: _bg1,
        body: Stack(
          children: [
            // Gradient
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_bg1, Color(0xFF122A1C), _bg2],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),

            // Ambient glow blob (top-right)
            Positioned(
              top: -70,
              right: -70,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _glowG.withValues(alpha: 0.13),
                ),
              ),
            ),

            // Ambient glow blob (bottom-left)
            Positioned(
              bottom: 200,
              left: -90,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _glowG.withValues(alpha: 0.07),
                ),
              ),
            ),

            // ── Content ────────────────────────────────────────────────────
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // ── Brand section (top) ─────────────────────────────────
                  Expanded(
                    flex: 5,
                    child: _BrandSection(),
                  ),

                  // ── Form card (bottom, slides up) ───────────────────────
                  Expanded(
                    flex: 7,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 540),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => Transform.translate(
                        offset: Offset(0, 28 * (1 - v)),
                        child: Opacity(opacity: v, child: child),
                      ),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: formBg,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 40,
                              offset: const Offset(0, -6),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Heading
                                    Text(
                                      'Sign in',
                                      style: GoogleFonts.sora(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                        color: labelC,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Access your SudVet account to continue.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: mutedC,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 22),

                                    // Email
                                    _FieldLabel(text: 'Email address', color: labelC),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.email],
                                      validator: (v) => Validators.email(v ?? ''),
                                      style: theme.textTheme.bodyLarge?.copyWith(color: labelC),
                                      decoration: _fieldDecor(
                                        hint: 'you@cattle.ai',
                                        icon: Icons.alternate_email_rounded,
                                        fillColor: fillC,
                                        borderColor: borderC,
                                        mutedColor: mutedC,
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // Password
                                    _FieldLabel(text: 'Password', color: labelC),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [AutofillHints.password],
                                      onFieldSubmitted: (_) => _submit(),
                                      validator: (v) =>
                                          Validators.required(v ?? '', label: 'Password'),
                                      style: theme.textTheme.bodyLarge?.copyWith(color: labelC),
                                      decoration: _fieldDecor(
                                        hint: '••••••••',
                                        icon: Icons.lock_outline_rounded,
                                        fillColor: fillC,
                                        borderColor: borderC,
                                        mutedColor: mutedC,
                                        suffix: IconButton(
                                          onPressed: () => setState(
                                            () => _obscurePassword = !_obscurePassword,
                                          ),
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                            color: mutedC,
                                            size: 19,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Forgot password
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () => context.go('/forgot-password'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: _glowG,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 6,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'Forgot password?',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: _glowG,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Error banner
                                    AnimatedSize(
                                      duration: const Duration(milliseconds: 220),
                                      curve: Curves.easeOutCubic,
                                      child: _inlineError == null
                                          ? const SizedBox.shrink()
                                          : Container(
                                              margin: const EdgeInsets.only(bottom: 12),
                                              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFDE9E4),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: const Color(0xFFEDC0B4),
                                                ),
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Icon(
                                                    Icons.error_outline_rounded,
                                                    size: 16,
                                                    color: Color(0xFF8F4434),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      _displayErrorMessage,
                                                      style: const TextStyle(
                                                        color: Color(0xFF8F4434),
                                                        fontSize: 12.5,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  if (_hasConnectionIssue)
                                                    TextButton(
                                                      onPressed: () {
                                                        if (_formKey.currentState?.validate() ??
                                                            false) {
                                                          _submit();
                                                        }
                                                      },
                                                      style: TextButton.styleFrom(
                                                        foregroundColor: const Color(0xFF8F4434),
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                        ),
                                                        minimumSize: Size.zero,
                                                        tapTargetSize:
                                                            MaterialTapTargetSize.shrinkWrap,
                                                      ),
                                                      child: const Text(
                                                        'Retry',
                                                        style: TextStyle(fontSize: 12.5),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                    ),

                                    // Sign in button
                                    BlocBuilder<AuthBloc, AuthState>(
                                      builder: (context, state) {
                                        final loading = state is AuthAuthenticating &&
                                            !state.checkingSession;
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            SizedBox(
                                              height: 52,
                                              child: FilledButton(
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: _glowG,
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                  elevation: 0,
                                                ),
                                                onPressed: loading ? null : _submit,
                                                child: loading
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          valueColor:
                                                              AlwaysStoppedAnimation<Color>(
                                                            Colors.white,
                                                          ),
                                                        ),
                                                      )
                                                    : Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment.center,
                                                        children: [
                                                          Text(
                                                            'Sign in',
                                                            style: GoogleFonts.manrope(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.w700,
                                                              color: Colors.white,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          const Icon(
                                                            Icons.arrow_forward_rounded,
                                                            size: 17,
                                                            color: Colors.white,
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  "Don't have an account? ",
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: mutedC,
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed:
                                                      loading ? null : () => context.go('/signup'),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: _glowG,
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 2,
                                                    ),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                  child: Text(
                                                    'Create account',
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: _glowG,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      },
                                    ),

                                    if (_devServerSettingsEnabled)
                                      Align(
                                        alignment: Alignment.center,
                                        child: TextButton(
                                          onPressed: () => context.push('/setup-api'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: mutedC,
                                          ),
                                          child: const Text(
                                            'Server settings',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecor({
    required String hint,
    required IconData icon,
    required Color fillColor,
    required Color borderColor,
    required Color mutedColor,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: mutedColor.withValues(alpha: 0.6), fontSize: 14),
      filled: true,
      fillColor: fillColor,
      prefixIcon: Icon(icon, color: mutedColor, size: 19),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _glowG, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }
}

// ── Brand section (dark top) ──────────────────────────────────────────────────

class _BrandSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo with glow ring — no rectangle
            Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring
                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _glowG.withValues(alpha: 0.15),
                  ),
                ),
                // Inner accent ring
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _glowG.withValues(alpha: 0.12),
                    border: Border.all(
                      color: _brightG.withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                ),
                // Logo
                SudVetCircleLogo(
                  size: 88,
                  showOuterRing: false,
                  backgroundColor: const Color(0xFF1A3E28),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Wordmark
            Text(
              'SudVet',
              style: GoogleFonts.sora(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 5),

            // Tagline with status dot
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _brightG,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'Field Veterinary AI',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: const Color(0xFF6BA88A),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.15,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Field label ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
    );
  }
}
