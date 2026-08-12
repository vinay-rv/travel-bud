/// Lightweight date/time formatting so we don't depend on `intl` yet.
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// e.g. "1 Mar 2026"
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// e.g. "1 Mar 2026, 11:00 AM"
String formatDateTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${formatDate(d)}, $hour12:$minute $ampm';
}

/// e.g. "11:00 AM"
String formatTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $ampm';
}

/// e.g. "1–8 Mar 2026" or "28 Feb – 3 Mar 2026" for cross-month ranges.
String formatDateRange(DateTime start, DateTime end) {
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}–${end.day} ${_months[start.month - 1]} ${start.year}';
  }
  if (start.year == end.year) {
    return '${start.day} ${_months[start.month - 1]} – '
        '${end.day} ${_months[end.month - 1]} ${end.year}';
  }
  return '${formatDate(start)} – ${formatDate(end)}';
}
