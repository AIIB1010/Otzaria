// lib/widgets/dialogs/app_dialog_header.dart
// כותרת משותפת לדיאלוגים מורכבים: פס צבוע, תג אייקון עגול, שם ותיאור קצר.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// גוון תג האייקון בכותרת. [error] שמור למצבי תקלה וסיכון.
enum AppDialogHeaderTone { primary, error }

/// כותרת דיאלוג בצורה אחידה: אייקון מסומל, שם, שורת משנה אופציונלית וכפתור
/// סגירה. משמשת את דיאלוגי הדיווח, ההקרסה והרשימות, כדי שכולם ייראו כחלק
/// מאותה מערכת.
class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.tone = AppDialogHeaderTone.primary,
    this.onClose,
    this.closeEnabled = true,
    this.compact = false,
    this.subtitleMaxLines,
  });

  final IconData icon;
  final String title;

  /// שורה קטנה מתחת לשם: תיאור המקרה, שם הספר וכד'.
  final String? subtitle;

  /// ווידג'ט בין הטקסט לכפתור הסגירה, למשל מונה.
  final Widget? trailing;

  final AppDialogHeaderTone tone;

  /// ברירת מחדל: סגירת הדיאלוג. [closeEnabled] false משבית את הכפתור, למשל
  /// בזמן שליחה.
  final VoidCallback? onClose;
  final bool closeEnabled;

  /// ריפוד אנכי קטן יותר, לכותרות שאינן מחזיקות תיאור ארוך.
  final bool compact;

  /// null = בלי הגבלה. כותרות עם שם ספר ארוך מגבילות לשורה אחת.
  final int? subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isError = tone == AppDialogHeaderTone.error;
    final vertical = compact ? AppTokens.spaceSM : AppTokens.spaceMD;
    return Container(
      color: cs.surfaceContainerHighest,
      padding: EdgeInsetsDirectional.fromSTEB(
        AppTokens.spaceLG,
        vertical,
        AppTokens.spaceSM,
        vertical,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isError ? cs.errorContainer : cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: isError ? cs.onErrorContainer : cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: subtitleMaxLines,
                    overflow: subtitleMaxLines == null
                        ? null
                        : TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppTokens.spaceSM),
            trailing!,
          ],
          IconButton(
            icon: const Icon(FluentIcons.dismiss_24_regular),
            tooltip: 'סגור',
            onPressed: closeEnabled
                ? (onClose ?? () => Navigator.of(context).pop())
                : null,
          ),
        ],
      ),
    );
  }
}
