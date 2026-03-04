import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme.dart';
import '../../../core/api/base_url_resolver.dart';
import '../../../widgets/disease_probability_bars.dart';
import '../../../widgets/explainability_panel.dart';
import '../../settings/data/settings_repository.dart';
import '../bloc/case_bloc.dart';
import '../bloc/case_event.dart';
import '../bloc/case_state.dart';
import '../model/case_record.dart';

// ── Disease display names ─────────────────────────────────────────────────────

const _diseaseDisplay = {
  'lsd':    'Lumpy Skin Disease',
  'fmd':    'Foot & Mouth Disease',
  'ecf':    'East Coast Fever',
  'cbpp':   'Contagious Bovine Pleuropneumonia',
  'normal': 'No Disease Detected',
};

const _diseaseShort = {
  'lsd':    'LSD',
  'fmd':    'FMD',
  'ecf':    'ECF',
  'cbpp':   'CBPP',
  'normal': 'Normal',
};

// ── Page ──────────────────────────────────────────────────────────────────────

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.caseId});

  final String caseId;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heroCtrl;
  late final Animation<double> _heroFade;

  @override
  void initState() {
    super.initState();
    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CaseBloc>().add(CaseOpenedById(widget.caseId));
      _heroCtrl.forward();
    });
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: BlocBuilder<CaseBloc, CaseState>(
        builder: (context, state) {
          final item = state.selectedCase;
          if (item == null || item.id != widget.caseId) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return _NotFoundView(
              onHistory: () => context.go('/app/history'),
            );
          }
          return _ResultBody(
            item: item,
            heroFade: _heroFade,
            onViewCase: () => context.push('/app/case/${item.id}'),
            onNewCase: () => context.go('/app/new-case'),
            onSync: () => context
                .read<CaseBloc>()
                .add(const CasePendingSyncRequested()),
          );
        },
      ),
    );
  }
}

