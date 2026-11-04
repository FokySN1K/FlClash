import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RouteExit.parse', () {
    test('reads the quoted name, the type and the address', () {
      final exit = RouteExit.parse('"HK 01" Vless 1.2.3.4:443');

      expect(exit?.name, 'HK 01');
      expect(exit?.type, 'Vless');
      expect(exit?.address, '1.2.3.4:443');
    });

    test('unquotes the two escapes Go leaves in a name', () {
      final exit = RouteExit.parse(r'"say \"hi\"" Trojan example.com:443');

      expect(exit?.name, 'say "hi"');
      expect(exit?.type, 'Trojan');
      expect(exit?.address, 'example.com:443');
    });

    test('keeps the empty address of a built-in or a group', () {
      expect(RouteExit.parse('"DIRECT" Direct ')?.address, isEmpty);
      expect(RouteExit.parse('"DIRECT" Direct')?.address, isEmpty);
    });

    test('answers nothing for an exit it cannot read', () {
      expect(RouteExit.parse(''), isNull);
      expect(RouteExit.parse('DIRECT'), isNull);
      expect(RouteExit.parse('"unterminated Vless 1.2.3.4:443'), isNull);
    });
  });

  group('a hit list', () {
    test('names the first exit it can read', () {
      const hits = [
        RouteHit(host: 'www.google.com', proxy: 'DIRECT'),
        RouteHit(host: 'www.google.com', exit: '"HK 01" Vless 1.2.3.4:443'),
        RouteHit(host: 'other.example', exit: '"JP 02" Trojan 5.6.7.8:443'),
      ];

      expect(hits.exitInfo?.name, 'HK 01');
    });

    test('names none when no hit carries an exit', () {
      expect(const <RouteHit>[].exitInfo, isNull);
      expect(const [RouteHit(host: 'a')].exitInfo, isNull);
    });
  });
}
