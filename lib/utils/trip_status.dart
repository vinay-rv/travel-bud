import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Where a trip sits relative to today, so the UI can colour and label it.
enum TripPhase { upcoming, ongoing, past }

class TripStatus {
  final TripPhase phase;

  /// Short human label, e.g. "In 12 days", "Day 2 of 6", "Ended".
  final String label;
  final Color color;

  const TripStatus(this.phase, this.label, this.color);
}

/// Number of whole days between two calendar dates, ignoring the time of day.
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Inclusive trip length in days (a same-day trip counts as 1).
int tripLengthInDays(DateTime start, DateTime end) =>
    daysBetween(start, end) + 1;

TripStatus tripStatus(DateTime start, DateTime end, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final toStart = daysBetween(today, start);
  final toEnd = daysBetween(today, end);

  if (toEnd < 0) {
    return const TripStatus(TripPhase.past, 'Ended', AppColors.textFaint);
  }
  if (toStart <= 0) {
    final day = daysBetween(start, today) + 1;
    final total = tripLengthInDays(start, end);
    return TripStatus(TripPhase.ongoing, 'Day $day of $total', AppColors.mint);
  }
  if (toStart == 1) {
    return const TripStatus(TripPhase.upcoming, 'Tomorrow', AppColors.amber);
  }
  if (toStart < 30) {
    return TripStatus(
      TripPhase.upcoming,
      'In $toStart days',
      toStart <= 7 ? AppColors.amber : AppColors.primary,
    );
  }
  final months = (toStart / 30).round();
  return TripStatus(
    TripPhase.upcoming,
    'In $months month${months == 1 ? '' : 's'}',
    AppColors.primary,
  );
}
