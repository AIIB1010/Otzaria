import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// ווידג'ט המוצג כאשר אין תוצאות בספרייה.
/// מציג הודעה ראשית ופעולות עזר לניווט וחיפוש.
///
/// כאשר [onOpenLink] מסופק, מוצג מצב קישור ישיר עם לחצן פתיחת קישור.
class LibraryEmptyStateWidget extends StatelessWidget {
  const LibraryEmptyStateWidget({
    super.key,
    required this.message,
    required this.onBack,
    required this.onHome,
    required this.onOpenSearch,
    this.onOpenLink,
    this.onSearchWholeLibrary,
    this.showSearchElsewhereHint = false,
  });

  final String message;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onOpenSearch;

  /// כאשר מוגדר, מוצג מצב "קישור ישיר" עם לחצן פתיחת קישור.
  final VoidCallback? onOpenLink;

  /// מריץ את אותו טקסט חיפוש מחדש בשורש הספרייה.
  /// מוצג כלחצן רק יחד עם [showSearchElsewhereHint].
  final VoidCallback? onSearchWholeLibrary;

  /// האם להציג את הרמז "ניתן לנסות לחפש בתיקייה אחרת".
  /// מוצג רק כאשר בוצע חיפוש ללא תוצאות בתוך תת-תיקייה.
  final bool showSearchElsewhereHint;

  bool get _isDeepLink => onOpenLink != null;

  Widget _buildNavButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ActionButton.neutral(
          onPressed: onBack,
          icon: FluentIcons.arrow_up_24_regular,
          text: 'חזור',
        ),
        const SizedBox(width: AppTokens.spaceSM),
        ActionButton.neutral(
          onPressed: onHome,
          icon: FluentIcons.home_24_regular,
          text: 'בית',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return OtzariaEmptyState(
      icon: _isDeepLink
          ? OtzariaIcons.link_24_regular
          : OtzariaIcons.search_not_found_24_regular,
      title: message,
      message: _isDeepLink
          ? 'נראה שהכנסתם קישור ישיר'
          : showSearchElsewhereHint
          ? 'ניתן לנסות לחפש בתיקייה אחרת'
          : null,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isDeepLink) ...[
            ActionButton.recommended(
              onPressed: onOpenLink,
              icon: OtzariaIcons.link_24_regular,
              text: 'פתיחת קישור',
            ),
            const SizedBox(height: AppTokens.spaceSM),
            _buildNavButtons(),
          ] else ...[
            _buildNavButtons(),
            if (showSearchElsewhereHint && onSearchWholeLibrary != null) ...[
              const SizedBox(height: AppTokens.spaceSM),
              ActionButton.recommended(
                onPressed: onSearchWholeLibrary,
                icon: FluentIcons.library_24_regular,
                text: 'חפש בתיקייה הראשית',
              ),
            ],
            const SizedBox(height: AppTokens.spaceMD),
            Text(
              'ניתן לחפש גם טקסט ספציפי במאגר',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            ActionButton.recommended(
              onPressed: onOpenSearch,
              icon: FluentIcons.search_24_regular,
              text: 'פתח חיפוש טקסט',
            ),
          ],
        ],
      ),
    );
  }
}
