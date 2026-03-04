import 'package:flutter/material.dart';

import '../features/cases/model/case_record.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final CaseStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color background;
    Color foreground;

    switch (status) {
      case CaseStatus.pending:
        background = const Color(0xFFFBF1DD);
        foreground = const Color(0xFF7A5A12);
      case CaseStatus.synced:
        background = const Color(0xFFE4F0E6);
        foreground = const Color(0xFF225C3A);
      case CaseStatus.failed:
        background = const Color(0xFFF7E1DA);
        foreground = const Color(0xFF8A2D1F);
    }

    return Semantics(
      label: 'Case status ${status.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground.withValues(alpha: 0.18)),
        ),
        child: Text(
          status.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
