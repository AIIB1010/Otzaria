// ignore_for_file: avoid_print
//
// מחולל `lib/plugins/utils/fluent_icon_resolver.dart` — מפת שמות פלואנט
// שתוספים יכולים להצהיר עליהם. המפה כוללת רק את השמות שב-
// `tool/plugins/fluent_icon_subset.txt`: כל IconData במפה נשמר בגופן ה-release,
// ומפה של כל 4,500 האייקונים מנטרלת את tree-shaking של גופני פלואנט.
//
// הרצה: dart run tool/plugins/gen_fluent_icon_map.dart [--check]

import 'dart:convert';
import 'dart:io';

const String subsetPath = 'tool/plugins/fluent_icon_subset.txt';
const String outputPath = 'lib/plugins/utils/fluent_icon_resolver.dart';

final RegExp _iconLine = RegExp(
  r"static const IconData ([a-z0-9_]+_24_(?:regular|filled|light)) = "
  r"IconData\((\d+), fontFamily: '([A-Za-z-]+)', fontPackage: _kFontPkg"
  r"(, matchTextDirection: true)?\);",
);

class _FluentIcon {
  final int codePoint;
  final String fontFamily;
  final bool matchTextDirection;
  const _FluentIcon(this.codePoint, this.fontFamily, this.matchTextDirection);
}

void main(List<String> args) {
  final root = Directory.current;
  final String output;
  try {
    output = buildFluentIconMap(root);
  } on FluentIconSubsetError catch (error) {
    stderr.writeln(error);
    exit(1);
  }
  final file = File('${root.path}/$outputPath');
  final current = file.existsSync()
      ? file.readAsStringSync().replaceAll('\r\n', '\n')
      : '';
  if (current == output) {
    print('$outputPath מעודכן.');
    return;
  }
  if (args.contains('--check')) {
    stderr.writeln(
      '$outputPath אינו תואם ל-$subsetPath. הרץ: '
      'dart run tool/plugins/gen_fluent_icon_map.dart',
    );
    exit(1);
  }
  file.writeAsStringSync(output);
  print('נכתב $outputPath.');
}

class FluentIconSubsetError implements Exception {
  final String message;
  const FluentIconSubsetError(this.message);
  @override
  String toString() => message;
}

/// בונה את תוכן `fluent_icon_resolver.dart` מקובץ התת-קבוצה ומהחבילה.
String buildFluentIconMap(Directory root) {
  final packageRoot = _packageRoot(root, 'fluentui_system_icons');
  final version = _packageVersion(packageRoot);
  final icons = _parseIcons(
    File('$packageRoot/lib/src/fluent_icons.dart').readAsStringSync(),
  );
  final subset = parseSubset(
    File('${root.path}/$subsetPath').readAsStringSync(),
  );

  final problems = <String>[];
  for (final name in subset) {
    final icon = icons[name];
    if (icon == null) {
      problems.add('$name: לא קיים ב-fluentui_system_icons $version');
    } else if (icon.matchTextDirection) {
      problems.add('$name: אייקון כיווני (matchTextDirection) אינו נתמך');
    }
  }
  if (problems.isNotEmpty) {
    throw FluentIconSubsetError(
      'שמות לא תקינים ב-$subsetPath:\n${problems.join('\n')}',
    );
  }
  return _render(version, subset, icons);
}

/// שמות הקובץ בסדר הופעתם, בלי הערות (`#`), שורות ריקות וכפילויות.
List<String> parseSubset(String text) {
  final names = <String>{};
  for (final raw in LineSplitter.split(text)) {
    final line = raw.split('#').first.trim();
    if (line.isNotEmpty) names.add(line);
  }
  return names.toList();
}

Map<String, _FluentIcon> _parseIcons(String source) => {
  for (final m in _iconLine.allMatches(source))
    m.group(1)!: _FluentIcon(
      int.parse(m.group(2)!),
      m.group(3)!,
      m.group(4) != null,
    ),
};

String _render(
  String version,
  List<String> subset,
  Map<String, _FluentIcon> icons,
) {
  final sorted = [...subset]
    ..sort((a, b) {
      final byFamily = icons[a]!.fontFamily.compareTo(icons[b]!.fontFamily);
      return byFamily != 0 ? byFamily : a.compareTo(b);
    });
  final buffer = StringBuffer()
    ..writeln('// GENERATED — do not edit manually.')
    ..writeln(
      '// Source: fluentui_system_icons $version, names from $subsetPath.',
    )
    ..writeln(
      '// Regenerate with: dart run tool/plugins/gen_fluent_icon_map.dart',
    )
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln()
    ..writeln("const _kFontPkg = 'fluentui_system_icons';")
    ..writeln()
    ..writeln(
      "/// ממיר שם אייקון FluentUI (למשל 'bookmark_24_regular') ל-IconData.",
    )
    ..writeln('///')
    ..writeln(
      '/// תומך רק בתת-הקבוצה שב-$subsetPath; שם אחר מחזיר null.',
    )
    ..writeln('IconData? fluentIconFromName(String? name) {')
    ..writeln('  if (name == null) return null;')
    ..writeln('  return _iconMap[name];')
    ..writeln('}')
    ..writeln()
    ..writeln('const _iconMap = <String, IconData>{');
  for (final name in sorted) {
    final icon = icons[name]!;
    buffer
      ..writeln("  '$name': IconData(")
      ..writeln('    ${icon.codePoint},')
      ..writeln("    fontFamily: '${icon.fontFamily}',")
      ..writeln('    fontPackage: _kFontPkg,')
      ..writeln('  ),');
  }
  buffer.writeln('};');
  return buffer.toString();
}

String _packageRoot(Directory root, String package) {
  final config =
      jsonDecode(
            File(
              '${root.path}/.dart_tool/package_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in config['packages'] as List<dynamic>) {
    final map = entry as Map<String, dynamic>;
    if (map['name'] == package) {
      final base = Uri.directory('${root.absolute.path}/.dart_tool/');
      return Directory.fromUri(
        base.resolve(map['rootUri'] as String),
      ).path.replaceAll(RegExp(r'[\\/]$'), '');
    }
  }
  throw StateError(
    '$package לא נמצא ב-package_config.json — הרץ flutter pub get',
  );
}

String _packageVersion(String root) {
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File('$root/pubspec.yaml').readAsStringSync());
  return match?.group(1) ?? 'unknown';
}
