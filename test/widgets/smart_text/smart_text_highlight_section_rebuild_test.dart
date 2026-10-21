import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/plugins/view/plugin_highlight_frame_overlay.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

const _text = 'ראש טקסט סוף';
const _bookTitle = 'גיטין';
const _pluginId = 'plugin.section.rebuild.test';

Map<String, dynamic> _payload({required String id, required int section}) => {
  'highlightId': id,
  'bookId': _bookTitle,
  'sectionIndex': section,
  'range': {
    'type': 'text-range-v1',
    'schemaVersion': 1,
    'sourceTextHash':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'layer': 'source',
    'start': {'grapheme': 4, 'codePoint': 4, 'utf16': 4},
    'end': {'grapheme': 8, 'codePoint': 8, 'utf16': 8},
    'exactText': 'טקסט',
    'beforeText': {
      'raw': 'ראש ',
      'normalized': 'ראש ',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'afterText': {
      'raw': ' סוף',
      'normalized': ' סוף',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'occurrenceIndexInSection': 0,
    'occurrenceCountInSection': 1,
  },
  'style': {'backgroundColor': '#FFE066'},
};

Widget _lines(int count) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        for (var i = 0; i < count; i++)
          SmartTextWidget(
            text: _text,
            settings: const RenderSettings(fontSize: 20),
            highlightBookId: _bookTitle,
            highlightSectionIndex: i,
          ),
      ],
    ),
  ),
);

/// הקטעים שה-ListenableBuilder של השורה שלהם נבנה מחדש.
final _rebuiltSections = <int>{};

void _onRebuild(Element element, bool builtOnce) {
  if (element.widget is! ListenableBuilder) return;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is! SmartTextWidget) return true;
    _rebuiltSections.add(widget.highlightSectionIndex!);
    return false;
  });
}

Set<int> _takeRebuilt() {
  final result = Set.of(_rebuiltSections);
  _rebuiltSections.clear();
  return result;
}

Set<int> _drawnSections(WidgetTester tester) => tester
    .widgetList<PluginHighlightFrameOverlay>(
      find.byType(PluginHighlightFrameOverlay),
    )
    .expand((overlay) => overlay.ranges)
    .map((range) => range.highlight.sectionIndex)
    .toSet();

void main() {
  setUp(() {
    PluginHighlightRegistry.instance.removePlugin(_pluginId);
    PluginHighlightRevealService.instance.clear();
    _rebuiltSections.clear();
    debugOnRebuildDirtyWidget = _onRebuild;
  });

  tearDown(() {
    debugOnRebuildDirtyWidget = null;
    PluginHighlightRevealService.instance.clear();
    PluginHighlightRegistry.instance.removePlugin(_pluginId);
  });

  testWidgets('הדגשה חדשה בונה מחדש רק את השורה של הקטע שלה', (tester) async {
    await tester.pumpWidget(_lines(5));
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h2', section: 2),
    );
    await tester.pumpAndSettle();

    expect(_takeRebuilt(), {2});
    expect(_drawnSections(tester), {2});

    PluginHighlightRegistry.instance.removePlugin(_pluginId);
    await tester.pumpAndSettle();

    expect(_takeRebuilt(), {2});
    expect(_drawnSections(tester), isEmpty);
  });

  testWidgets('חשיפת הדגשה בונה מחדש רק את הקטע שלה, גם בכניסה וגם ביציאה', (
    tester,
  ) async {
    final highlight = PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h3', section: 3),
    );
    await tester.pumpWidget(_lines(5));
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRevealService.instance.reveal(highlight);
    await tester.pump();
    expect(_takeRebuilt(), {3});

    PluginHighlightRevealService.instance.clear();
    await tester.pump();
    expect(_takeRebuilt(), {3});
  });

  testWidgets('סיום חשיפה של הדגשה שהועברה בונה מחדש את הקטע החדש', (
    tester,
  ) async {
    final highlight = PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h1', section: 1),
    );
    await tester.pumpWidget(_lines(5));
    await tester.pumpAndSettle();
    PluginHighlightRevealService.instance.reveal(highlight);
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h1', section: 3),
    );
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRevealService.instance.clear();
    await tester.pump();
    expect(_takeRebuilt(), contains(3));
  });

  testWidgets('שורה שהוסרה מהעץ אינה נשארת רשומה לקטע', (tester) async {
    await tester.pumpWidget(_lines(3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_lines(1));
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h2', section: 2),
    );
    await tester.pumpAndSettle();

    expect(_takeRebuilt(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
