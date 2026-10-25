import 'package:flutter/material.dart';
import 'package:otzaria/plugins/services/plugin_correction_text.dart';

/// בקר טקסט פשוט שמסתיר רק את הרווחים שנוצרו מתגיות בלוק בקצוות.
class PluginCorrectionController extends TextEditingController {
  late PluginCorrectionText source;
  String? _sourceText;
  String _prefix = '';
  String _suffix = '';

  PluginCorrectionController(String raw) {
    setSource(raw);
  }

  void setSource(String raw) {
    if (_sourceText == raw) return;
    source = PluginCorrectionText(raw);
    _sourceText = raw;
    value = TextEditingValue(text: forEditor(source.plain));
  }

  String forEditor(String canonical) {
    final prefix = source.plain.substring(0, source.visibleStart);
    final suffix = source.plain.substring(source.visibleEnd);
    _prefix = '';
    _suffix = '';
    if (!canonical.startsWith(prefix) ||
        !canonical.endsWith(suffix) ||
        canonical.length < prefix.length + suffix.length) {
      return canonical;
    }
    _prefix = prefix;
    _suffix = suffix;
    return canonical.substring(prefix.length, canonical.length - suffix.length);
  }

  String forService(String visible) => _prefix + visible + _suffix;
}
