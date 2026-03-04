import 'package:equatable/equatable.dart';

class DashboardTrendPoint extends Equatable {
  const DashboardTrendPoint({required this.label, required this.count});

  final String label;
  final int count;

  @override
  List<Object?> get props => [label, count];
}

class DashboardStats extends Equatable {
  const DashboardStats({
    required this.totalCases,
    required this.pendingCases,
    required this.syncedCases,
    required this.failedCases,
    required this.lastSyncAt,
    required this.diseaseCounts,
    required this.weeklyTrend,
  });

  final int totalCases;
  final int pendingCases;
  final int syncedCases;
  final int failedCases;
  final DateTime? lastSyncAt;
  final Map<String, int> diseaseCounts;
  final List<DashboardTrendPoint> weeklyTrend;

  factory DashboardStats.empty() {
    return const DashboardStats(
      totalCases: 0,
      pendingCases: 0,
      syncedCases: 0,
      failedCases: 0,
      lastSyncAt: null,
      diseaseCounts: {},
      weeklyTrend: [],
    );
  }

  DashboardStats copyWith({
    int? totalCases,
    int? pendingCases,
    int? syncedCases,
    int? failedCases,
    DateTime? lastSyncAt,
    Map<String, int>? diseaseCounts,
    List<DashboardTrendPoint>? weeklyTrend,
  }) {
    return DashboardStats(
      totalCases: totalCases ?? this.totalCases,
      pendingCases: pendingCases ?? this.pendingCases,
      syncedCases: syncedCases ?? this.syncedCases,
      failedCases: failedCases ?? this.failedCases,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      diseaseCounts: diseaseCounts ?? this.diseaseCounts,
      weeklyTrend: weeklyTrend ?? this.weeklyTrend,
    );
  }

  @override
  List<Object?> get props => [
    totalCases,
    pendingCases,
    syncedCases,
    failedCases,
    lastSyncAt,
    diseaseCounts,
    weeklyTrend,
  ];
}