// ── Result body ───────────────────────────────────────────────────────────────

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.item,
    required this.heroFade,
    required this.onViewCase,
    required this.onNewCase,
    required this.onSync,
  });

  final CaseRecord item;
  final Animation<double> heroFade;
  final VoidCallback onViewCase;
  final VoidCallback onNewCase;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final dc = Theme.of(context).extension<DiseaseColors>() ?? DiseaseColors.light;
    final diseaseKey = item.diseaseKey;
    final accent = dc.colorFor(diseaseKey);
    final onAccent = dc.onSurfaceFor(diseaseKey);
    final confidence = item.confidence;
    final probabilities = item.allProbabilities;
    final recommendations = item.recommendations.isEmpty
        ? _defaultRecommendations(diseaseKey)
        : item.recommendations;

    return CustomScrollView(
      slivers: [
        // ── Hero SliverAppBar ────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 210,
          pinned: true,
          backgroundColor: accent,
          foregroundColor: onAccent,
          flexibleSpace: FlexibleSpaceBar(
            background: FadeTransition(
              opacity: heroFade,
              child: _HeroHeader(
                diseaseKey: diseaseKey,
                accent: accent,
                onAccent: onAccent,
                confidence: confidence,
                status: item.status,
                urgency: item.urgency,
                method: item.method,
              ),
            ),
          ),
          title: Text(
            _diseaseShort[diseaseKey] ?? 'Result',
            style: GoogleFonts.sora(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: onAccent,
            ),
          ),
        ),

        // ── Content ──────────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Low-confidence banner
              if (confidence != null && confidence < 0.55) ...[
                _LowConfidenceBanner(confidence: confidence),
                const SizedBox(height: 12),
              ],

              // Probability distribution
              if (probabilities.isNotEmpty) ...[
                _PanelCard(
                  title: 'Disease Probability Distribution',
                  icon: Icons.bar_chart_rounded,
                  child: DiseaseProbabilityBars(
                    probabilities: probabilities,
                    topDisease: diseaseKey,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Case images
              if (_imagePaths(item).isNotEmpty) ...[
                _PanelCard(
                  title: 'Case Images',
                  icon: Icons.photo_library_rounded,
                  child: _ImagesRow(imagePaths: _imagePaths(item)),
                ),
                const SizedBox(height: 12),
              ],

              // AI explainability
              ExplainabilityPanel(
                reasoning: item.reasoningText,
                featureImportance: item.featureImportance,
                ruleTriggers: item.ruleTriggers,
                differential: item.differential,
                temperatureNote: item.temperatureNote,
                severityNote: item.severityNote,
              ),
              if (item.reasoningText != null ||
                  item.featureImportance.isNotEmpty)
                const SizedBox(height: 12),

              // Grad-CAM (if available)
              if (item.gradcamPath != null) ...[
                _PanelCard(
                  title: 'Visual Saliency Map (Grad-CAM)',
                  icon: Icons.visibility_rounded,
                  child: _GradCamView(path: item.gradcamPath!),
                ),
                const SizedBox(height: 12),
              ],

              // Recommended actions
              _PanelCard(
                title: 'Recommended Actions',
                icon: Icons.checklist_rounded,
                accentBg: accent.withValues(alpha: 0.08),
                accentBorder: onAccent.withValues(alpha: 0.18),
                child: _RecommendationsList(
                  items: recommendations,
                  accentColor: accent,
                  checkColor: onAccent,
                ),
              ),
              const SizedBox(height: 12),

              // Action buttons
              _ActionButtons(
                status: item.status,
                onViewCase: onViewCase,
                onNewCase: onNewCase,
                onSync: onSync,
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ],
    );
  }

  List<String> _imagePaths(CaseRecord item) {
    final out = <String>[];
    final seen = <String>{};
    if (item.imagePath != null && item.imagePath!.trim().isNotEmpty) {
      if (seen.add(item.imagePath!.trim())) out.add(item.imagePath!.trim());
    }
    for (final p in item.attachments) {
      final s = p.trim();
      if (s.isNotEmpty && seen.add(s)) out.add(s);
    }
    return out;
  }

  List<String> _defaultRecommendations(String key) {
    switch (key) {
      case 'lsd':
        return [
          'Isolate the affected animal immediately',
          'Clean and disinfect shared areas',
          'Contact veterinarian for confirmatory diagnosis',
          'Monitor herd for new skin lesions',
        ];
      case 'fmd':
        return [
          'Restrict all herd movement immediately',
          'Notify animal health authority — FMD is notifiable',
          'Provide soft feed and clean water',
          'Do not move animals off-farm',
        ];
      case 'ecf':
        return [
          'Contact veterinarian urgently — ECF can be fatal',
          'Control ticks with approved acaricide',
          'Isolate and shade affected animals',
          'Do not stress the animal further',
        ];
      case 'cbpp':
        return [
          'Isolate affected animal from herd',
          'Report to local animal health authority',
          'Vaccinate healthy herd',
          'Improve housing ventilation',
        ];
      default:
        return [
          'Continue daily health observation',
          'Maintain vaccination schedule',
          'Resubmit case if symptoms develop',
        ];
    }
  }
}

// ── Hero header ───────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.diseaseKey,
    required this.accent,
    required this.onAccent,
    required this.confidence,
    required this.status,
    required this.urgency,
    required this.method,
  });

  final String diseaseKey;
  final Color accent;
  final Color onAccent;
  final double? confidence;
  final CaseStatus status;
  final String urgency;
  final String? method;

  @override
  Widget build(BuildContext context) {
    final display = _diseaseDisplay[diseaseKey] ?? 'Unknown';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.70)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 60,
        20,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status chips row
          Wrap(
            spacing: 6,
            children: [
              _SmallChip(
                label: status.label,
                color: onAccent,
              ),
              _SmallChip(
                label: '$urgency urgency',
                color: onAccent,
                icon: urgency.toLowerCase() == 'high'
                    ? Icons.warning_amber_rounded
                    : null,
              ),
              if (method != null && method!.trim().isNotEmpty)
                _SmallChip(
                  label: method!.replaceAll('_', ' '),
                  color: onAccent,
                  icon: Icons.science_rounded,
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Disease name
          Text(
            display,
            style: GoogleFonts.sora(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: onAccent,
              height: 1.1,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          // Confidence
          Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 3.5,
                      color: onAccent.withValues(alpha: 0.20),
                    ),
                    CircularProgressIndicator(
                      value: (confidence ?? 0.0).clamp(0.0, 1.0),
                      strokeWidth: 3.5,
                      color: onAccent,
                      strokeCap: StrokeCap.round,
                    ),
                    Center(
                      child: Text(
                        confidence != null
                            ? '${(confidence! * 100).toStringAsFixed(0)}%'
                            : '--',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: onAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      confidence != null
                          ? 'Confidence: ${(confidence! * 100).toStringAsFixed(1)}%'
                          : 'Confidence pending sync',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: onAccent,
                      ),
                    ),
                    Text(
                      confidence != null
                          ? (confidence! >= 0.75
                              ? 'High confidence — strong clinical match'
                              : confidence! >= 0.55
                                  ? 'Moderate — consider better photo'
                                  : 'Low — retake photo in daylight')
                          : 'Will appear after sync',
                      style: TextStyle(
                        fontSize: 11,
                        color: onAccent.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Panel card ────────────────────────────────────────────────────────────────

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.icon,
    required this.child,
    this.accentBg,
    this.accentBorder,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Color? accentBg;
  final Color? accentBorder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: accentBg ?? cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accentBorder ?? cs.outline.withValues(alpha: 0.20),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.65),
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Images row ────────────────────────────────────────────────────────────────

class _ImagesRow extends StatelessWidget {
  const _ImagesRow({required this.imagePaths});

  final List<String> imagePaths;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: imagePaths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => SizedBox(
          width: 140,
          child: _CaseImageTile(path: imagePaths[i]),
        ),
      ),
    );
  }
}

/// Displays a single case image from either a local file path or a server URL.
class _CaseImageTile extends StatelessWidget {
  const _CaseImageTile({required this.path});

  final String path;

  static Widget _placeholder(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );

  static Widget _broken(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Icon(Icons.broken_image_outlined, size: 28)),
      );

  @override
  Widget build(BuildContext context) {
    // Absolute network URL or blob URL (Flutter web image_picker returns blob: URLs)
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('blob:')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          path,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, prog) =>
              prog == null ? child : _placeholder(context),
          errorBuilder: (_, _, _) => _broken(context),
        ),
      );
    }

    // Server-relative path (e.g. /uploads/abc.jpg) — prepend resolved base URL
    if (path.startsWith('/')) {
      return FutureBuilder<String>(
        future: BaseUrlResolver.resolve(),
        builder: (context, snap) {
          if (!snap.hasData) return _placeholder(context);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              '${snap.data}$path',
              fit: BoxFit.cover,
              loadingBuilder: (_, child, prog) =>
                  prog == null ? child : _placeholder(context),
              errorBuilder: (_, _, _) => _broken(context),
            ),
          );
        },
      );
    }

    // Local file path (native platforms)
    return FutureBuilder<Uint8List>(
      future: XFile(path).readAsBytes(),
      builder: (context, snap) {
        if (snap.hasError || (snap.connectionState == ConnectionState.done && !snap.hasData)) {
          return _broken(context);
        }
        if (!snap.hasData) return _placeholder(context);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _broken(context),
          ),
        );
      },
    );
  }
}

