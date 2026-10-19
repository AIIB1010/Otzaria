import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// [ItemScrollController] שמודיע למאזינים לפני כל קפיצה לאינדקס.
class JumpAwareItemScrollController extends ItemScrollController {
  final _beforeJumpListeners = ObserverList<VoidCallback>();

  void addBeforeJumpListener(VoidCallback listener) =>
      _beforeJumpListeners.add(listener);

  void removeBeforeJumpListener(VoidCallback listener) =>
      _beforeJumpListeners.remove(listener);

  /// מודיע למאזינים על ניווט שאינו עובר ברשימה (למשל קורא חיצוני).
  void notifyBeforeJump() {
    for (final listener in _beforeJumpListeners.toList()) {
      listener();
    }
  }

  @override
  void jumpTo({required int index, double alignment = 0, double offset = 0}) {
    notifyBeforeJump();
    super.jumpTo(index: index, alignment: alignment, offset: offset);
  }

  @override
  Future<void> scrollTo({
    required int index,
    double alignment = 0,
    double offset = 0,
    required Duration duration,
    Curve curve = Curves.linear,
    List<double> opacityAnimationWeights = const [40, 20, 40],
  }) {
    notifyBeforeJump();
    return super.scrollTo(
      index: index,
      alignment: alignment,
      offset: offset,
      duration: duration,
      curve: curve,
    );
  }
}
