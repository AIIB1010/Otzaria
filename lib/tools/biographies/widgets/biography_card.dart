// Card of one sage:
//  - title: name and honorific; era, generation and dates below it
//  - the summary is always shown; a tap expands the details and the
//    "remember" line
//  - teachers, students and relatives with their own entry are links
//  - SelectionArea through ToolResultCardShell for free copying

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/tool_result_card_shell.dart';

class BiographyCard extends StatefulWidget {
  final Biography biography;

  /// Whether a related person's [RelatedPerson.ref] has an entry to open.
  final bool Function(String id) canOpen;

  /// Opens the entry with this id.
  final ValueChanged<String>? onOpen;

  final bool initiallyExpanded;

  const BiographyCard({
    super.key,
    required this.biography,
    this.canOpen = _never,
    this.onOpen,
    this.initiallyExpanded = false,
  });

  static bool _never(String id) => false;

  @override
  State<BiographyCard> createState() => _BiographyCardState();
}

class _BiographyCardState extends State<BiographyCard> {
  /// Width of the button in [SecondaryIconButton]; the slot is kept without it.
  static const double _toggleSlotWidth = 36;

  /// Summary lines shown before expanding.
  static const int _collapsedLines = 2;

  late bool _expanded = widget.initiallyExpanded;

  Biography get _bio => widget.biography;

