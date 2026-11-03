import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// מידות יחסיות לגודל המסך, כדי שהממשק ימלא את המסך בכל גודל מכשיר.
class LvMetrics {
  const LvMetrics._(this.size);

  factory LvMetrics.of(BuildContext context) =>
      LvMetrics._(MediaQuery.sizeOf(context));

  final Size size;

  /// יחידת בסיס: כ-1/12 מהצלע הקצרה.
  double get unit => math.max(24, size.shortestSide / 12);

  double get title => unit * 0.85;
  double get body => unit * 0.7;
  double get label => unit * 0.6;
  double get iconSize => unit * 0.95;

  /// גובה מינימלי לכפתור ולשורה לחיצה.
  double get tapHeight => unit * 1.6;
  double get gap => unit * 0.25;
  double get radius => unit * 0.3;
  double get border => math.max(3, unit * 0.06);

  bool get isWide => size.width > size.height * 1.15;
}
