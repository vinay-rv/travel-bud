import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/database_helper.dart';
import 'sync_engine.dart';

/// Decides *when* to sync, so nothing else has to.
///
/// Two moments matter, and neither needs a screen to cooperate:
///
///  * the user changed something — debounced, because packing a list is twenty
///    edits in ten seconds and that should be one upload, not twenty;
///  * the app came back to the foreground, which is when a phone that was in a
///    tunnel usually has signal again.
///
/// There is deliberately no connectivity plugin. A failed request is a perfectly
/// good connectivity check, and the engine already treats being offline as an
/// ordinary outcome rather than an error.
class SyncTrigger {
  final DatabaseHelper db;
  final SyncEngine Function() engine;
  final Duration debounce;

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _started = false;

  SyncTrigger({
    required this.db,
    required this.engine,
    this.debounce = const Duration(seconds: 3),
  });

  void start() {
    if (_started) return;
    _started = true;
    db.revision.addListener(_onChanged);
    _lifecycle = AppLifecycleListener(onResume: _syncNow);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    db.revision.removeListener(_onChanged);
    _lifecycle?.dispose();
    _lifecycle = null;
    _timer?.cancel();
    _timer = null;
  }

  void _onChanged() {
    _timer?.cancel();
    _timer = Timer(debounce, _syncNow);
  }

  void _syncNow() {
    // Fire and forget: `sync()` reports failure by returning, never by throwing,
    // and a sync that can't run right now simply runs later.
    unawaited(engine().sync());
  }
}
