import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/lv_books_screen.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_search_screen.dart';
import 'package:otzaria/low_vision/view/lv_settings_screen.dart';
import 'package:otzaria/low_vision/view/widgets/lv_pressable.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';

/// מסך הבית: שני כפתורים ענקיים בלבד, ואייקון קטן להגדרות.
class LvHomeScreen extends StatefulWidget {
  const LvHomeScreen({super.key, this.libraryHasBooks});

  /// לבדיקות: מחליף את בדיקת קיום הספרייה.
  final Future<bool> Function()? libraryHasBooks;

  @override
  State<LvHomeScreen> createState() => _LvHomeScreenState();
}

enum _LibraryStatus { loading, ready, missing }

class _LvHomeScreenState extends State<LvHomeScreen> {
  _LibraryStatus _status = _LibraryStatus.loading;

  @override
  void initState() {
    super.initState();
    _checkLibrary();
  }

  Future<void> _checkLibrary() async {
    setState(() => _status = _LibraryStatus.loading);
    var status = _LibraryStatus.missing;
    try {
      final hasBooks =
          await (widget.libraryHasBooks?.call() ?? _libraryHasBooks());
      if (hasBooks) status = _LibraryStatus.ready;
    } catch (_) {
      status = _LibraryStatus.missing;
    }
    if (mounted) setState(() => _status = status);
  }

  Future<bool> _libraryHasBooks() async {
    final library = await DataRepository.instance.library;
    return library.getAllBooks().isNotEmpty;
  }

  void _openBooks() => lvPush<void>(context, const LvBooksScreen());
  void _openSearch() => lvPush<void>(context, const LvSearchScreen());
  void _openSettings() => lvPush<void>(context, const LvSettingsScreen());

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final ready = _status == _LibraryStatus.ready;
    return LvKeyScope(
      actions: {
        LvAction.openBooks: _openBooks,
        LvAction.openSearch: ready ? _openSearch : () {},
        LvAction.previousSection: _openBooks,
        LvAction.nextSection: _openSearch,
      },
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Material(
          color: p.background,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(m.gap * 1.5),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(top: m.unit * 1.1),
                      child: _buildBody(m),
                    ),
                  ),
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    child: _SettingsCorner(onTap: _openSettings),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(LvMetrics m) {
    if (_status == _LibraryStatus.missing) {
      return LvMessage(
        'לא נמצאה ספרייה במכשיר.\nבקשו עזרה ממי שרואה, והקישו על כפתור ההגדרות.',
        action: SizedBox(
          width: m.unit * 9,
          child: LvButton(
            label: 'נסו שוב',
            icon: FluentIcons.arrow_clockwise_24_filled,
            onPressed: _checkLibrary,
          ),
        ),
      );
    }
    final count = context.select((LowVisionCubit c) => c.openBooks.length);
    final scale = context.select((LowVisionCubit c) => c.state.homeScale);
    final loading = _status == _LibraryStatus.loading;
    final books = _BigChoice(
      icon: FluentIcons.book_24_filled,
      title: 'הספרים שלי',
      subtitle: count == 0 ? 'עדיין אין ספרים' : '$count ספרים פתוחים',
      onTap: _openBooks,
      scale: scale,
    );
    final search = _BigChoice(
      icon: FluentIcons.search_24_filled,
      title: 'חיפוש ספרים',
      subtitle: loading ? 'הספרייה נטענת…' : 'הקלידו שם ספר',
      onTap: loading ? null : _openSearch,
      scale: scale,
    );
    return m.isWide
        ? Row(
            children: [
              Expanded(child: books),
              SizedBox(width: m.gap * 2),
              Expanded(child: search),
            ],
          )
        : Column(
            children: [
              Expanded(child: books),
              SizedBox(height: m.gap * 2),
              Expanded(child: search),
            ],
          );
  }
}

class _BigChoice extends StatelessWidget {
  const _BigChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.scale,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// מכפיל גודל האייקון והכיתוב (הגדרה "גודל מסך הבית").
  final double scale;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    return Semantics(
      button: true,
      label: title,
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: LvPressable(
          onTap: onTap,
          builder: (context, pressed) {
            final bg = pressed ? p.background : p.accent;
            final fg = pressed ? p.foreground : p.onAccent;
            return Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(m.radius * 1.5),
                border: Border.all(color: p.foreground, width: m.border * 1.5),
              ),
              alignment: Alignment.center,
              padding: EdgeInsets.all(m.gap * 2),
              // האייקון הוא העיקר: גדול בהרבה מהכיתוב, ומתכווץ רק אם אין מקום.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: m.unit * 4.5 * scale, color: fg),
                    SizedBox(height: m.gap * scale),
                    Text(
                      // כל מילה בשורה משלה, כדי שהכיתוב יוכל להיות גדול.
                      title.split(' ').join('\n'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fg,
                        fontSize: m.unit * 1.5 * scale,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: m.gap * scale),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fg,
                        fontSize: m.label * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// אייקון קטן ושקט בפינה: הגדרות ואפשרויות לעוזר רואה.
class _SettingsCorner extends StatelessWidget {
  const _SettingsCorner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final size = m.unit * 0.9;
    return Semantics(
      button: true,
      label: 'הגדרות',
      onTap: onTap,
      excludeSemantics: true,
      child: LvPressable(
        onTap: onTap,
        builder: (context, pressed) => Container(
          // אזור המגע גדול מהאייקון, כדי שהעוזר ימצא אותו בקלות.
          width: size * 1.6,
          height: size * 1.6,
          alignment: Alignment.center,
          decoration: pressed
              ? BoxDecoration(color: p.foreground, shape: BoxShape.circle)
              : null,
          child: Icon(
            FluentIcons.settings_24_regular,
            size: size * 0.7,
            color: pressed ? p.background : p.foreground.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
