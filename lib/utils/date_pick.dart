import 'package:flutter/material.dart';

/// Prompts for a date and then a time, returning the combined [DateTime].
/// Returns null if the user cancels either step.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  required DateTime initial,
}) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (date == null) return null;
  if (!context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
