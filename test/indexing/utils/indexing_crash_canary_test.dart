import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'package:path/path.dart' as p;

void main() {
  final logged = <String>[];
  setUp(() {
    logged.clear();
    IndexingCrashCanary.writeLog = logged.add;
  });
  tearDown(() => IndexingCrashCanary.writeLog = ErrorLogFile.appendText);

  test(
    'commit מנקה רק דילוג שנחתם, ומשמר ספר שעדיין מחולץ וספר שלא נבדק',
    () async {
      final temp = await Directory.systemTemp.createTemp('canary_commit_');
      addTearDown(() => temp.delete(recursive: true));
      final index = p.join(temp.path, 'index');
      final file = File('$index.in_flight.json')
        ..writeAsStringSync(jsonEncode({'skipped': 2, 'unvisited': 2}));
      IndexingCrashCanary.start(index);
      final canary = IndexingCrashCanary.current!;
      addTearDown(canary.finish);
      expect(canary.begin('skipped'), isFalse);
      expect(canary.begin('prefetched'), isTrue);
      canary.committed({'skipped'});
      await canary.flush();
      expect(jsonDecode(file.readAsStringSync()), {
        'unvisited': 2,
        'prefetched': 1,
      });
      await canary.finish();
      expect(jsonDecode(file.readAsStringSync()), {'unvisited': 2});
    },
  );

  test('ריצה בריאה אינה מחשבת את קבוצת הספרים לצורך ניקוי קריסות', () async {
    final temp = await Directory.systemTemp.createTemp('canary_lazy_');
    addTearDown(() => temp.delete(recursive: true));
    IndexingCrashCanary.start(
      p.join(temp.path, 'index'),
      pendingKeys: () {
        fail('ריצה ללא קריסה קודמת אינה צריכה לסרוק ספרים שוב');
      },
    );
    await IndexingCrashCanary.current!.finish();
  });

  test('דילוג על ספר קורס נשמר גם כשספר נוסף מפיל את אותה אצווה', () async {
    final temp = await Directory.systemTemp.createTemp('canary_batch_');
    addTearDown(() => temp.delete(recursive: true));
    final index = p.join(temp.path, 'index');
    final file = File('$index.in_flight.json')
      ..writeAsStringSync(jsonEncode({'a': 2, 'b': 1}));
    IndexingCrashCanary.start(index);
    final canary = IndexingCrashCanary.current!;
    addTearDown(canary.finish);
    expect(canary.begin('a'), isFalse);
    canary.end('a');
    expect(canary.begin('b'), isTrue);
    await canary.flush();
    expect(jsonDecode(file.readAsStringSync()), {'a': 2, 'b': 2});
  });

  test(
    'ספר שקרס פעם אחת ונפתח שוב באותה ריצה אינו נחסם (issue #3336)',
    () async {
      final temp = await Directory.systemTemp.createTemp('canary_reenter_');
      addTearDown(() => temp.delete(recursive: true));
      final index = p.join(temp.path, 'index');
      final file = File('$index.in_flight.json')
        ..writeAsStringSync(jsonEncode({'a': 1}));
      IndexingCrashCanary.start(index);
      final canary = IndexingCrashCanary.current!;
      addTearDown(canary.finish);
      // אצווה שנכשלה, ואחריה המסלול ספר-ספר על אותו ספר.
      expect(canary.begin('a'), isTrue);
      expect(canary.begin('a'), isTrue);
      await canary.flush();
      expect(jsonDecode(file.readAsStringSync()), {'a': 2});
      canary.end('a');
      await canary.flush();
      expect(jsonDecode(file.readAsStringSync()), isEmpty);
    },
  );

  test(
    'שינויים נכתבים אסינכרונית, ושינויים רצופים בכתיבה אחת (#3330)',
    () async {
      final temp = await Directory.systemTemp.createTemp('canary_save_');
      addTearDown(() => temp.delete(recursive: true));
      final index = p.join(temp.path, 'index');
      final file = File('$index.in_flight.json');
      IndexingCrashCanary.start(index);
      final canary = IndexingCrashCanary.current!;
      addTearDown(canary.finish);

      expect(canary.begin('a'), isTrue);
      expect(canary.begin('b'), isTrue);
      expect(file.existsSync(), isFalse);
      await canary.flush();
      expect(jsonDecode(file.readAsStringSync()), {'a': 1, 'b': 1});

      canary.end('a');
      expect(jsonDecode(file.readAsStringSync()), {'a': 1, 'b': 1});
      await canary.flush();
      expect(jsonDecode(file.readAsStringSync()), {'b': 1});
    },
  );

  test('ספר שבטיסה בסגירה מסודרת אינו נספר כקריסה (issue #2038)', () async {
    final tempDir = await Directory.systemTemp.createTemp('canary_');
    addTearDown(() => tempDir.delete(recursive: true));
    final index = p.join(tempDir.path, 'index');
    File('$index.in_flight.json').writeAsStringSync(jsonEncode({'a': 1}));

    IndexingCrashCanary.start(index);
    final canary = IndexingCrashCanary.current!;
    expect(canary.recovering, isTrue);
    expect(canary.begin('a'), isTrue);
    await canary.finish();
    expect(IndexingCrashCanary.current, isNull);

    IndexingCrashCanary.start(index);
    expect(IndexingCrashCanary.current!.recovering, isFalse);
    await IndexingCrashCanary.current!.finish();
  });

  test(
    'ריצה שאחרי קריסה רושמת ללוג את הספרים שהיו באמצע (issue #2038)',
    () async {
      final temp = await Directory.systemTemp.createTemp('canary_log_');
      addTearDown(() => temp.delete(recursive: true));
      final index = p.join(temp.path, 'index');
      const crashed = r'C:\books\קורס.pdf';
      File(
        '$index.in_flight.json',
      ).writeAsStringSync(jsonEncode({crashed: 1, 'deleted': 1}));

      IndexingCrashCanary.start(index, pendingKeys: () => [crashed]);
      final canary = IndexingCrashCanary.current!;
      expect(canary.begin(crashed), isTrue);
      canary.end(crashed);
      await canary.finish();

      expect(logged, hasLength(1));
      expect(logged.single, contains('Indexing crash detected'));
      expect(logged.single, contains('Book 1: $crashed (attempts: 1)'));
      expect(logged.single, isNot(contains('deleted')));

      IndexingCrashCanary.start(index);
      await IndexingCrashCanary.current!.finish();
      expect(logged, hasLength(1), reason: 'ריצה בריאה אינה רושמת קריסה');
    },
  );
}
