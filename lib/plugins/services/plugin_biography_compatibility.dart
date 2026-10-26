import 'dart:convert';

import 'package:crypto/crypto.dart';

// TODO: להסיר את תאימות הביוגרפיות לאחר העברת התוספים ל-formatVersion: 2.
abstract final class PluginBiographyCompatibility {
  /// מזהה יציב ובטוח למספרי JavaScript; שלילי כדי לא להתנגש במאגר הישן.
  static int legacyId(String id) =>
      -1 -
      int.parse(
        sha256.convert(utf8.encode(id)).toString().substring(0, 13),
        radix: 16,
      );
}
