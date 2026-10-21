import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/smart_text_render_stats.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

const _anchorLine =
    'בראשית<a class="link-anchor link-anchor-0" '
    'href="otzaria://anchor?id=1">א</a> ברא';

Widget _wrap(List<Widget> children) => MaterialApp(
  home: Scaffold(body: Column(children: children)),
);

void main() {
  setUp(() {
    SmartTextRenderStats.reset();
    SmartTextRenderStats.enabled = true;
    TextRendererService.clearRenderCacheForTesting();
  });

  tearDown(() {
    SmartTextRenderStats.enabled = false;
    SmartTextRenderStats.reset();
  });

  test('כבוי: לא נספר דבר', () {
    SmartTextRenderStats.enabled = false;
    SmartTextRenderStats.fastLine(heading: false);
    SmartTextRenderStats.fullLine(columnMode: true);
    SmartTextRenderStats.fullPathHtml(_anchorLine);
    SmartTextRenderStats.processTextHit();
    SmartTextRenderStats.processTextMiss(SmartTextRenderStats.startMicros());
    expect(SmartTextRenderStats.startMicros(), 0);
    expect(SmartTextRenderStats.takeAndReset(), isNull);
  });

  test('סיבת הנפילה נספרת רק בהחטאת מטמון של SimpleInlineHtml', () {
    const style = TextStyle(fontSize: 17.25);
    expect(SimpleInlineHtml.tryParse(_anchorLine, style), isNull);
    expect(SimpleInlineHtml.tryParse(_anchorLine, style), isNull);
    expect(SimpleInlineHtml.tryParse('<b>א</b> ב', style), isNotNull);

    final stats = SmartTextRenderStats.takeAndReset()!;
    expect(stats['fullReasons'], {'linkAnchor': 1});
    expect(SmartTextRenderStats.takeAndReset(), isNull);
  });

  test('processText: פגיעה והחטאה במטמון', () {
    const settings = RenderSettings(fontSize: 20);
    TextRendererService.processText('ויאמר משה', settings);
    TextRendererService.processText('ויאמר משה', settings);
    TextRendererService.processText('ויאמר אהרן', settings);

    final stats = SmartTextRenderStats.takeAndReset()!;
    expect(stats['processMisses'], 2);
    expect(stats['processHits'], 1);
    expect(stats['processUncachedMs'], isA<double>());
  });

  testWidgets('שורות מהירות ומלאות נצברות עם בניית fwfh', (tester) async {
    await tester.pumpWidget(
      _wrap(const [
        SmartTextWidget(text: 'ויאמר משה', settings: RenderSettings()),
        SmartTextWidget(
          text: '<h2>פרק א</h2>',
          settings: RenderSettings(),
        ),
        SmartTextWidget(text: _anchorLine, settings: RenderSettings()),
      ]),
    );

    final stats = SmartTextRenderStats.takeAndReset()!;
    expect(stats['fastInline'], 1);
    expect(stats['fastHeading'], 1);
    expect(stats['fullHtml'], 1);
    expect(stats['fwfhBuilds'], 1);
    expect(stats['fullReasons'], {'linkAnchor': 1});
  });

  group('classifyFullPath', () {
    SmartTextFullPathReason classify(String html) =>
        SmartTextRenderStats.classifyFullPath(html);

    test('מזהה את התג הראשון שהמסלול המהיר דוחה', () {
      expect(classify(_anchorLine), SmartTextFullPathReason.linkAnchor);
      expect(
        classify('<b>א</b><span class="link-anchor-range">ב</span>'),
        SmartTextFullPathReason.linkAnchorRange,
      );
      expect(
        classify('<a href="otzaria://book?x">ב</a>'),
        SmartTextFullPathReason.link,
      );
      expect(
        classify('<span style="color: green">ב</span>'),
        SmartTextFullPathReason.styledSpan,
      );
      expect(
        classify('<span class="mam-kq">א</span><span class="x">ב</span>'),
        SmartTextFullPathReason.classSpan,
      );
      expect(classify('א<sup>1</sup>'), SmartTextFullPathReason.supSub);
      expect(classify('<div>א</div>'), SmartTextFullPathReason.block);
      expect(classify('<img src="a.png">'), SmartTextFullPathReason.image);
      expect(classify('א &amp; ב'), SmartTextFullPathReason.entity);
      expect(classify('א</span>'), SmartTextFullPathReason.structure);
    });
  });
}
