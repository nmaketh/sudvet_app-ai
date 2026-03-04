import 'package:flutter/material.dart';

const _logoAsset = 'assets/branding/sudvet_logo.png';

class SudVetCircleLogo extends StatelessWidget {
  const SudVetCircleLogo({
    super.key,
    this.size = 92,
    this.showOuterRing = true,
    this.backgroundColor,
  });

  final double size;
  final bool showOuterRing;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ringColor = isDark ? const Color(0xFF2F3D32) : const Color(0xFFD8E2D8);
    final innerBg =
        backgroundColor ?? (isDark ? const Color(0xFF1A231D) : const Color(0xFFF2F6EE));
    final imageSize = size * 0.62;

    Widget logoContent = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: innerBg,
        border: Border.all(color: ringColor, width: 1.2),
      ),
      child: ClipOval(
        child: Image.asset(
          _logoAsset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Text(
                'SV',
                style: TextStyle(
                  color: const Color(0xFF2E7D4F),
                  fontSize: size * 0.24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            );
          },
        ),
      ),
    );

    if (!showOuterRing) {
      return SizedBox(width: size, height: size, child: logoContent);
    }

    return Container(
      width: size + 10,
      height: size + 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor.withValues(alpha: 0.7), width: 1.2),
      ),
      child: Center(
        child: SizedBox(
          width: imageSize + (size - imageSize),
          height: imageSize + (size - imageSize),
          child: logoContent,
        ),
      ),
    );
  }
}
