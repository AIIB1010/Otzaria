import 'dart:io';

import 'package:flutter/foundation.dart';

/// נבחר בזמן הבנייה: `--dart-define=LOW_VISION=true`.
const bool _lowVisionBuild = bool.fromEnvironment('LOW_VISION');

/// מהדורת הראייה הלקויה: ממשק פשוט וענק במקום הממשק הרגיל, באנדרואיד בלבד.
bool get isLowVisionMode => _lowVisionBuild && !kIsWeb && Platform.isAndroid;