// ── Recommendations ───────────────────────────────────────────────────────────

class _RecommendationsList extends StatefulWidget {
  const _RecommendationsList({
    required this.items,
    required this.accentColor,
    required this.checkColor,
  });

  final List<String> items;
  final Color accentColor;
  final Color checkColor;

  @override
  State<_RecommendationsList> createState() => _RecommendationsListState();
}

class _RecommendationsListState extends State<_RecommendationsList> {
  late final List<bool> _checked;

  @override
  void initState() {
    super.initState();
    _checked = List.filled(widget.items.length, false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(widget.items.length, (i) {
        final done = _checked[i];
        return InkWell(
          onTap: () => setState(() => _checked[i] = !done),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? widget.accentColor
                        : Colors.transparent,
                    border: Border.all(
                      color: done
                          ? widget.accentColor
                          : cs.outline.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: done
                      ? Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: widget.checkColor,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.items[i],
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      decoration:
                          done ? TextDecoration.lineThrough : null,
                      color: done
                          ? cs.onSurface.withValues(alpha: 0.40)
                          : cs.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ── Low confidence banner ─────────────────────────────────────────────────────

class _LowConfidenceBanner extends StatelessWidget {
  const _LowConfidenceBanner({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE6A817).withValues(alpha: 0.50),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFF7A5A00),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Low confidence (${(confidence * 100).toStringAsFixed(0)}%). '
              'Retake a clearer photo in daylight and resubmit for better accuracy.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7A5A00),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action buttons ────────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.status,
    required this.onViewCase,
    required this.onNewCase,
    required this.onSync,
  });

  final CaseStatus status;
  final VoidCallback onViewCase;
  final VoidCallback onNewCase;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onViewCase,
          icon: const Icon(Icons.manage_search_rounded, size: 18),
          label: const Text('View Full Case Details'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onNewCase,
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: const Text('Submit New Case'),
        ),
        if (status == CaseStatus.pending) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onSync,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Sync to Server'),
          ),
        ],
      ],
    );
  }
}

// ── Grad-CAM view ─────────────────────────────────────────────────────────────

class _GradCamView extends StatelessWidget {
  const _GradCamView({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: _resolveUrl(context, path),
      builder: (context, snap) {
        final resolved = snap.data?.trim() ?? path;
        final isRemote = resolved.startsWith('http://') ||
            resolved.startsWith('https://');
        if (!isRemote) {
          return Container(
            height: 120,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'Grad-CAM map: $resolved',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            resolved,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              height: 90,
              color: cs.surfaceContainerHighest,
              child: const Center(
                child: Text('Could not load saliency map.'),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String> _resolveUrl(BuildContext context, String value) async {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (!value.startsWith('/')) return value;
    final settings = await context.read<SettingsRepository>().load();
    final base = settings.apiBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return base.isEmpty ? value : '$base$value';
  }
}

// ── Not-found view ────────────────────────────────────────────────────────────

class _NotFoundView extends StatelessWidget {
  const _NotFoundView({required this.onHistory});

  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.find_in_page_outlined,
              size: 56,
              color: cs.onSurface.withValues(alpha: 0.30),
            ),
            const SizedBox(height: 16),
            Text(
              'This case is no longer available.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onHistory,
              child: const Text('Go to History'),
            ),
          ],
        ),
      ),
    );
  }
}
