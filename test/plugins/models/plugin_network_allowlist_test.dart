import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';

void main() {
  group('matchingNetworkAllowlistPrefix', () {
    const allowlist = [
      'https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books',
      'https://nakdan.dicta.org.il/api',
    ];

    test('מתיר URL מהרשימה ותתי-נתיביו', () {
      expect(
        matchingNetworkAllowlistPrefix(
          Uri.parse(
            'https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books/releases/latest/download/a.zip',
          ),
          allowlist,
        ),
        isNotNull,
      );
      expect(
        matchingNetworkAllowlistPrefix(
          Uri.parse('https://nakdan.dicta.org.il/api?text=שלום'),
          allowlist,
        ),
        isNotNull,
      );
    });

    test('חוסם נתיב אחר, קידומת חלקית ודומיין אחר', () {
      expect(
        matchingNetworkAllowlistPrefix(
          Uri.parse('https://github.com/Someone/Other/releases'),
          allowlist,
        ),
        isNull,
      );
      expect(
        matchingNetworkAllowlistPrefix(
          Uri.parse('https://nakdan.dicta.org.il/apix'),
          allowlist,
        ),
        isNull,
      );
      expect(
        matchingNetworkAllowlistPrefix(
          Uri.parse('https://objects.githubusercontent.com/abc/a.zip'),
          allowlist,
        ),
        isNull,
      );
    });
  });

  group('isUriAllowedForPluginNetwork', () {
    test('מתיר URL של מאגר הספרים המאושר ותתי-נתיביו', () {
      expect(
        isUriAllowedForPluginNetwork(
          Uri.parse(
            'https://github.com/YairDaniel11/Otzarya-Unofficial-Books/releases/latest/download/a.zip',
          ),
        ),
        isTrue,
      );
    });

    test('חוסם דומייני CDN של גיטהאב כגישה ישירה (אינם ברשימה הגלובלית)', () {
      expect(
        isUriAllowedForPluginNetwork(
          Uri.parse('https://objects.githubusercontent.com/abc/a.zip'),
        ),
        isFalse,
      );
      expect(
        isUriAllowedForPluginNetwork(
          Uri.parse('https://release-assets.githubusercontent.com/abc/a.zip'),
        ),
        isFalse,
      );
    });

    test('חוסם מאגר גיטהאב אחר', () {
      expect(
        isUriAllowedForPluginNetwork(
          Uri.parse('https://github.com/Someone/Other/releases'),
        ),
        isFalse,
      );
    });
  });

  group('matchingLoopbackPrefix', () {
    test('host חשוף מתיר כל פורט/נתיב על אותו host', () {
      const allowlist = ['127.0.0.1', 'localhost'];
      expect(
        matchingLoopbackPrefix(
          Uri.parse('http://127.0.0.1:11434/api/tags'),
          allowlist,
        ),
        isNotNull,
      );
      expect(
        matchingLoopbackPrefix(
          Uri.parse('http://localhost:1234/v1/models'),
          allowlist,
        ),
        isNotNull,
      );
    });

    test('URL מלא עם פורט מתיר רק את אותו פורט', () {
      const allowlist = ['http://127.0.0.1:11434'];
      expect(
        matchingLoopbackPrefix(
          Uri.parse('http://127.0.0.1:11434/api/tags'),
          allowlist,
        ),
        isNotNull,
      );
      expect(
        matchingLoopbackPrefix(
          Uri.parse('http://127.0.0.1:1234/api/tags'),
          allowlist,
        ),
        isNull,
      );
    });

    test('חוסם כשאין הצהרת loopback תואמת, או כשהיעד אינו loopback', () {
      expect(
        matchingLoopbackPrefix(
          Uri.parse('http://127.0.0.1:11434/api'),
          const [],
        ),
        isNull,
      );
      expect(
        matchingLoopbackPrefix(Uri.parse('https://example.com'), const [
          '127.0.0.1',
        ]),
        isNull,
      );
    });
  });

  group('isLoopbackHost', () {
    test('127.0.0.0–127.0.0.255, localhost ו-::1', () {
      for (final host in [
        'localhost',
        'LOCALHOST',
        '::1',
        '127.0.0.1',
        '127.0.0.9',
        '127.0.0.0',
        '127.0.0.255',
      ]) {
        expect(isLoopbackHost(host), isTrue, reason: host);
      }
    });

    test('כתובות שאינן loopback קנוני נחשבות אינטרנט', () {
      for (final host in [
        '128.0.0.1',
        '127.0.1.1',
        '127.1.0.0',
        '127.10.10.1',
        '127.255.255.254',
        '172.0.0.1',
        '127.0.0.01',
        '126.255.255.255',
        '127.0.0',
        '127.0.0.1.evil.com',
        'evil127.0.0.1',
        '127.0.0.256',
        '127.1',
        '0127.0.0.1',
        '127.00.0.1',
        '127.0.0.1 ',
        '0.0.0.0',
        '10.0.0.1',
        '192.168.1.1',
        '::ffff:127.0.0.1',
        'example.com',
        '',
      ]) {
        expect(isLoopbackHost(host), isFalse, reason: host);
      }
    });

    test('matchingLoopbackPrefix: host חשוף נועל לכתובת המדויקת', () {
      final uri = Uri.parse('http://127.0.0.9:8080/api');
      expect(matchingLoopbackPrefix(uri, const ['127.0.0.9']), isNotNull);
      expect(matchingLoopbackPrefix(uri, const ['127.0.0.1']), isNull);
      expect(matchingLoopbackPrefix(uri, const ['127.0.0.8']), isNull);
      expect(
        matchingLoopbackPrefix(uri, const ['http://127.0.0.9:8080']),
        isNotNull,
      );
      expect(
        matchingLoopbackPrefix(uri, const ['http://127.0.0.9:9090']),
        isNull,
      );
    });
  });

  group('requiredNetworkPermissionFor', () {
    test('כתובת 127.x.x.x כלשהי דורשת network.localhost', () {
      expect(
        requiredNetworkPermissionFor(Uri.parse('http://127.0.0.9:8080/x')),
        'network.localhost',
      );
    });

    test('יעד loopback דורש network.localhost', () {
      expect(
        requiredNetworkPermissionFor(Uri.parse('http://127.0.0.1:11434')),
        'network.localhost',
      );
      expect(
        requiredNetworkPermissionFor(Uri.parse('http://localhost:1234')),
        'network.localhost',
      );
    });

    test('userinfo מטעה, נקודה סופית ו-IPv6 ממופה אינם נחשבים מקומיים', () {
      for (final url in [
        'http://127.0.0.1@evil.example.com/',
        'http://127.0.0.1:80@evil.example.com/',
        'http://127.0.0.1.:11434/',
        'http://localhost.:1234/',
        'http://[::ffff:127.0.0.1]:11434/',
      ]) {
        expect(
          requiredNetworkPermissionFor(Uri.parse(url)),
          'network.access',
          reason: url,
        );
      }
    });

    test('אותיות גדולות ב-host מקומי נחשבות מקומיות', () {
      expect(
        requiredNetworkPermissionFor(Uri.parse('http://LocalHost:1234/')),
        'network.localhost',
      );
    });

    test('יעד אינטרנט דורש network.access', () {
      expect(
        requiredNetworkPermissionFor(Uri.parse('https://nakdan.dicta.org.il')),
        'network.access',
      );
    });
  });

  group('parsePluginNetworkAllowlistText', () {
    test('מפרק שורות ומדלג על הערות ושורות ריקות', () {
      const source = '''
# הערה בראש הקובץ
https://a.example.com

  https://b.example.com/path
# הערה נוספת
''';

      expect(
        parsePluginNetworkAllowlistText(source),
        ['https://a.example.com', 'https://b.example.com/path'],
      );
    });
  });

  group('isGithubReleaseRedirectAllowed', () {
    final githubRelease = Uri.parse(
      'https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books/releases/latest/download/a.zip',
    );
    final cdn = Uri.parse(
      'https://release-assets.githubusercontent.com/abc/a.zip',
    );

    test('מתיר redirect מ-github.com אל ה-CDN', () {
      expect(isGithubReleaseRedirectAllowed(githubRelease, cdn), isTrue);
    });

    test('מתיר המשך שרשרת redirect בין דומייני CDN', () {
      final cdn2 = Uri.parse('https://objects.githubusercontent.com/x/a.zip');
      expect(isGithubReleaseRedirectAllowed(cdn, cdn2), isTrue);
    });

    test('חוסם redirect ליעד שאינו דומיין CDN של גיטהאב', () {
      final evil = Uri.parse('https://evil.example.com/a.zip');
      expect(isGithubReleaseRedirectAllowed(githubRelease, evil), isFalse);
    });

    test('חוסם redirect ל-CDN ממקור שאינו github/CDN', () {
      final arbitrary = Uri.parse('https://otzaria.org/x');
      expect(isGithubReleaseRedirectAllowed(arbitrary, cdn), isFalse);
    });
  });
}
