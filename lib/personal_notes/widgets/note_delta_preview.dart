import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// מציג מסמך Quill לקריאה בלבד כ-RichText לכל שורה, בלי QuillEditor.
///
/// מיועד לתצוגות מקדימות לא-אינטראקטיביות (כרטיסי רשת): אין בחירה, סמן
/// או לחיצה על קישורים. הסגנונות נלקחים מ-[quill.DefaultStyles] כמו בעורך.
class NoteDeltaPreview extends StatelessWidget {
  const NoteDeltaPreview({super.key, required this.document});

  final quill.Document document;

  @override
  Widget build(BuildContext context) {
    final styles = quill.DefaultStyles.getInstance(context);
    final direction = Directionality.of(context);
    // מספור משותף לבלוקים עוקבים, כמו ב-QuillEditor (רמות הזחה הן בלוקים נפרדים).
    final levelCounts = <int, int>{};
    var prevOl = false;
    var clearCounts = false;
    final children = <Widget>[];
    for (final node in document.root.children) {
      final attrs = node.style.attributes;
      final isOl = attrs[quill.Attribute.list.key] == quill.Attribute.ol;
      if (prevOl && !isOl || attrs.isEmpty) clearCounts = true;
      prevOl = isOl;
      if (node is quill.Line) {
        children.add(_rootLine(context, styles, node, direction));
      } else if (node is quill.Block) {
        if (clearCounts) levelCounts.clear();
        clearCounts = false;
        children.add(_block(context, styles, node, direction, levelCounts));
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _rootLine(
    BuildContext context,
    quill.DefaultStyles styles,
    quill.Line line,
    TextDirection direction,
  ) {
    final header = _headerStyle(styles, line.style.attributes);
    final horizontal =
        header?.horizontalSpacing ?? styles.paragraph!.horizontalSpacing;
    final vertical =
        header?.verticalSpacing ?? styles.paragraph!.verticalSpacing;
    final body = _lineText(context, styles, line, direction);
    final decoration = header?.decoration;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: horizontal.left,
        end: horizontal.right,
        top: vertical.top,
        bottom: vertical.bottom,
      ),
      child: decoration == null
          ? body
          : DecoratedBox(decoration: decoration, child: body),
    );
  }

  Widget _block(
    BuildContext context,
    quill.DefaultStyles styles,
    quill.Block block,
    TextDirection ambientDirection,
    Map<int, int> levelCounts,
  ) {
    final attrs = block.style.attributes;
    // כמו ב-Quill: direction=rtl בתוך הקשר RTL הופך את הבלוק ל-LTR.
    final direction =
        attrs[quill.Attribute.direction.key] == quill.Attribute.rtl
        ? (ambientDirection == TextDirection.rtl
              ? TextDirection.ltr
              : TextDirection.rtl)
        : ambientDirection;
    final blockStyle = _blockStyle(styles, attrs);
    final isQuote = attrs.containsKey(quill.Attribute.blockQuote.key);
    final isCode = attrs.containsKey(quill.Attribute.codeBlock.key);
    final listAttr = attrs[quill.Attribute.list.key];
    final fontSize = styles.paragraph?.style.fontSize ?? 16;
    final count = block.children.length;
    final indent = _blockIndent(attrs, fontSize, count);

    var decoration = isQuote
        ? styles.quote!.decoration
        : (isCode ? styles.code!.decoration : null);
    final border = decoration?.border;
    if (isQuote && direction == TextDirection.rtl && border is Border) {
      decoration = decoration!.copyWith(border: Border(right: border.left));
    }

    final lines = <Widget>[];
    var index = 0;
    for (final line in block.children.whereType<quill.Line>()) {
      index++;
      final lineSpacing = _blockLineSpacing(styles, attrs);
      final top = index == 1 ? 0.0 : lineSpacing.top;
      final bottom = index == count ? 0.0 : lineSpacing.bottom;
      final leading = _leading(
        styles,
        line,
        listAttr,
        isCode,
        fontSize,
        index,
        count,
        levelCounts,
      );
      lines.add(
        Padding(
          padding: EdgeInsets.only(top: top, bottom: bottom),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: indent.left, child: leading),
              Expanded(child: _lineText(context, styles, line, direction)),
              if (indent.right > 0) SizedBox(width: indent.right),
            ],
          ),
        ),
      );
    }

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: lines,
    );
    if (isCode) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: content,
      );
    }
    if (decoration != null) {
      content = DecoratedBox(decoration: decoration, child: content);
    }
    final horizontal =
        blockStyle?.horizontalSpacing ?? quill.HorizontalSpacing.zero;
    final vertical = blockStyle?.verticalSpacing ?? quill.VerticalSpacing.zero;
    return Directionality(
      textDirection: direction,
      child: Padding(
        padding: EdgeInsets.only(
          left: horizontal.left,
          right: horizontal.right,
          top: vertical.top,
          bottom: vertical.bottom,
        ),
        child: content,
      ),
    );
  }

  Widget? _leading(
    quill.DefaultStyles styles,
    quill.Line line,
    quill.Attribute? listAttr,
    bool isCode,
    double fontSize,
    int index,
    int count,
    Map<int, int> levelCounts,
  ) {
    String numberLabel() => quill.LeadingConfig(
      attribute: listAttr ?? quill.Attribute.codeBlock,
      attrs: line.style.attributes,
      indentLevelCounts: levelCounts,
      index: index,
      count: count,
      style: null,
      width: null,
      padding: null,
      value: false,
      onCheckboxTap: (_) {},
    ).getIndexNumberByIndent!;
    if (isCode) {
      final codeStyle = styles.code!.style;
      return quill.QuillNumberPoint(
        index: numberLabel(),
        indentLevelCounts: levelCounts,
        count: count,
        style: codeStyle.copyWith(
          color: codeStyle.color!.withValues(alpha: 0.4),
        ),
        attrs: line.style.attributes,
        width:
            quill.TextBlockUtils.defaultNumberPointWidthBuilder(
              fontSize,
              count,
            ) -
            fontSize / 4,
        padding: fontSize / 2,
      );
    }
    if (listAttr == null) return null;
    final firstOp = line.toDelta().operations.firstOrNull?.attributes;
    final color = _parseColor(firstOp?[quill.Attribute.color.key]);
    final size = _fontSizeOf(styles, firstOp?[quill.Attribute.size.key]);
    final leadingStyle = styles.leading!.style.copyWith(
      fontSize: size,
      color: color,
    );
    if (listAttr == quill.Attribute.ul) {
      return quill.QuillBulletPoint(
        style: leadingStyle.copyWith(fontWeight: FontWeight.bold),
        width: quill.TextBlockUtils.defaultNumberPointWidthBuilder(fontSize, 1),
        padding: fontSize / 2,
      );
    }
    if (listAttr == quill.Attribute.ol) {
      return quill.QuillNumberPoint(
        index: numberLabel(),
        indentLevelCounts: levelCounts,
        count: count,
        style: leadingStyle,
        attrs: line.style.attributes,
        width: quill.TextBlockUtils.defaultNumberPointWidthBuilder(
          fontSize,
          count,
        ),
        padding: fontSize / 2,
      );
    }
    if (listAttr == quill.Attribute.checked ||
        listAttr == quill.Attribute.unchecked) {
      return quill.QuillCheckboxPoint(
        size: fontSize,
        value: listAttr == quill.Attribute.checked,
        enabled: false,
        onChanged: (_) {},
        uiBuilder: styles.lists?.checkboxUIBuilder,
      );
    }
    return null;
  }

  Widget _lineText(
    BuildContext context,
    quill.DefaultStyles styles,
    quill.Line line,
    TextDirection direction,
  ) {
    final lineStyle = _lineStyle(styles, line.style.attributes);
    final children = <InlineSpan>[
      for (final leaf in line.children)
        if (leaf is quill.QuillText)
          TextSpan(
            text: leaf.value,
            style: _inlineStyle(styles, leaf.style.attributes, line.style),
          ),
    ];
    return RichText(
      text: TextSpan(style: lineStyle, children: children),
      textAlign: _textAlign(line.style.attributes[quill.Attribute.align.key]),
      textDirection: direction,
      strutStyle: StrutStyle.fromTextStyle(lineStyle),
      textScaler: MediaQuery.textScalerOf(context),
    );
  }

  static quill.DefaultTextBlockStyle? _headerStyle(
    quill.DefaultStyles styles,
    Map<String, quill.Attribute> attrs,
  ) {
    final level = attrs[quill.Attribute.header.key]?.value;
    return switch (level is num ? level.toInt() : null) {
      1 => styles.h1,
      2 => styles.h2,
      3 => styles.h3,
      4 => styles.h4,
      5 => styles.h5,
      6 => styles.h6,
      _ => null,
    };
  }

  static quill.DefaultTextBlockStyle? _blockStyle(
    quill.DefaultStyles styles,
    Map<String, quill.Attribute> attrs,
  ) {
    if (attrs.containsKey(quill.Attribute.blockQuote.key)) return styles.quote;
    if (attrs.containsKey(quill.Attribute.codeBlock.key)) return styles.code;
    if (attrs.containsKey(quill.Attribute.indent.key)) return styles.indent;
    if (attrs.containsKey(quill.Attribute.list.key)) return styles.lists;
    if (attrs.containsKey(quill.Attribute.align.key)) return styles.align;
    return null;
  }

  static quill.VerticalSpacing _blockLineSpacing(
    quill.DefaultStyles styles,
    Map<String, quill.Attribute> attrs,
  ) {
    final header = _headerStyle(styles, attrs);
    if (header != null) return header.verticalSpacing;
    return (_blockStyle(styles, attrs) ?? styles.paragraph!).lineSpacing;
  }

  /// רוחב ההזחה של שורות הבלוק (מקביל ל-defaultIndentWidthBuilder של Quill).
  static quill.HorizontalSpacing _blockIndent(
    Map<String, quill.Attribute> attrs,
    double fontSize,
    int count,
  ) {
    final indent = attrs[quill.Attribute.indent.key]?.value;
    final extra = indent is num ? fontSize * indent : 0.0;
    if (attrs.containsKey(quill.Attribute.blockQuote.key)) {
      return quill.HorizontalSpacing(fontSize + extra, 0);
    }
    if (attrs.containsKey(quill.Attribute.codeBlock.key)) {
      final width = quill.TextBlockUtils.defaultNumberPointWidthBuilder(
        fontSize,
        count,
      );
      return quill.HorizontalSpacing(
        width - fontSize / 4 + extra,
        fontSize / 2,
      );
    }
    final list = attrs[quill.Attribute.list.key];
    if (list == null) return quill.HorizontalSpacing(extra, 0);
    final base = list == quill.Attribute.ol
        ? quill.TextBlockUtils.defaultNumberPointWidthBuilder(fontSize, count)
        : fontSize * 2;
    return quill.HorizontalSpacing(base + extra, 0);
  }

  static TextStyle _lineStyle(
    quill.DefaultStyles styles,
    Map<String, quill.Attribute> attrs,
  ) {
    var style = (_headerStyle(styles, attrs) ?? styles.paragraph!).style;
    final list = attrs[quill.Attribute.list.key];
    if (attrs.containsKey(quill.Attribute.blockQuote.key)) {
      style = style.merge(styles.quote!.style);
    } else if (attrs.containsKey(quill.Attribute.codeBlock.key)) {
      style = style.merge(styles.code!.style);
    } else if (list != null) {
      style = style.merge(styles.lists!.style);
    }
    return style;
  }

  static TextStyle _inlineStyle(
    quill.DefaultStyles styles,
    Map<String, quill.Attribute> attrs,
    quill.Style lineAttrs,
  ) {
    var res = const TextStyle();
    final color = _parseColor(attrs[quill.Attribute.color.key]?.value);
    void add(String key, TextStyle? style) {
      if (style == null || !attrs.containsKey(key)) return;
      if (key == quill.Attribute.link.key && attrs[key]!.value == null) {
        return;
      }
      final isLineDecoration =
          key == quill.Attribute.underline.key ||
          key == quill.Attribute.strikeThrough.key;
      final decorationColor = color ?? styles.color;
      res = _mergeDecorations(
        isLineDecoration ? res.copyWith(decorationColor: decorationColor) : res,
        isLineDecoration
            ? style.copyWith(decorationColor: decorationColor)
            : style,
      );
    }

    add(quill.Attribute.bold.key, styles.bold);
    add(quill.Attribute.italic.key, styles.italic);
    add(quill.Attribute.small.key, styles.small);
    add(quill.Attribute.link.key, styles.link);
    add(quill.Attribute.underline.key, styles.underline);
    add(quill.Attribute.strikeThrough.key, styles.strikeThrough);

    final script = attrs[quill.Attribute.script.key];
    if (script == quill.Attribute.subscript) {
      res = _mergeDecorations(res, styles.subscript!);
    } else if (script == quill.Attribute.superscript) {
      res = _mergeDecorations(res, styles.superscript!);
    }
    if (attrs.containsKey(quill.Attribute.inlineCode.key)) {
      final inlineCode = styles.inlineCode!;
      res = _mergeDecorations(
        res,
        inlineCode
            .styleFor(lineAttrs)
            .copyWith(backgroundColor: inlineCode.backgroundColor),
      );
    }

    final font = attrs[quill.Attribute.font.key]?.value;
    if (font is String) res = res.merge(TextStyle(fontFamily: font));

    final size = _fontSizeOf(styles, attrs[quill.Attribute.size.key]?.value);
    if (size != null) res = res.merge(TextStyle(fontSize: size));
    if (color != null) res = res.merge(TextStyle(color: color));

    final background = _parseColor(
      attrs[quill.Attribute.background.key]?.value,
    );
    if (background != null) {
      res = res.merge(TextStyle(backgroundColor: background));
    }
    return res;
  }

  static TextStyle _mergeDecorations(TextStyle a, TextStyle b) {
    final decorations = [?a.decoration, ?b.decoration];
    return a.merge(b).apply(decoration: TextDecoration.combine(decorations));
  }

  static TextAlign _textAlign(quill.Attribute? align) {
    if (align == quill.Attribute.centerAlignment) return TextAlign.center;
    if (align == quill.Attribute.rightAlignment) return TextAlign.end;
    if (align == quill.Attribute.justifyAlignment) return TextAlign.justify;
    return TextAlign.start;
  }

  static double? _fontSizeOf(quill.DefaultStyles styles, Object? value) {
    return switch (value) {
      'small' => styles.sizeSmall?.fontSize,
      'large' => styles.sizeLarge?.fontSize,
      'huge' => styles.sizeHuge?.fontSize,
      num() => value.toDouble(),
      String() => double.tryParse(value),
      _ => null,
    };
  }

  static Color? _parseColor(Object? value) {
    if (value is! String || !value.startsWith('#')) return null;
    var hex = value.substring(1);
    if (hex.length == 6) hex = 'ff$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
