import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_search_screen.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';

/// "הספרים שלי": קבועים ראשונים, אחריהם האחרונים שנפתחו.
class LvBooksScreen extends StatefulWidget {
  const LvBooksScreen({super.key});

  @override
  State<LvBooksScreen> createState() => _LvBooksScreenState();
}

class _LvBooksScreenState extends State<LvBooksScreen> {
  final _scroll = ScrollController();
  final _rowKeys = <int, GlobalKey>{};
  int _selected = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, count - 1));
    final context = _rowKeys[_selected]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, alignment: 0.5);
    }
  }

  void _page(double direction) {
    if (!_scroll.hasClients) return;
    final step = _scroll.position.viewportDimension * 0.85 * direction;
    _scroll.animateTo(
      (_scroll.offset + step).clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LowVisionCubit>();
    return BlocBuilder<LowVisionCubit, LowVisionState>(
      builder: (context, _) {
        final books = cubit.openBooks;
        final selected = books.isEmpty
            ? 0
            : _selected.clamp(0, books.length - 1);
        return LvKeyScope(
          actions: {
            LvAction.back: () => Navigator.of(context).maybePop(),
            LvAction.down: () => _move(1, books.length),
            LvAction.up: () => _move(-1, books.length),
            LvAction.next: () => _page(1),
            LvAction.previous: () => _page(-1),
            LvAction.select: () {
              if (books.isNotEmpty) lvOpenBook(context, books[selected]);
            },
            LvAction.openSearch: () => lvPush<void>(
              context,
              const LvSearchScreen(),
            ),
          },
          child: LvScaffold(
            title: 'הספרים שלי',
            onBack: () => Navigator.of(context).maybePop(),
            body: books.isEmpty
                ? LvMessage(
                    'עדיין אין ספרים.\nחפשו ספר ופתחו אותו, והוא יופיע כאן.',
                    action: LvButton(
                      label: 'חיפוש ספרים',
                      icon: FluentIcons.search_24_filled,
                      onPressed: () =>
                          lvPush<void>(context, const LvSearchScreen()),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _scroll,
                          child: Column(
                            children: [
                              for (var i = 0; i < books.length; i++)
                                _BookItem(
                                  key: _rowKeys.putIfAbsent(i, GlobalKey.new),
                                  book: books[i],
                                  selected: i == selected,
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: LvMetrics.of(context).gap),
                      LvScrollButtons(
                        onUp: () => _page(-1),
                        onDown: () => _page(1),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _BookItem extends StatelessWidget {
  const _BookItem({super.key, required this.book, required this.selected});

  final Book book;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final cubit = context.read<LowVisionCubit>();
    final pinned = cubit.isPinned(book);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LvRow(
              title: book.title,
              subtitle: pinned ? 'קבוע ברשימה' : book.author,
              selected: selected,
              onTap: () => lvOpenBook(context, book),
            ),
          ),
          SizedBox(width: m.gap),
          SizedBox(
            width: m.unit * 3.4,
            child: Padding(
              padding: EdgeInsets.only(bottom: m.gap),
              child: LvButton(
                label: pinned ? 'קבוע' : 'קבע',
                icon: pinned
                    ? FluentIcons.pin_24_filled
                    : FluentIcons.pin_24_regular,
                filled: pinned,
                height: double.infinity,
                onPressed: () => cubit.togglePin(book),
              ),
            ),
          ),
          if (!pinned) ...[
            SizedBox(width: m.gap),
            SizedBox(
              width: m.unit * 3.4,
              child: Padding(
                padding: EdgeInsets.only(bottom: m.gap),
                child: LvButton(
                  label: 'הסר',
                  icon: FluentIcons.dismiss_24_filled,
                  filled: false,
                  height: double.infinity,
                  onPressed: () => cubit.removeRecent(book),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
