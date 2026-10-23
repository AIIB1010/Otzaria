import 'dart:io';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';

/// ה-embedder של Linux אינו שולח `ViewFocusEvent`, ולכן אחרי מעבר חלון המקשים
/// היו ממשיכים לפוקוס שבחלון הקודם. כאן מסנתזים אותו מהפעלת החלון.
abstract final class ViewFocusSync {
  static int? _focusedViewId;

  @visibleForTesting
  static bool? debugEnabledOverride;

  /// ב-Windows וב-macOS המנוע שולח את האירוע בעצמו.
  static bool get _enabled =>
      debugEnabledOverride ??
      (!kIsWeb && Platform.isLinux && MultiViewMode.enabled);

  /// החלון שמציג את [viewId] הופעל.
  static void windowActivated(int viewId) {
    if (!_enabled || _focusedViewId == viewId) return;
    _focusedViewId = viewId;
    WidgetsBinding.instance.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: viewId,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.undefined,
      ),
    );
  }

  /// החלון הראשי (התצוגה המרומזת) הופעל.
  static void mainWindowActivated() {
    if (!_enabled) return;
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) windowActivated(view.viewId);
  }

  @visibleForTesting
  static void resetForTest() {
    _focusedViewId = null;
    debugEnabledOverride = null;
  }
}
