import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/text_book/utils/reading_extent_estimates.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// מחברת שינויים בתוכן להערכות הרשימה בלי לאפס מדידות בכל חימום.
class ReadingExtentEstimation extends StatefulWidget {
  const ReadingExtentEstimation({
    super.key,
    required this.segments,
    required this.controller,
    required this.fontSize,
    required this.builder,
    this.lineHeight = 1.5,
    this.fontFamily,
    this.fontWeight,
    this.contentWidthRatio = 1,
    this.verticalPadding = 4,
    this.textWidth,
    this.styleKey,
  });

  final ReadingSegments segments;
  final ItemScrollController controller;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final FontWeight? fontWeight;
  final double contentWidthRatio;
  final double verticalPadding;
  final double Function(double availableWidth)? textWidth;
  final Object? styleKey;
  final Widget Function(ItemExtentEstimator estimator, Object estimationKey)
  builder;

  @override
  State<ReadingExtentEstimation> createState() =>
      _ReadingExtentEstimationState();
}

class _ReadingExtentEstimationState extends State<ReadingExtentEstimation> {
  late final _data = ReadingExtentEstimates(widget.segments);
  ReadingExtentMetrics? _metrics;
  Object? _metricStyle;
  Object _estimationKey = Object();
  bool _refreshScheduled = false;
  double _availableWidth = 0;
  double _itemWidth = 0;

  @override
  void didUpdateWidget(ReadingExtentEstimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _data.update(widget.segments);
    if (!oldWidget.segments.layout.hasSameStructure(widget.segments.layout) ||
        !identical(oldWidget.controller, widget.controller)) {
      _estimationKey = Object();
    }
  }

  void _scheduleRefresh() {
    if (_refreshScheduled || !_data.needsRefresh) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final changes = await _data.refresh();
      _refreshScheduled = false;
      if (!mounted) return;
      if (changes.full) {
        setState(() => _estimationKey = Object());
      } else if (changes.ranges.isNotEmpty && widget.controller.isAttached) {
        final layout = widget.segments.layout;
        final items = <int>{};
        var refreshAll = false;
        for (final range in changes.ranges) {
          final first = layout.itemForLine(range.first);
          final last = layout.itemForLine(range.last);
          if (last - first + 1 > 10000) {
            refreshAll = true;
            break;
          }
          for (var item = first; item <= last; item++) {
            items.add(item);
            if (items.length > 10000) {
              refreshAll = true;
              break;
            }
          }
          if (refreshAll) break;
        }
        if (refreshAll) {
          setState(() => _estimationKey = Object());
        } else {
          unawaited(
            widget.controller.updateEstimatedExtents({
              for (final item in items)
                item: _estimate(
                  item,
                  _itemWidth > 0 ? _itemWidth : _availableWidth,
                ),
            }),
          );
        }
      }
    });
  }

  double _estimate(int index, double width) {
    _itemWidth = width;
    final textWidth = widget.textWidth?.call(width);
    return _data.estimate(
      index,
      textWidth != null && textWidth > 0 ? textWidth : width,
      _metrics!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = (
      widget.fontSize,
      widget.lineHeight,
      widget.fontFamily,
      widget.fontWeight,
      widget.contentWidthRatio,
      widget.verticalPadding,
      widget.styleKey,
      scaler,
    );
    if (_metricStyle != style) {
      const sample = 'בראשית ברא אלהים את השמים ואת הארץ';
      final painter = TextPainter(
        text: TextSpan(
          text: sample,
          style: TextStyle(
            fontSize: widget.fontSize,
            height: widget.lineHeight,
            fontFamily: widget.fontFamily,
            fontWeight: widget.fontWeight,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      _metrics = ReadingExtentMetrics(
        lineExtent: painter.height,
        charWidth: painter.width / sample.length,
        contentWidthRatio: widget.contentWidthRatio,
        verticalPadding: widget.verticalPadding,
      );
      painter.dispose();
      _metricStyle = style;
      _estimationKey = Object();
    }
    _scheduleRefresh();
    return LayoutBuilder(
      builder: (_, constraints) {
        _availableWidth = constraints.maxWidth;
        return widget.builder(_estimate, _estimationKey);
      },
    );
  }
}
