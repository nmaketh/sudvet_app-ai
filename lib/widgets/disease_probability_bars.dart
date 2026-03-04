import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Displays an animated horizontal probability bar for each disease category.
///
/// Pass [probabilities] as a map of disease-key → 0..1 score.
/// The top disease is highlighted with a star badge and bolder text.
class DiseaseProbabilityBars extends StatelessWidget {
  const DiseaseProbabilityBars({
    super.key,
    required this.probabilities,
    this.topDisease,
  });

  final Map<String, double> probabilities;
  final String? topDisease;

  static const _order = ['lsd', 'fmd', 'ecf', 'cbpp', 'normal'];
  static const _labels = {
    'lsd':    'LSD',
    'fmd':    'FMD',
    'ecf':    'ECF',
    'cbpp':   'CBPP',
    'normal': 'Normal',
  };
  static const _fullLabels = {
    'lsd':    'Lumpy Skin Disease',
    'fmd':    'Foot & Mouth Disease',
    'ecf':    'East Coast Fever',
    'cbpp':   'CBPP',
    'normal': 'No Disease',
  };

  @override
  Widget build(BuildContext context) {
    final dc = Theme.of(context).extension<DiseaseColors>() ?? DiseaseColors.light;
    final keys = _order.where((k) => probabilities.containsKey(k)).toList();
    if (keys.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: keys.map((key) {
        final score = (probabilities[key] ?? 0.0).clamp(0.0, 1.0);
        final isTop = topDisease == key;
        final barColor = dc.colorFor(key);
        final textColor = dc.onSurfaceFor(key);
        return _DiseaseBar(
          key: ValueKey(key),
          diseaseKey: key,
          label: _labels[key] ?? key.toUpperCase(),
          fullLabel: _fullLabels[key] ?? key,
          score: score,
          barColor: barColor,
          textColor: textColor,
          isTop: isTop,
        );
      }).toList(),
    );
  }
}

class _DiseaseBar extends StatefulWidget {
  const _DiseaseBar({
    super.key,
    required this.diseaseKey,
    required this.label,
    required this.fullLabel,
    required this.score,
    required this.barColor,
    required this.textColor,
    required this.isTop,
  });

  final String diseaseKey;
  final String label;
  final String fullLabel;
  final double score;
  final Color barColor;
  final Color textColor;
  final bool isTop;

  @override
  State<_DiseaseBar> createState() => _DiseaseBarState();
}

class _DiseaseBarState extends State<_DiseaseBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final animScore = _anim.value * widget.score;
          return Row(
            children: [
              // Disease label
              SizedBox(
                width: 52,
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: widget.isTop
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: widget.isTop
                        ? widget.textColor
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Bar track
              Expanded(
                child: Stack(
                  children: [
                    // Track
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: trackColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    // Fill
                    FractionallySizedBox(
                      widthFactor: animScore.clamp(0.0, 1.0),
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.barColor,
                              widget.barColor.withValues(alpha: 0.75),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Percentage
              SizedBox(
                width: 42,
                child: Text(
                  '${(widget.score * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: widget.isTop ? FontWeight.w800 : FontWeight.w500,
                    color: widget.isTop
                        ? widget.textColor
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              // Top star indicator
              if (widget.isTop)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: widget.textColor,
                  ),
                )
              else
                const SizedBox(width: 18),
            ],
          );
        },
      ),
    );
  }
}
