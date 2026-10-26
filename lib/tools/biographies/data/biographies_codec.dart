import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';

/// Decodes `biographies-app.json.gz`, the application bundle of
/// "Toldot Gedolei Yisrael" (gzip of UTF-8 JSON, format `biographies-app`).
class BiographiesCodec {
  BiographiesCodec._();

  static const String format = 'biographies-app';

  /// The bundle version this code reads. A bundle with another version is
  /// rejected, so the repository falls back to the bundled copy.
  static const int supportedVersion = 1;

  /// Throws [FormatException] when the bytes are not a supported bundle.
  static BiographiesBundle decode(Uint8List bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(gzip.decode(bytes)));
    } catch (e) {
      throw FormatException('Biographies bundle could not be read: $e');
    }
    if (json is! Map<String, dynamic> || json['format'] != format) {
      throw const FormatException('Not a biographies-app bundle');
    }
    if (json['version'] != supportedVersion) {
      throw FormatException(
        'Unsupported biographies bundle version: ${json['version']}',
      );
    }

    final eras = <BiographyEra>[
      for (final era in (json['eras'] as List?) ?? const [])
        if (era case {'key': final String key, 'label': final String label})
          BiographyEra(key, label),
    ];
    final eraLabels = {for (final era in eras) era.key: era.label};

    final credits = <String, BiographyCredit>{};
    final rawCredits = json['credits'];
    if (rawCredits is Map<String, dynamic>) {
      for (final MapEntry(:key, :value) in rawCredits.entries) {
        final credit = BiographyCredit.fromJson(value);
        if (credit != null) credits[key] = credit;
      }
    }

    final entries = <Biography>[];
    for (final entry in (json['entries'] as List?) ?? const []) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        entries.add(Biography.fromJson(entry, eraLabels: eraLabels));
      } on FormatException {
        // One malformed entry should not hide all the others.
      }
    }

    return BiographiesBundle(
      entries: entries,
      eras: eras,
      credits: credits,
      built: json['built'] as String?,
      release: json['release'] as String?,
    );
  }
}
