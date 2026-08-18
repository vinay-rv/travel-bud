import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'column_codec.dart';
import 'sync_remote.dart';

/// The real server, talking to Supabase over PostgREST.
///
/// This is the only file in the app that imports `supabase_flutter` — the same
/// containment `notification_platform.dart` gives the notifications plugin. The
/// sync engine above it is testable precisely because none of this leaks
/// upwards.
///
/// Nothing here sends `user_id`: the Postgres columns default it to
/// `auth.uid()`, and row level security rejects any attempt to set it to
/// someone else. That is what makes "claim my data on first sync" free — rows
/// simply land owned by whoever pushed them.
class SupabaseRemote implements SyncRemote {
  final SupabaseClient client;

  SupabaseRemote({SupabaseClient? client})
    : client = client ?? Supabase.instance.client;

  @override
  Future<String?> currentUserId() async => client.auth.currentUser?.id;

  @override
  Future<String> signInAnonymously() async {
    return _guard(() async {
      final response = await client.auth.signInAnonymously();
      final user = response.user;
      if (user == null) {
        throw StateError('Signed in anonymously but got no user back');
      }
      return user.id;
    });
  }

  @override
  Future<void> signOut() => _guard(() => client.auth.signOut());

  @override
  Future<List<PushedRow>> pushUpserts(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return const [];

    return _guard(() async {
      final response = await client
          .from(table)
          .upsert(rows.map(encodeRow).toList(), onConflict: 'uuid')
          // The server assigns updated_at; read back what it decided, because
          // that value is the cursor every future pull is measured against.
          .select('uuid, updated_at');

      return response
          .map(
            (row) => PushedRow(
              uuid: row['uuid'] as String,
              serverUpdatedAt: (row['updated_at'] as num).toInt(),
            ),
          )
          .toList();
    });
  }

  @override
  Future<void> pushDeletes(List<Tombstone> deletes) async {
    if (deletes.isEmpty) return;

    await _guard(() async {
      // Deletes are soft server-side: another device has to be able to learn
      // that the row went away. Locally the row is really gone.
      final byTable = <String, List<Tombstone>>{};
      for (final tombstone in deletes) {
        byTable.putIfAbsent(tombstone.table, () => []).add(tombstone);
      }

      for (final entry in byTable.entries) {
        await client
            .from(entry.key)
            .update({'deleted_at': entry.value.first.deletedAt})
            .inFilter('uuid', entry.value.map((t) => t.uuid).toList());
      }
    });
  }

  @override
  Future<List<RemoteRow>> pull(String table, {required int sinceMs}) async {
    return _guard(() async {
      final response = await client
          .from(table)
          .select()
          .gt('updated_at', sinceMs)
          .order('updated_at', ascending: true);

      return response.map((row) {
        final decoded = decodeRow(row);
        return RemoteRow(
          uuid: decoded['uuid'] as String,
          values: decoded,
          serverUpdatedAt: (decoded['updatedAt'] as num).toInt(),
          deletedAt: (decoded['deletedAt'] as num?)?.toInt(),
        );
      }).toList();
    });
  }

  /// Turns "can't reach the server" into [SyncUnavailable], which the engine
  /// treats as an ordinary quiet outcome.
  ///
  /// Being offline is the normal state of a travel app — on a plane, on a
  /// foreign SIM, in a hotel basement — so it must never surface as an error.
  /// Anything else (a schema mismatch, a broken policy) is a real bug and is
  /// left to propagate rather than being swallowed into silence.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SocketException catch (e) {
      throw SyncUnavailable(e);
    } on TimeoutException catch (e) {
      throw SyncUnavailable(e);
    } on AuthException catch (e) {
      // An expired or unrefreshable session is a "come back later", not a bug.
      throw SyncUnavailable(e);
    } on PostgrestException catch (e) {
      // PostgREST reports transport-level trouble with an empty code; genuine
      // API errors (RLS denials, constraint violations) carry one and should
      // be loud, because they mean the client and schema disagree.
      if (e.code == null) throw SyncUnavailable(e);
      rethrow;
    }
  }
}
