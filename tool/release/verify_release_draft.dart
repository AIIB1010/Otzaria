// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// שם הרשומה ש-`upload_release_assets.sh` כותב בתיקיית הרשומה של כל job.
const String kUploadRecordName = 'uploaded-assets.json';

/// נכס שה-job העלה לטיוטה, כפי שהוא מדווח ברשומה.
class ReportedAsset {
  const ReportedAsset({
    required this.name,
    required this.size,
    required this.sha256,
  });

  final String name;
  final int size;
  final String sha256;

  Map<String, Object> toJson() => {
    'name': name,
    'size': size,
    'sha256': sha256,
  };
}

/// נכס כפי שהוא בטיוטה ב-GitHub. [digest] חסר בנכס ישן או בהעלאה שלא הושלמה.
class DraftAsset {
  const DraftAsset({
    required this.id,
    required this.name,
    required this.size,
    required this.state,
    this.digest,
  });

  factory DraftAsset.fromJson(Map<String, Object?> json) => DraftAsset(
    id: json['id']! as int,
    name: json['name']! as String,
    size: json['size']! as int,
    state: json['state'] as String? ?? 'uploaded',
    digest: json['digest'] as String?,
  );

  final int id;
  final String name;
  final int size;
  final String state;
  final String? digest;
}

/// תוצאת ההשוואה: [problems] מונעות פרסום; [extra] הם נכסים שאף job לא דיווח.
class DraftCheck {
  const DraftCheck({required this.problems, required this.extra});

  final List<String> problems;
  final List<DraftAsset> extra;
}

class DraftVerificationException implements Exception {
  DraftVerificationException(this.message);
  final String message;
  @override
  String toString() => 'DraftVerificationException: $message';
}

/// קורא את הרשומות לפי שם התיקייה (שם הארטיפקט): `<records>/<name>/uploaded-assets.json`.
Map<String, List<ReportedAsset>> readUploadRecords(Directory records) {
  final result = <String, List<ReportedAsset>>{};
  if (!records.existsSync()) return result;
  for (final dir in records.listSync().whereType<Directory>()) {
    final file = File('${dir.path}/$kUploadRecordName');
    if (!file.existsSync()) continue;
    final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List) {
      throw DraftVerificationException(
        '$name: $kUploadRecordName is not a list',
      );
    }
    result[name] = [
      for (final entry in decoded)
        if (entry case {
          'name': final String assetName,
          'size': final int size,
          'sha256': final String sha,
        })
          ReportedAsset(name: assetName, size: size, sha256: sha)
        else
          throw DraftVerificationException(
            '$name: malformed entry in $kUploadRecordName: $entry',
          ),
    ];
  }
  return result;
}

/// מאחד נכסים לפי שם. אותו שם עם תוכן אחר (שני jobs) הוא שגיאה; אותו קובץ
/// משני jobs — סקריפטי ההרכבה — נספר פעם אחת.
List<ReportedAsset> mergeReportedAssets(Iterable<ReportedAsset> assets) {
  final byName = <String, ReportedAsset>{};
  for (final asset in assets) {
    final known = byName[asset.name];
    if (known != null &&
        (known.size != asset.size || known.sha256 != asset.sha256)) {
      throw DraftVerificationException(
        'two jobs reported different files named ${asset.name}',
      );
    }
    byName[asset.name] = asset;
  }
  return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// משווה את הנכסים שדווחו לטיוטה. לא מבצע שום פעולה.
DraftCheck checkDraft({
  required List<ReportedAsset> reported,
  required List<DraftAsset> draft,
}) {
  final onDraft = {for (final asset in draft) asset.name: asset};
  final problems = <String>[];
  for (final want in reported) {
    final have = onDraft[want.name];
    if (have == null) {
      problems.add('${want.name} is missing from the draft');
    } else if (have.state != 'uploaded') {
      problems.add('${want.name} is incomplete on the draft (${have.state})');
    } else if (have.size != want.size) {
      problems.add(
        '${want.name} is ${have.size} bytes on the draft but the build '
        'reported ${want.size}',
      );
    } else if (have.digest != null && have.digest != 'sha256:${want.sha256}') {
      problems.add(
        '${want.name} on the draft has ${have.digest} but the build reported '
        'sha256:${want.sha256}',
      );
    }
  }
  final names = {for (final asset in reported) asset.name};
  return DraftCheck(
    problems: problems,
    extra: [
      for (final asset in draft)
        if (!names.contains(asset.name)) asset,
    ],
  );
}

class _GitHub {
  _GitHub({required this.api, required this.repo, required this.token});

  final String api;
  final String repo;
  final String token;
  final _client = HttpClient();

  Future<(int, String)> _send(String method, Uri uri) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final request = await _client.openUrl(method, uri);
        request.headers
          ..set('Authorization', 'Bearer $token')
          ..set('Accept', 'application/vnd.github+json');
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode < 500 || attempt == 3) {
          return (response.statusCode, body);
        }
      } on IOException {
        if (attempt == 3) rethrow;
      }
      await Future<void>.delayed(Duration(seconds: 5 * attempt));
    }
  }

  Future<List<DraftAsset>> assets(String releaseId) async {
    final assets = <DraftAsset>[];
    for (var page = 1; ; page++) {
      final (status, body) = await _send(
        'GET',
        Uri.parse(
          '$api/repos/$repo/releases/$releaseId/assets'
          '?per_page=100&page=$page',
        ),
      );
      if (status != 200) {
        throw DraftVerificationException(
          'listing the assets of release $releaseId failed: $status $body',
        );
      }
      final batch = (jsonDecode(body) as List).cast<Map<String, Object?>>();
      assets.addAll(batch.map(DraftAsset.fromJson));
      if (batch.length < 100) return assets;
    }
  }

  Future<void> delete(DraftAsset asset) async {
    final (status, body) = await _send(
      'DELETE',
      Uri.parse('$api/repos/$repo/releases/assets/${asset.id}'),
    );
    if (status != 204 && status != 404) {
      throw DraftVerificationException(
        'deleting ${asset.name} failed: $status $body',
      );
    }
  }

  void close() => _client.close();
}

