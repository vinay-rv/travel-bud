import 'package:flutter_test/flutter_test.dart';

import 'package:packmate/sync/column_codec.dart';

/// The app speaks camelCase and Postgres speaks snake_case. If this translation
/// is wrong the failure is a rejected push or a silently missing column, not a
/// compile error — so every column of every synced table is pinned here against
/// the names in supabase/migrations/0001_initial_sync_schema.sql.
void main() {
  group('Name conversion', () {
    test('camelCase to snake_case', () {
      expect(camelToSnake('name'), 'name');
      expect(camelToSnake('startDate'), 'start_date');
      expect(camelToSnake('checkOutAt'), 'check_out_at');
      expect(camelToSnake('tripUuid'), 'trip_uuid');
      expect(camelToSnake('uuid'), 'uuid');
    });

    test('snake_case to camelCase', () {
      expect(snakeToCamel('name'), 'name');
      expect(snakeToCamel('start_date'), 'startDate');
      expect(snakeToCamel('check_out_at'), 'checkOutAt');
      expect(snakeToCamel('trip_uuid'), 'tripUuid');
      expect(snakeToCamel('uuid'), 'uuid');
    });

    test('every synced column survives a round trip', () {
      const columns = [
        'uuid', 'name', 'startDate', 'endDate',
        'tripUuid', 'hotelName', 'checkInAt', 'checkOutAt',
        'type', 'departureAt', 'fromLocation', 'toLocation',
        'category', 'quantity', 'packed',
        'createdAt', 'listUuid',
      ];
      for (final column in columns) {
        expect(
          snakeToCamel(camelToSnake(column)),
          column,
          reason: '$column did not survive the round trip',
        );
      }
    });
  });

  group('Encoding matches the Postgres schema', () {
    // Each expectation below is the actual column list from the migration.
    test('trips', () {
      final encoded = encodeRow({
        'uuid': 'u',
        'name': 'Northeast India',
        'startDate': 1772323200000,
        'endDate': 1772928000000,
      });
      expect(encoded.keys, ['uuid', 'name', 'start_date', 'end_date']);
      expect(encoded['start_date'], 1772323200000);
    });

    test('stays', () {
      final encoded = encodeRow({
        'uuid': 'u',
        'tripUuid': 't',
        'hotelName': 'Hotel Polo Towers',
        'checkInAt': 1,
        'checkOutAt': 2,
      });
      expect(encoded.keys, [
        'uuid',
        'trip_uuid',
        'hotel_name',
        'check_in_at',
        'check_out_at',
      ]);
    });

    test('transport_legs', () {
      final encoded = encodeRow({
        'uuid': 'u',
        'tripUuid': 't',
        'type': 'train',
        'departureAt': 1,
        'fromLocation': 'Guwahati',
        'toLocation': 'Shillong',
      });
      expect(encoded.keys, [
        'uuid',
        'trip_uuid',
        'type',
        'departure_at',
        'from_location',
        'to_location',
      ]);
    });

    test('items', () {
      final encoded = encodeRow({
        'uuid': 'u',
        'tripUuid': 't',
        'name': 'T-shirts',
        'category': 'clothes',
        'quantity': 3,
        'packed': 0,
      });
      expect(encoded.keys, [
        'uuid',
        'trip_uuid',
        'name',
        'category',
        'quantity',
        'packed',
      ]);
    });

    test('packing_lists and packing_list_items', () {
      expect(
        encodeRow({'uuid': 'u', 'name': 'Hill trek', 'createdAt': 1}).keys,
        ['uuid', 'name', 'created_at'],
      );
      expect(
        encodeRow({
          'uuid': 'u',
          'listUuid': 'l',
          'name': 'Fleece',
          'category': 'clothes',
          'quantity': 2,
        }).keys,
        ['uuid', 'list_uuid', 'name', 'category', 'quantity'],
      );
    });
  });

  group('Booleans', () {
    // SQLite has no boolean: `packed` is 0/1 locally and a real boolean in
    // Postgres. sqflite also refuses to bind a bool at all, so the inbound
    // direction has to convert or every pulled item throws.
    test('packed goes out as a boolean', () {
      expect(encodeRow({'packed': 1})['packed'], isTrue);
      expect(encodeRow({'packed': 0})['packed'], isFalse);
    });

    test('packed comes back as 0 or 1', () {
      expect(decodeRow({'packed': true})['packed'], 1);
      expect(decodeRow({'packed': false})['packed'], 0);
    });

    test('quantity is left alone despite also being an int', () {
      expect(encodeRow({'quantity': 1})['quantity'], 1);
      expect(encodeRow({'quantity': 0})['quantity'], 0);
    });

    test('a full item survives the round trip', () {
      const original = {
        'uuid': 'u',
        'tripUuid': 't',
        'name': 'Rain jacket',
        'category': 'clothes',
        'quantity': 1,
        'packed': 1,
      };
      expect(decodeRow(encodeRow(original)), original);
    });
  });

  group('Decoding a server row', () {
    test('server-only columns come through for the engine to filter', () {
      // The engine drops anything the local table doesn't have; the codec's job
      // is only to make the names comparable.
      final decoded = decodeRow({
        'uuid': 'u',
        'user_id': 'abc',
        'name': 'Northeast India',
        'start_date': 1772323200000,
        'updated_at': 1700000000000,
        'deleted_at': null,
        'start_at': '2026-02-28T00:00:00Z',
      });
      expect(decoded['uuid'], 'u');
      expect(decoded['userId'], 'abc');
      expect(decoded['startDate'], 1772323200000);
      expect(decoded['updatedAt'], 1700000000000);
      expect(decoded['deletedAt'], isNull);
      expect(decoded['startAt'], '2026-02-28T00:00:00Z');
    });
  });
}
