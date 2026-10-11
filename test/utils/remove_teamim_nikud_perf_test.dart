import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

// אורקלים: המימושים מבוססי-הרגקס, שהמימוש הנוכחי חייב להחזיר בדיוק כמוהם.
final RegExp _oracleCantillation = RegExp('[֑-֯]');
final RegExp _oracleVowels = RegExp('[ְ-ׇּֿׁׂׅׄ]');

String _oracleRemoveTeamim(String s) => s
    .replaceAll('־', ' ')
    .replaceAll(' ׀', '')
    .replaceAll('ֽ', '')
    .replaceAll('׀', '')
    .replaceAll(_oracleCantillation, '');

String _oracleRemoveNikudOnly(String s) => s.replaceAll(_oracleVowels, '');

const _vocalizedLine =
    '<b>בְּרֵאשִׁ֖ית</b> בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם, וְאֵ֥ת הָאָֽרֶץ׃ '
    'וַיֹּ֥אמֶר יְהוָ֖ה אֶל־מֹשֶׁ֣ה לֵּאמֹ֑ר ׀ דַּבֵּ֞ר אֶל־בְּנֵ֣י יִשְׂרָאֵ֗ל | '
    'רש"י: אין המקרא הזה אומר אלא דרשני (ע"ש.) וכו\' 😀 abc.';

void main() {
  final functions =
      <String, (String Function(String), String Function(String))>{
        'removeTeamim': (removeTeamim, _oracleRemoveTeamim),
        'removeNikudOnly': (removeNikudOnly, _oracleRemoveNikudOnly),
      };

  for (final MapEntry(key: name, value: (current, oracle))
      in functions.entries) {
    group(name, () {
      test('identical to the regex oracle on edge and random input', () {
        final inputs = <String>[
          '',
          _vocalizedLine,
          oracle(_vocalizedLine),
          // פסק אחרי רווח או מקף נמחק יחד איתם; טעם ביניהם מפריד.
          ' ׀ ׀׀־׀־ ׀ ֑׀׀',
          '֐ְּֽ֑֯־ֿ׀׃׆ׇ׈',
          'a\u{1F600}bְ',
        ];
        final random = Random(7);
        const pool = [0x20, 0x7C, 0x41, 0x05BE, 0x05C0, 0x05D0, 0xD83D];
        for (var i = 0; i < 5000; i++) {
          final length = random.nextInt(40);
          inputs.add(
            String.fromCharCodes([
              for (var j = 0; j < length; j++)
                random.nextBool()
                    ? 0x0588 + random.nextInt(0x48)
                    : pool[random.nextInt(pool.length)],
            ]),
          );
        }
        for (final input in inputs) {
          expect(current(input), oracle(input), reason: '${input.codeUnits}');
        }
      });

      test('at least 3x faster than the regex oracle on vocalized lines', () {
        final lines = [for (var i = 0; i < 20000; i++) '$_vocalizedLine $i'];
        int timeMicros(String Function(String) clean) {
          for (final line in lines.take(500)) {
            clean(line);
          }
          final stopwatch = Stopwatch()..start();
          var length = 0;
          for (final line in lines) {
            length += clean(line).length;
          }
          stopwatch.stop();
          expect(length, greaterThan(0));
          return stopwatch.elapsedMicroseconds;
        }

        // מינימום של מדידות לסירוגין: מסנן הפרעות GC ו-JIT בסביבת CI עמוסה.
        var oracleMicros = 1 << 62;
        var currentMicros = 1 << 62;
        for (var round = 0; round < 5; round++) {
          oracleMicros = min(oracleMicros, timeMicros(oracle));
          currentMicros = min(currentMicros, timeMicros(current));
        }
        expect(
          currentMicros * 3,
          lessThan(oracleMicros),
          reason: 'oracle ${oracleMicros}us, current ${currentMicros}us',
        );
      });
    });
  }
}
