import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';

void main() {
  for (final source in ['<br>אב', 'אב<br>', '<br>אב<br>']) {
    test('המרה סימטרית גם כשהתיקון הסיר את שולי $source', () {
      final controller = PluginCorrectionController(source);
      addTearDown(controller.dispose);
      for (final canonical in [controller.source.plain, 'אם', '', ' אמת ']) {
        expect(
          controller.forService(controller.forEditor(canonical)),
          canonical,
        );
      }
    });
  }

  test('עדכון מקור מסנכרן טקסט ושוליים גם כשהטקסט הגלוי זהה', () {
    final controller = PluginCorrectionController('<b>אב</b>');
    addTearDown(controller.dispose);
    controller.setSource('<p>אב</p>');
    expect(controller.text, 'אב');
    expect(controller.forService(controller.text), ' אב ');
    controller.setSource('<i>גד</i>');
    expect(controller.text, 'גד');
    expect(controller.forService(controller.text), 'גד');
  });

  test('הד חוזר של אותו מקור משמר בחירה ו-IME', () {
    const source = '<b>אב</b>';
    final controller = PluginCorrectionController(source);
    addTearDown(controller.dispose);
    const editing = TextEditingValue(
      text: 'אגב',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    controller.value = editing;
    controller.setSource(source);
    expect(controller.value, editing);
  });
}
