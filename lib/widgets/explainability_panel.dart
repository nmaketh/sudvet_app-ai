import 'package:flutter/material.dart';

/// Collapsible panel that shows the AI reasoning behind a diagnosis.
///
/// Shows:
///   • Natural language reasoning text
///   • Top contributing symptoms (feature importance bars)
///   • Rule triggers as coloured chips
///   • Differential diagnosis (top 3 ranked alternatives)
class ExplainabilityPanel extends StatefulWidget {
  const ExplainabilityPanel({
    super.key,
    this.reasoning,
    this.featureImportance = const {},
    this.ruleTriggers = const [],
    this.differential = const [],
    this.temperatureNote,
    this.severityNote,
    this.initiallyExpanded = true,
  });

  final String? reasoning;
  final Map<String, double> featureImportance;
  final List<String> ruleTriggers;
  final List<Map<String, dynamic>> differential;
  final String? temperatureNote;
  final String? severityNote;
  final bool initiallyExpanded;

  @override
  State<ExplainabilityPanel> createState() => _ExplainabilityPanelState();
}

class _ExplainabilityPanelState extends State<ExplainabilityPanel>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController _ctrl;
  late final Animation<double> _sizeAnim;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: _expanded ? 1.0 : 0.0,
    );
    _sizeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasContent = widget.reasoning != null ||
        widget.featureImportance.isNotEmpty ||
        widget.ruleTriggers.isNotEmpty ||
        widget.differential.length > 1;

    if (!hasContent) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: _toggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.psychology_rounded,
                      size: 18,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Why this diagnosis?',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 280),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          SizeTransition(
            sizeFactor: _sizeAnim,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),

                // Reasoning text
                if (widget.reasoning != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(
                            color: cs.primary.withValues(alpha: 0.4),
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        widget.reasoning!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.6,
                          color: cs.onSurface.withValues(alpha: 0.80),
                        ),
                      ),
                    ),
                  ),
                ],

                // Context notes
                if (widget.temperatureNote != null || widget.severityNote != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (widget.temperatureNote != null)
                          _ContextChip(
                            icon: Icons.thermostat_rounded,
                            text: widget.temperatureNote!,
                            color: const Color(0xFFD94F3D),
                          ),
                        if (widget.severityNote != null)
                          _ContextChip(
                            icon: Icons.warning_amber_rounded,
                            text: widget.severityNote!,
                            color: const Color(0xFFE6A817),
                          ),
                      ],
                    ),
                  ),
                ],

                // Feature importance
                if (widget.featureImportance.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Text(
                      'Key contributing symptoms',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.50),
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _FeatureImportanceList(
                      importance: widget.featureImportance,
                      accentColor: cs.primary,
                    ),
                  ),
                ],

                // Rule triggers
                if (widget.ruleTriggers.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Text(
                      'Clinical rules triggered',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.50),
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.ruleTriggers.map((rule) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D4F).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF2E7D4F).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 12,
                                color: Color(0xFF2E7D4F),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                rule.replaceAll('_', ' '),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A5232),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                // Differential diagnosis
                if (widget.differential.length > 1) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Text(
                      'Differential diagnosis',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.50),
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      children: widget.differential
                          .skip(1) // skip top — already shown prominently
                          .take(3)
                          .map((entry) => _DifferentialRow(entry: entry))
                          .toList(),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ContextChip extends StatelessWidget {
  const _ContextChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureImportanceList extends StatelessWidget {
  const _FeatureImportanceList({
    required this.importance,
    required this.accentColor,
  });

  final Map<String, double> importance;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = importance.entries.take(6).toList();
    final maxVal = entries.fold(0.0, (m, e) => e.value > m ? e.value : m);

    return Column(
      children: entries.asMap().entries.map((e) {
        final idx = e.key;
        final symptom = e.value.key;
        final score = e.value.value;
        final fraction = maxVal > 0 ? score / maxVal : 0.0;
        final label = symptom.replaceAll('_', ' ');
        // Alpha decreases for lower-ranked symptoms
        final opacity = 1.0 - (idx * 0.10).clamp(0.0, 0.45);

        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            children: [
              // Rank
              SizedBox(
                width: 16,
                child: Text(
                  '${idx + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              // Label
              SizedBox(
                width: 140,
                child: Text(
                  _capitalise(label),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: opacity),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Bar
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: accentColor.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation(
                      accentColor.withValues(alpha: opacity),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Percentage
              SizedBox(
                width: 32,
                child: Text(
                  '${(score * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static String _capitalise(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

class _DifferentialRow extends StatelessWidget {
  const _DifferentialRow({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (entry['display_name'] ?? entry['disease'] ?? '').toString();
    final pct = entry['percentage'] is num
        ? (entry['percentage'] as num).toDouble()
        : double.tryParse(entry['percentage']?.toString() ?? '') ?? 0.0;
    final matched = (entry['matched_symptoms'] as List?)
        ?.map((s) => s.toString().replaceAll('_', ' '))
        .take(3)
        .toList() ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Score badge
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${pct.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Disease name and matched symptoms
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (matched.isNotEmpty)
                  Text(
                    matched.join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.50),
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