/// מאמת את הטיוטה מול רשומות ההעלאה של ה-jobs, לפני הפרסום.
///
/// רשומה חסרה של job חובה, נכס חסר, חלקי או בגודל/hash אחר — עוצרים. נכס שאף
/// רשומה לא מדווחת הוא שארית של ניסיון קודם ונמחק. לבסוף נכתבים נכסי ה-jobs
/// שבנו (ללא חבילות העדכון) ל-[assetsOut], ומניפסטי ה-JSON שלהם ל-[filesDir].
Future<void> verifyReleaseDraft({
  required String releaseId,
  required Directory records,
  required Directory filesDir,
  required File assetsOut,
  required List<String> requiredRecords,
  required String api,
  required String repo,
  required String token,
}) async {
  final all = readUploadRecords(records);
  final missing = requiredRecords.where((r) => !all.containsKey(r)).toList();
  if (missing.isNotEmpty) {
    throw DraftVerificationException(
      'no upload record from ${missing.join(', ')} - re-run the job that '
      'uploads it',
    );
  }
  final reported = mergeReportedAssets(all.values.expand((a) => a));
  final build = mergeReportedAssets(
    requiredRecords.expand((record) => all[record]!),
  );

  final github = _GitHub(api: api, repo: repo, token: token);
  try {
    final check = checkDraft(
      reported: reported,
      draft: await github.assets(releaseId),
    );
    if (check.problems.isNotEmpty) {
      for (final problem in check.problems) {
        print('::error::$problem');
      }
      throw DraftVerificationException(
        'the draft release does not hold what the build jobs uploaded - '
        're-run the failed jobs; they upload again with clobber',
      );
    }
    for (final asset in check.extra) {
      print(
        '::warning::${asset.name} is on the draft but no job of this run '
        'reported it - deleting it',
      );
      await github.delete(asset);
    }
  } finally {
    github.close();
  }

  filesDir.createSync(recursive: true);
  for (final record in requiredRecords) {
    final dir = Directory('${records.path}/$record');
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.endsWith('.json') && name != kUploadRecordName) {
        file.copySync('${filesDir.path}/$name');
      }
    }
  }
  assetsOut.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(build)}\n',
  );
  print('The draft holds all ${reported.length} reported assets');
}

Future<void> main(List<String> args) async {
  const usage =
      'usage: dart run tool/release/verify_release_draft.dart <release-id> '
      '<records-dir> <files-dir> <assets-json> <required-record>...';
  if (args.length < 5) {
    stderr.writeln(usage);
    exitCode = 64;
    return;
  }
  final env = Platform.environment;
  final token = env['GH_TOKEN'];
  final repo = env['GITHUB_REPOSITORY'];
  if (token == null || token.isEmpty || repo == null || repo.isEmpty) {
    stderr.writeln('::error::GH_TOKEN and GITHUB_REPOSITORY must be set');
    exitCode = 64;
    return;
  }
  try {
    await verifyReleaseDraft(
      releaseId: args[0],
      records: Directory(args[1]),
      filesDir: Directory(args[2]),
      assetsOut: File(args[3]),
      requiredRecords: args.sublist(4),
      api: env['GITHUB_API_URL'] ?? 'https://api.github.com',
      repo: repo,
      token: token,
    );
  } on DraftVerificationException catch (error) {
    print('::error::${error.message}');
    exitCode = 1;
  }
}
