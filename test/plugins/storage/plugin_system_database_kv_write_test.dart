import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  late Directory tempDir;
  final db = PluginSystemDatabase.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_kv_write_');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    db.resetForTests();
  });

  tearDown(() async {
    db.resetForTests();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  test('כתיבת KV מול מסד נעול אינה חוסמת את ה-isolate הקורא (#3378)', () async {
    await db.database;
    final locker = sqlite3.open(await AppPaths.resolvePluginsDbPath());
    locker.execute('BEGIN IMMEDIATE');

    final write = db.setPluginKV('p', 'ns', 'k', '"v"');
    final tick = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    tick.stop();

    locker.execute('COMMIT');
    locker.close();
    await write;

    expect(tick.elapsedMilliseconds, lessThan(1000));
    expect(await db.getPluginKV('p', 'ns', 'k'), '"v"');
  });

  test('קריאה, מחיקה וכתיבה רצופות שומרות על הסדר', () async {
    final pending = [
      db.setPluginKV('p', 'ns', 'a', '1'),
      db.setPluginKV('p', 'ns', 'a', '2'),
      db.setPluginKV('p', 'ns', 'b', '3'),
      db.removePluginKV('p', 'ns', 'b'),
    ];
    expect(await db.getPluginKV('p', 'ns', 'a'), '2');
    expect(await db.listPluginKVKeys('p', 'ns'), ['a']);
    await Future.wait(pending);
  });

  test('close מחכה גם לכתיבה שנכנסה בזמן אצווה רצה', () async {
    await db.database;
    final first = db.setPluginKV('p', 'ns', 'a', '1');
    await Future<void>.delayed(Duration.zero);
    unawaited(db.setPluginKV('p', 'ns', 'b', '2'));
    unawaited(db.writeLog('p', 'error', 'boom'));
    await first;
    await db.close();

    final file = sqlite3.open(await AppPaths.resolvePluginsDbPath());
    addTearDown(file.close);
    expect(
      file
          .select('SELECT key FROM plugin_kv_store ORDER BY key')
          .map(
            (r) => r['key'],
          ),
      ['a', 'b'],
    );
    expect(file.select('SELECT message FROM plugin_runtime_log'), hasLength(1));
  });

  test('קריאה אינה ממתינה לכתיבות שנכנסו אחריה', () async {
    await db.setPluginKV('p', 'ns', 'a', '1');
    final writes = <Future<void>>[];
    final writer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      for (var i = 0; i < 200; i++) {
        writes.add(db.setPluginKV('p', 'ns', 'k${writes.length}', 'x'));
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final value = await db
        .getPluginKV('p', 'ns', 'a')
        .timeout(const Duration(seconds: 5), onTimeout: () => 'starved');
    writer.cancel();
    await Future.wait(writes);

    expect(value, '1');
  });
}
