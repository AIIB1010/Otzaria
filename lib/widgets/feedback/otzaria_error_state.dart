import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';

/// מצב שגיאה אחיד: סמל באדום, כותרת בעברית, ופירוט טכני אופציונלי מתחתיה.
///
/// בא במקום `Center(Text('Error: ...'))` גולמי. הפירוט ([details]) הוא טקסט
/// הכשל כפי שהגיע מהשכבה שמתחת, ולכן מוצג בקטן ומתחת לכותרת העברית.
class OtzariaErrorState extends StatelessWidget {
  final String title;
  final Object? details;
  final Widget? body;
  final List<Widget>? actions;
  final IconData icon;
  final bool isCompact;
  final bool scrollable;

  const OtzariaErrorState({
    super.key,
    required this.title,
    this.details,
    this.body,
    this.actions,
    this.icon = FluentIcons.error_circle_24_regular,
    this.isCompact = false,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = details?.toString();
    return OtzariaEmptyState(
      customIcon: Icon(icon, size: isCompact ? 36 : 56, color: cs.error),
      title: title,
      message: text == null || text.isEmpty ? null : text,
      body: body,
      actions: actions,
      isCompact: isCompact,
      scrollable: scrollable,
    );
  }
}
