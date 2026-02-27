import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('QueryClient', () {
    late QueryClient client;

    setUp(() {
      client = QueryClient();
    });

    tearDown(() {
      client.dispose();
    });

    group('key serialization', () {
      test('serializes simple keys', () {
        expect(QueryClient.serializeKey(['todos']), '["todos"]');
      });

      test('serializes compound keys', () {
        expect(
          QueryClient.serializeKey(['todo', 123]),
          '["todo",123]',
        );
      });

      test('same keys produce same serialization', () {
        expect(
          QueryClient.serializeKey(['todo', 'abc']),
          QueryClient.serializeKey(['todo', 'abc']),
        );
      });
    });

    group('cache entry management', () {
      test('creates new entry', () {
        final entry = client.getOrCreateEntry(['todos']);
        expect(entry, isNotNull);
        expect(entry.serializedKey, '["todos"]');
        expect(client.size, 1);
      });

      test('returns existing entry for same key', () {
        final e1 = client.getOrCreateEntry(['todos']);
        final e2 = client.getOrCreateEntry(['todos']);
        expect(identical(e1, e2), isTrue);
        expect(client.size, 1);
      });

      test('creates separate entries for different keys', () {
        client.getOrCreateEntry(['todos']);
        client.getOrCreateEntry(['users']);
        expect(client.size, 2);
      });

      test('uses max gcTime when same key accessed with different gcTimes',
          () {
        client.getOrCreateEntry(
          ['todos'],
          gcTime: const Duration(minutes: 3),
        );
        final entry = client.getOrCreateEntry(
          ['todos'],
          gcTime: const Duration(minutes: 10),
        );
        expect(entry.gcTime, const Duration(minutes: 10));
      });
    });

    group('getQueryData / setQueryData', () {
      test('returns null for missing key', () {
        expect(client.getQueryData<String>(['missing']), isNull);
      });

      test('returns null when entry exists but has no data', () {
        client.getOrCreateEntry(['todos']);
        expect(client.getQueryData<List>(['todos']), isNull);
      });

      test('setQueryData stores and retrieves data', () {
        client.getOrCreateEntry(['todos']);
        client.setQueryData<List<int>>(['todos'], [1, 2, 3]);
        expect(client.getQueryData<List<int>>(['todos']), [1, 2, 3]);
      });

      test('setQueryData notifies listeners', () {
        final entry = client.getOrCreateEntry(['todos']);
        var notified = false;
        entry.addListener(() => notified = true);

        client.setQueryData(['todos'], 'data');
        expect(notified, isTrue);
      });

      test('setQueryData clears error', () {
        final entry = client.getOrCreateEntry(['todos']);
        entry.error = Exception('fail');
        client.setQueryData(['todos'], 'data');
        expect(entry.error, isNull);
      });
    });

    group('invalidateQueries', () {
      test('invalidates exact key match', () {
        final entry = client.getOrCreateEntry(['todos']);
        entry.data = [1, 2, 3];
        entry.fetchedAt = DateTime.now();

        client.invalidateQueries(['todos']);
        expect(entry.fetchedAt, isNull);
      });

      test('invalidates prefix matches', () {
        final e1 = client.getOrCreateEntry(['todos']);
        final e2 = client.getOrCreateEntry(['todos', 'active']);
        final e3 = client.getOrCreateEntry(['todos', 'completed']);
        final e4 = client.getOrCreateEntry(['users']);

        for (final e in [e1, e2, e3, e4]) {
          e.data = 'data';
          e.fetchedAt = DateTime.now();
        }

        client.invalidateQueries(['todos']);

        expect(e1.fetchedAt, isNull); // exact match
        expect(e2.fetchedAt, isNull); // prefix match
        expect(e3.fetchedAt, isNull); // prefix match
        expect(e4.fetchedAt, isNotNull); // unrelated — not invalidated
      });

      test('does not match partial key segments', () {
        final e1 = client.getOrCreateEntry(['todos']);
        final e2 = client.getOrCreateEntry(['todosExtra']);

        for (final e in [e1, e2]) {
          e.data = 'data';
          e.fetchedAt = DateTime.now();
        }

        client.invalidateQueries(['todos']);

        expect(e1.fetchedAt, isNull); // exact match
        expect(e2.fetchedAt, isNotNull); // not a prefix match
      });

      test('notifies listeners on invalidation', () {
        final entry = client.getOrCreateEntry(['todos']);
        entry.data = 'data';
        entry.fetchedAt = DateTime.now();

        var notified = false;
        entry.addListener(() => notified = true);

        client.invalidateQueries(['todos']);
        expect(notified, isTrue);
      });
    });

    group('removeQueries', () {
      test('removes matching entries', () {
        client.getOrCreateEntry(['todos']);
        client.getOrCreateEntry(['todos', 'active']);
        client.getOrCreateEntry(['users']);

        client.removeQueries(['todos']);
        expect(client.size, 1);
        expect(client.keys.single, '["users"]');
      });
    });

    group('clear', () {
      test('removes all entries', () {
        client.getOrCreateEntry(['a']);
        client.getOrCreateEntry(['b']);
        client.getOrCreateEntry(['c']);

        client.clear();
        expect(client.size, 0);
      });
    });

    group('snapshotEntries / restoreSnapshot', () {
      test('snapshots and restores data', () {
        final entry = client.getOrCreateEntry(['todos']);
        entry.data = [1, 2, 3];
        entry.fetchedAt = DateTime.now();

        final snapshot = client.snapshotEntries([
          ['todos']
        ]);
        expect(snapshot['["todos"]'], [1, 2, 3]);

        // Modify data.
        client.setQueryData(['todos'], [4, 5, 6]);
        expect(entry.data, [4, 5, 6]);

        // Restore.
        client.restoreSnapshot(snapshot);
        expect(entry.data, [1, 2, 3]);
      });

      test('snapshots multiple prefixes', () {
        client.getOrCreateEntry(['todos']).data = 'todos';
        client.getOrCreateEntry(['users']).data = 'users';
        client.getOrCreateEntry(['posts']).data = 'posts';

        final snapshot = client.snapshotEntries([
          ['todos'],
          ['users'],
        ]);
        expect(snapshot.length, 2);
        expect(snapshot['["todos"]'], 'todos');
        expect(snapshot['["users"]'], 'users');
      });
    });

    group('singleton', () {
      tearDown(() {
        QueryClient.resetInstance();
      });

      test('returns same instance', () {
        final a = QueryClient.instance;
        final b = QueryClient.instance;
        expect(identical(a, b), isTrue);
      });

      test('resetInstance creates fresh instance', () {
        final a = QueryClient.instance;
        QueryClient.resetInstance();
        final b = QueryClient.instance;
        expect(identical(a, b), isFalse);
      });
    });
  });
}
