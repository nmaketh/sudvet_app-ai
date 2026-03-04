import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../widgets/sudvet_circle_logo.dart';

const _bg1   = Color(0xFF0C2318);
const _bg2   = Color(0xFF0F2B1E);
const _glowG = Color(0xFF1F8A66);
const _brightG = Color(0xFF4BC997);

/// Shared scaffold for auth flows (signup, verify, forgot-password).
/// Mirrors the login page's split-screen design: dark brand top + white form card.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.logoSize = 72.0,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final formBg = isDark ? const Color(0xFF0F1B14) : Colors.white;
    final labelC = isDark ? const Color(0xFFDFECE2) : const Color(0xFF1D2A25);
    final mutedC = isDark ? const Color(0xFF7A9C85) : const Color(0xFF65756F);

    return Scaffold(
      backgroundColor: _bg1,
      body: Stack(
        children: [
          // Full-screen brand gradient
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

          // Ambient glow blob
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _glowG.withValues(alpha: 0.12),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Brand section (compact for non-login auth pages)
                SizedBox(
                  height: 180,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, child) => Opacity(
                      opacity: v,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - v)),
                        child: child,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: logoSize + 26,
                                height: logoSize + 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _glowG.withValues(alpha: 0.14),
                                  border: Border.all(
                                    color: _brightG.withValues(alpha: 0.16),
                                    width: 1.2,
                                  ),
                                ),
                              ),
                              SudVetCircleLogo(
                                size: logoSize,
                                showOuterRing: false,
                                backgroundColor: const Color(0xFF1A3E28),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'SudVet',
                            style: GoogleFonts.sora(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Form card
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, child) => Transform.translate(
                      offset: Offset(0, 24 * (1 - v)),
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
                            color: Colors.black.withValues(alpha: 0.26),
                            blurRadius: 36,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  title,
                                  style: GoogleFonts.sora(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                    color: labelC,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  subtitle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: mutedC,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                child,
                              ],
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
    );
  }
}
