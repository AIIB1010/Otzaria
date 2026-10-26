import 'package:otzaria/tools/biographies/models/biography.dart';

/// How a source of the biographies must be credited.
class BiographyCredit {
  final String name;
  final String? author;
  final String? publisher;
  final String? license;
  final String? licenseUrl;
  final String? attribution;

  const BiographyCredit({
    required this.name,
    this.author,
    this.publisher,
    this.license,
    this.licenseUrl,
    this.attribution,
  });

  static BiographyCredit? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    String? text(String key) => switch (json[key]) {
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => null,
    };
    final name = text('name');
    if (name == null) return null;
    return BiographyCredit(
      name: name,
      author: text('author'),
      publisher: text('publisher'),
      license: text('license'),
      licenseUrl: text('license_url'),
      attribution: text('attribution'),
    );
  }
}

class BiographyEra {
  final String key;
  final String label;

  const BiographyEra(this.key, this.label);
}

/// The decoded `biographies-app` bundle of "Toldot Gedolei Yisrael".
class BiographiesBundle {
  /// Credit line the license of the biographies requires to be shown.
  static const String authorCredit = 'הביוגרפיות נערכו ע"י abaye';

  static const String projectName = 'תולדות גדולי ישראל';

  /// The full credit line shown under the list and in the credits dialog.
  static const String fullCredit =
      '$authorCredit עבור אוצריא כחלק מפרויקט "$projectName"';

  /// Eras in chronological order, as the bundle lists them.
  final List<BiographyEra> eras;

  final Map<String, BiographyCredit> credits;

  /// Entries in the bundle's order: by era, then by year.
  final List<Biography> entries;

  final String? built;
  final String? release;

  const BiographiesBundle({
    required this.entries,
    this.eras = const [],
    this.credits = const {},
    this.built,
    this.release,
  });

  /// Eras that have at least one entry.
  List<BiographyEra> get presentEras {
    final present = {for (final bio in entries) bio.era};
    return eras.where((era) => present.contains(era.key)).toList();
  }
}