  String? get _metaLine {
    final parts = <String>[
      [?_bio.eraLabel, ?_bio.generation].join(', '),
      if (_bio.born != null) 'נולד: ${_bio.born!.display}',
      if (_bio.died != null) 'נפטר: ${_bio.died!.display}',
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join('  •  ');
  }

  String? get _knownAsLine =>
      _bio.knownAs.isEmpty ? null : 'נודע גם: ${_bio.knownAs.join(' · ')}';

  /// Labeled detail rows shown when expanded, in the order of the viewer.
  List<(String, String)> get _detailRows => [
    if (_bio.region.isNotEmpty) ('מקומות', _bio.region.join(', ')),
    if (_bio.buried != null) ('מקום מנוחתו', _bio.buried!),
    if (_bio.mentionedIn != null) ('מוזכר ב', _bio.mentionedIn!),
    if (_bio.roles.isNotEmpty) ('תפקידים', _bio.roles.join(' · ')),
  ];

  bool get _hasDetails =>
      _detailRows.isNotEmpty ||
      _bio.teachers.isNotEmpty ||
      _bio.students.isNotEmpty ||
      _bio.family.isNotEmpty ||
      _bio.works.isNotEmpty ||
      _bio.remember != null;

  void _copy() {
    String people(List<RelatedPerson> list) =>
        list.map((p) => p.display).join(' · ');
    final text = [
      _bio.fullName,
      _knownAsLine,
      _metaLine,
      _bio.summary,
      if (_expanded) ...[
        for (final (label, value) in _detailRows) '$label: $value',
        if (_bio.teachers.isNotEmpty) 'רבותיו: ${people(_bio.teachers)}',
        if (_bio.students.isNotEmpty) 'תלמידיו: ${people(_bio.students)}',
        if (_bio.family.isNotEmpty) 'משפחה: ${people(_bio.family)}',
        if (_bio.works.isNotEmpty)
          'חיבוריו: ${_bio.works.map((w) => w.display).join(' · ')}',
        _bio.remember,
      ],
      BiographiesBundle.authorCredit,
    ].whereType<String>().join('\n');
    Clipboard.setData(ClipboardData(text: text));
    UiSnack.show(UiSnack.textCopied);
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  /// Whether [text] needs more than [maxLines] at [width].
  bool _overflows(String text, TextStyle style, double width, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bodyStyle = TextStyle(
      fontSize: AppTokens.fontMD,
      color: cs.onSurface,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Text width: the card width minus the shell's horizontal padding.
        final textWidth = constraints.maxWidth - AppTokens.spaceMD * 2;
        final summary = _bio.summary;
        final clamped =
            summary != null &&
            _overflows(summary, bodyStyle, textWidth, _collapsedLines);
        return _buildCard(cs, bodyStyle, _hasDetails || clamped);
      },
    );
  }

  Widget _buildCard(ColorScheme cs, TextStyle bodyStyle, bool hasBody) {
    final subtitleStyle = TextStyle(
      fontSize: AppTokens.fontMD,
      color: cs.onSurfaceVariant,
    );
    return ToolResultCardShell(
      onTap: hasBody ? _toggle : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: _bio.name,
                    children: [
                      if (_bio.honorific != null)
                        TextSpan(
                          text: ' ${_bio.honorific}',
                          style: TextStyle(
                            fontSize: AppTokens.fontSM,
                            fontWeight: FontWeight.normal,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: AppTokens.fontLG,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceXS),
              // The slot is always kept, or the copy button would move.
              SizedBox(
                width: _toggleSlotWidth,
                child: hasBody
                    ? SecondaryIconButton(
                        icon: _expanded
                            ? FluentIcons.chevron_up_24_regular
                            : FluentIcons.chevron_down_24_regular,
                        tooltip: _expanded ? 'הסתר' : 'הרחב',
                        onPressed: _toggle,
                      )
                    : null,
              ),
              const SizedBox(width: AppTokens.spaceXS),
              SecondaryIconButton(
                icon: FluentIcons.copy_24_regular,
                tooltip: 'העתק',
                onPressed: _copy,
              ),
            ],
          ),
          if (_knownAsLine != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceXS),
              child: Text(_knownAsLine!, style: subtitleStyle),
            ),
          if (_metaLine != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceXS),
              child: Text(_metaLine!, style: subtitleStyle),
            ),
          if (_bio.summary != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSM),
              child: Text(
                _bio.summary!,
                style: bodyStyle,
                maxLines: _expanded ? null : _collapsedLines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            ),
          if (_expanded) ..._buildDetails(cs, bodyStyle),
        ],
      ),
    );
  }

  List<Widget> _buildDetails(ColorScheme cs, TextStyle bodyStyle) {
    final labelStyle = bodyStyle.copyWith(fontWeight: FontWeight.bold);
    final linkStyle = bodyStyle.copyWith(
      color: cs.primary,
      decoration: TextDecoration.underline,
      decorationColor: cs.primary,
    );

    Widget row(String label, List<Widget> values) => Padding(
      padding: const EdgeInsets.only(top: AppTokens.spaceXS),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$label: ', style: labelStyle),
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) Text(' · ', style: bodyStyle),
            values[i],
          ],
        ],
      ),
    );

    Widget person(RelatedPerson p) {
      final ref = p.ref;
      if (ref == null || widget.onOpen == null || !widget.canOpen(ref)) {
        return Text(p.display, style: bodyStyle);
      }
      final prefix = p.relation == null ? '' : '${p.relation}: ';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix.isNotEmpty) Text(prefix, style: bodyStyle),
          InkWell(
            onTap: () => widget.onOpen!(ref),
            child: Text(p.name, style: linkStyle),
          ),
        ],
      );
    }

    return [
      const SizedBox(height: AppTokens.spaceXS),
      for (final (label, value) in _detailRows)
        row(label, [Text(value, style: bodyStyle)]),
      if (_bio.teachers.isNotEmpty)
        row('רבותיו', _bio.teachers.map(person).toList()),
      if (_bio.students.isNotEmpty)
        row('תלמידיו', _bio.students.map(person).toList()),
      if (_bio.family.isNotEmpty)
        row('משפחה', _bio.family.map(person).toList()),
      if (_bio.works.isNotEmpty)
        row('חיבוריו', [
          for (final work in _bio.works)
            Text.rich(
              TextSpan(
                text: work.title,
                style: labelStyle.copyWith(fontWeight: FontWeight.w600),
                children: [
                  if (work.description != null)
                    TextSpan(
                      text: ' - ${work.description}',
                      style: bodyStyle,
                    ),
                ],
              ),
            ),
        ]),
      if (_bio.remember != null)
        Container(
          margin: const EdgeInsets.only(top: AppTokens.spaceSM),
          padding: const EdgeInsets.all(AppTokens.spaceSM),
          decoration: BoxDecoration(
            color: cs.secondaryContainer.withValues(alpha: 0.5),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Text(
            _bio.remember!,
            style: bodyStyle.copyWith(color: cs.onSecondaryContainer),
          ),
        ),
    ];
  }
}
