import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// מעטפת משותפת לכרטיסי תוצאה במסכי כלים.
class ToolResultCardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const ToolResultCardShell({
    super.key,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTokens.borderRadiusAll,
          focusColor: Colors.transparent,
          child: AppSelectionArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMD,
                vertical: AppTokens.spaceSM,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
