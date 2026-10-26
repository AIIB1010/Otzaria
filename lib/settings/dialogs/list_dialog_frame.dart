import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';

/// מסגרת משותפת לדיאלוגי רשימות הספרים: רוחב וגובה מוגבלים, כותרת בצורת
/// [AppDialogHeader] עם מונה, ואחריה [children].
class ListDialogFrame extends StatelessWidget {
  final IconData icon;
  final String title;
  final String counter;
  final double maxWidth;
  final double heightFactor;
  final List<Widget> children;

  const ListDialogFrame({
    super.key,
    required this.icon,
    required this.title,
    required this.counter,
    this.maxWidth = 720,
    this.heightFactor = 0.85,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final width = media.size.width * 0.9;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width > maxWidth ? maxWidth : width,
          maxHeight: media.size.height * heightFactor,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              icon: icon,
              title: title,
              compact: true,
              trailing: Text(
                counter,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLG,
                  0,
                  AppTokens.spaceLG,
                  AppTokens.spaceMD,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
