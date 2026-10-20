import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/foreground_work.dart';

class _FakePlatform implements ForegroundWorkPlatform {
  final calls = <String>[];
  bool failStart = false;
  late void Function() onTimeout;
  late void Function(String reason) onStartFailed;

  @override
  void setHandlers({
    required void Function() onTimeout,
    required void Function(String reason) onStartFailed,
  }) {
    this.onTimeout = onTimeout;
    this.onStartFailed = onStartFailed;
  }

  @override
  Future<void> start(ForegroundWorkNotice notice) async {
    if (failStart) throw Exception('ForegroundServiceStartNotAllowedException');
    calls.add('start:${notice.title}');
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  const download = (channelName: 'c', title: 'download', text: 't');
  const indexing = (channelName: 'c', title: 'indexing', text: 't');

  late _FakePlatform platform;
  late List<String> failures;

  ForegroundWork build({bool isAndroid = true}) => ForegroundWork(
    platform: platform,
    isAndroid: isAndroid,
    logFailure: (stage, error, _) => failures.add('$stage: $error'),
  );

  setUp(() {
    platform = _FakePlatform();
    failures = [];
  });

  test('עולה עם הבעלים הראשון ונעצר כשהוא משחרר', () async {
    final work = build();
    work.acquire('download', notice: download);
    await work.settled;
    expect(platform.calls, ['start:download']);

    work.release('download');
    await work.settled;
    expect(platform.calls, ['start:download', 'stop']);
  });

  test('שני בעלים במקביל: שחרור של אחד אינו עוצר את השני', () async {
    final work = build();
    work.acquire('download', notice: download);
    work.acquire('indexing', notice: indexing);
    await work.settled;
    work.release('download');
    await work.settled;
    expect(platform.calls, ['start:download']);

    work.acquire('download', notice: download);
    work.release('indexing');
    await work.settled;
    expect(platform.calls, ['start:download']);

    work.release('download');
    await work.settled;
    expect(platform.calls, ['start:download', 'stop']);
  });

  test('שחרור כפול או של מי שלא החזיק אינו עוצר', () async {
    final work = build();
    work.acquire('download', notice: download);
    work.release('indexing');
    await work.settled;
    expect(platform.calls, ['start:download']);
  });

  test('acquire ו-release מיידיים אינם משאירים שירות פועל', () async {
    final work = build();
    work.acquire('download', notice: download);
    work.release('download');
    await work.settled;
    expect(platform.calls, isEmpty);
  });

  test('כשל בהפעלה נרשם ואינו נזרק; הבעלים הבא מנסה שוב', () async {
    final work = build();
    platform.failStart = true;
    work.acquire('download', notice: download);
    await work.settled;
    expect(failures, [contains('start')]);
    expect(platform.calls, isEmpty);

    platform.failStart = false;
    work.acquire('indexing', notice: indexing);
    await work.settled;
    expect(platform.calls, ['start:download']);
  });

  test('כשל שהשירות מדווח אחרי ההפעלה נרשם, ושחרור אינו קורס', () async {
    final work = build();
    work.acquire('download', notice: download);
    await work.settled;
    platform.onStartFailed('quota exhausted');
    expect(failures, ['start: quota exhausted']);

    work.release('download');
    await work.settled;
    expect(platform.calls, ['start:download'], reason: 'השירות כבר לא רץ');
  });

  test('מכסת זמן: כל הבעלים מקבלים הודעה, והשירות אינו נעצר שוב', () async {
    final work = build();
    final timedOut = <String>[];
    work.acquire(
      'download',
      notice: download,
      onTimeout: () => timedOut.add('download'),
    );
    work.acquire(
      'indexing',
      notice: indexing,
      onTimeout: () => timedOut.add('indexing'),
    );
    await work.settled;

    platform.onTimeout();
    expect(timedOut, ['download', 'indexing']);

    work.release('download');
    work.release('indexing');
    await work.settled;
    expect(platform.calls, ['start:download']);
  });

  test('מחוץ לאנדרואיד אינו נוגע בפלטפורמה', () async {
    final work = build(isAndroid: false);
    work.acquire('download', notice: download);
    work.release('download');
    await work.settled;
    expect(platform.calls, isEmpty);
  });
}
