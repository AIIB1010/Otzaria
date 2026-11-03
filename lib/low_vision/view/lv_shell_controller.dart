import 'package:flutter/foundation.dart';

/// מעבר בין הממשק הפשוט לממשק המלא (עבור אדם רואה שעוזר בהגדרות).
class LvShellController {
  final ValueNotifier<bool> _advanced = ValueNotifier<bool>(false);

  /// האם הממשק המלא מוצג כרגע.
  ValueListenable<bool> get advancedListenable => _advanced;
  bool get advanced => _advanced.value;

  void openAdvanced() => _advanced.value = true;
  void closeAdvanced() => _advanced.value = false;

  void dispose() => _advanced.dispose();
}
