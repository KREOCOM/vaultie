import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/services/logo_service.dart';

/// A wrong logo is worse than no logo — it reads as the app being confidently
/// wrong about the user's own spending. These pin the two ways that happens:
/// a brand's letters appearing inside an unrelated word, and a multi-word brand
/// losing to a shorter one.
void main() {
  group('domainForName resolves real merchants', () {
    test('subscriptions', () {
      expect(domainForName('CHATGPT SUBSCRIPTION'), 'chat.openai.com');
      expect(domainForName('Netflix Family'), 'netflix.com');
      expect(domainForName('APPLE.COM/BILL'), 'apple.com');
      expect(domainForName('Spotify P1234'), 'spotify.com');
    });

    test('everyday Lithuanian merchants', () {
      expect(domainForName('MAXIMA LT VILNIUS'), 'maxima.lt');
      expect(domainForName('IKI VILNIUS'), 'iki.lt');
      expect(domainForName('MCDONALDS VILNIUS'), 'mcdonalds.com');
      expect(domainForName('Eurovaistinė'), 'eurovaistine.lt');
      expect(domainForName('MOGO LT'), 'mogo.lt');
    });

    test('multi-word brands beat their shorter prefix', () {
      expect(domainForName('YouTube Premium'), 'youtube.com');
      expect(domainForName('Topo Centras'), 'topocentras.lt');
    });
  });

  group('never guesses from a substring', () {
    test('a brand hiding inside an unrelated word is not a match', () {
      // "vaikiškas" contains "iki"; "Sebastijonas" contains "seb";
      // "maximum" contains "max"; "chemija" contains "hm".
      expect(domainForName('VAIKISKAS PASAULIS'), isNull);
      expect(domainForName('Sebastijonas Petraitis'), isNull);
      expect(domainForName('MAXIMUM FITNESS'), isNull);
      expect(domainForName('UAB CHEMIJA'), isNull);
    });

    test('unknown merchants resolve to nothing, not to something close', () {
      expect(domainForName('UAB ARTUS GRUPE'), isNull);
      expect(domainForName('Zivile Sulajeva'), isNull);
      expect(domainForName(''), isNull);
      expect(domainForName('X'), isNull);
    });
  });
}
