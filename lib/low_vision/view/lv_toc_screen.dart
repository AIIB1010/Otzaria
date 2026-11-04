import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/models/lv_toc.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';

/// תוכן עניינים: לחיצה על סעיף מדלגת אליו מיד; סעיף עם תתי־סעיפים מציג גם
/// כפתור כניסה אליהם. מחזיר את [LvTocItem.target] שנבחר.
class LvTocScreen extends StatefulWidget {
  const LvTocScreen({
    super.key,
    required this.items,
    required this.bookTitle,
    this.parent,
    this.targetLabel = 'סעיף',
  });

  final List<LvTocItem> items;
  final String bookTitle;

  /// הסעיף שבתוכו אנחנו נמצאים (null בשורש).
  final LvTocItem? parent;
  final String targetLabel;

  @override
  State<LvTocScreen> createState() => _LvTocScreenState();
}

class _LvTocScreenState extends State<LvTocScreen> {
  final _scroll = ScrollController();
  int _selected = -1;

  List<LvTocItem> get _rows => [
    if (widget.parent != null)
      LvTocItem('תחילת: ${widget.parent!.title}', widget.parent!.target),
    ...widget.items,
  ];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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

  void _move(int delta) {
    final rows = _rows;
    if (rows.isEmpty) return;
    final from = _selected < 0 ? (delta > 0 ? -1 : rows.length) : _selected;
    final next = (from + delta).clamp(0, rows.length - 1);
    setState(() => _selected = next);
    final m = LvMetrics.of(context);
    final rowHeight = m.tapHeight * 1.3 + m.gap;
    final top = next * rowHeight;
    final viewport = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + rowHeight > _scroll.offset + viewport) {
      _scroll.jumpTo(top + rowHeight - viewport);
    }
  }

  void _choose(int target) {
    Navigator.of(context).pop<int>(target);
  }

  Future<void> _drill(LvTocItem item) async {
    final result = await Navigator.of(context).push<int>(
      lvRoute<int>(
        LvTocScreen(
          items: item.children,
          bookTitle: widget.bookTitle,
          parent: item,
          targetLabel: widget.targetLabel,
        ),
      ),
    );
    if (result != null && mounted) Navigator.of(context).pop<int>(result);
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final rows = _rows;
    final selected = rows.isEmpty || _selected < 0
        ? -1
        : _selected.clamp(0, rows.length - 1);
    final parentRows = widget.parent != null ? 1 : 0;
    return LvKeyScope(
      actions: {
        LvAction.back: () => Navigator.of(context).maybePop(),
        LvAction.down: () => _move(1),
        LvAction.up: () => _move(-1),
        LvAction.scrollDown: () => _page(0.35),
        LvAction.scrollUp: () => _page(-0.35),
        LvAction.next: () => _page(1),
        LvAction.previous: () => _page(-1),
        LvAction.select: () {
          if (rows.isNotEmpty && selected >= 0) _choose(rows[selected].target);
        },
        LvAction.nextSection: () {
          final i = selected - parentRows;
          if (i >= 0 && i < widget.items.length) {
            final item = widget.items[i];
            if (item.children.isNotEmpty) _drill(item);
          }
        },
      },
      child: LvScaffold(
        title: widget.parent?.title ?? 'תוכן העניינים',
        onBack: () => Navigator.of(context).maybePop(),
        body: rows.isEmpty
            ? const LvMessage('אין תוכן עניינים לספר זה')
            : Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final item = rows[i];
                        final isParentRow = i < parentRows;
                        final hasChildren =
                            !isParentRow && item.children.isNotEmpty;
                        return SizedBox(
                          height: m.tapHeight * 1.3 + m.gap,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: LvRow(
                                  title: item.title,
                                  selected: i == selected,
                                  onTap: () => _choose(item.target),
                                ),
                              ),
                              if (hasChildren) ...[
                                SizedBox(width: m.gap),
                                SizedBox(
                                  width: m.unit * 4.4,
                                  child: Padding(
                                    padding: EdgeInsets.only(bottom: m.gap),
                                    child: LvButton(
                                      label: 'תתי־סעיפים',
                                      icon: FluentIcons.chevron_left_24_filled,
                                      height: double.infinity,
                                      onPressed: () => _drill(item),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: m.gap),
                  LvScrollButtons(
                    onUp: () => _page(-1),
                    onDown: () => _page(1),
                  ),
                ],
              ),
      ),
    );
  }
}
