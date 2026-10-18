import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/otzaria_widget_factory.dart';
import 'package:url_launcher/url_launcher.dart';

/// מציג טקסט Markdown (GitHub Flavored) כ-HTML, עם קישורים לחיצים.
///
/// אינו גולל בעצמו — יש לעטוף ב-scrollable בעל היקף מדויק.
class MarkdownHtmlBody extends StatelessWidget {
  const MarkdownHtmlBody(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return HtmlWidget(
      md.markdownToHtml(data, extensionSet: md.ExtensionSet.gitHubFlavored),
      textStyle: textStyle,
      factoryBuilder: OtzariaWidgetFactory.new,
      customStylesBuilder: (element) {
        final font = textStyle?.fontFamily;
        final css = <String, String>{
          'font-weight': ?AppFonts.headingFontWeightOverride(
            element.localName,
            font,
          ),
          'font-size': ?AppFonts.headingFontSizeOverride(
            element.localName,
            font,
          ),
        };
        return css.isEmpty ? null : css;
      },
      onTapUrl: (url) async {
        await launchUrl(Uri.parse(url));
        return true;
      },
    );
  }
}
