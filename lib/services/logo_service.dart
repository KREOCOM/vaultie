/// Resolves a merchant name to a BUNDLED, on-device logo asset.
///
/// A curated name→domain table maps popular merchants (global + Lithuanian) to a
/// brand key; `tools/logos` ships each key's logo as an app asset, so showing a
/// logo never fetches anything and never discloses a user's merchants to a third
/// party. Names are normalised (diacritics folded, non-alphanumerics stripped)
/// and matched on whole words, so "TV3 Go"/"tv3go" resolve alike while a brand's
/// letters buried in an unrelated word ("iki" in "vaikiškas") never false-match.
/// Nothing matches → the caller shows its category tile / initials.
library;

import 'bundled_logos.g.dart';

const Map<String, String> _serviceDomains = {
  // Streaming / video
  'netflix': 'netflix.com',
  'youtube': 'youtube.com',
  'youtubepremium': 'youtube.com',
  'youtubemusic': 'youtube.com',
  'amazonprime': 'primevideo.com',
  'primevideo': 'primevideo.com',
  'amazon': 'amazon.com',
  'appletv': 'tv.apple.com',
  'disney': 'disneyplus.com',
  'disneyplus': 'disneyplus.com',
  'hbo': 'hbomax.com',
  'hbomax': 'hbomax.com',
  'max': 'max.com',
  'hulu': 'hulu.com',
  'paramount': 'paramountplus.com',
  'paramountplus': 'paramountplus.com',
  'peacock': 'peacocktv.com',
  'crunchyroll': 'crunchyroll.com',
  'twitch': 'twitch.tv',
  'viaplay': 'viaplay.com',
  // Music / audio
  'spotify': 'spotify.com',
  'applemusic': 'music.apple.com',
  'deezer': 'deezer.com',
  'tidal': 'tidal.com',
  'soundcloud': 'soundcloud.com',
  'audible': 'audible.com',
  // AI / productivity / cloud
  'chatgpt': 'chat.openai.com',
  'chatgptplus': 'chat.openai.com',
  'openai': 'openai.com',
  'claude': 'claude.ai',
  'notion': 'notion.so',
  'grammarly': 'grammarly.com',
  'canva': 'canva.com',
  'figma': 'figma.com',
  'slack': 'slack.com',
  'zoom': 'zoom.us',
  'dropbox': 'dropbox.com',
  'googleone': 'one.google.com',
  'google': 'google.com',
  'microsoft365': 'microsoft.com',
  'office365': 'microsoft.com',
  'microsoft': 'microsoft.com',
  'onedrive': 'onedrive.live.com',
  'icloud': 'icloud.com',
  'apple': 'apple.com',
  'adobe': 'adobe.com',
  'photoshop': 'adobe.com',
  'github': 'github.com',
  'githubcopilot': 'github.com',
  'linkedin': 'linkedin.com',
  // Gaming
  'xbox': 'xbox.com',
  'xboxgamepass': 'xbox.com',
  'gamepass': 'xbox.com',
  'playstation': 'playstation.com',
  'psplus': 'playstation.com',
  'nintendo': 'nintendo.com',
  // Learning / reading / news
  'duolingo': 'duolingo.com',
  'medium': 'medium.com',
  'coursera': 'coursera.org',
  'nytimes': 'nytimes.com',
  // Health / fitness
  'strava': 'strava.com',
  'headspace': 'headspace.com',
  'calm': 'calm.com',
  // VPN / security
  'nordvpn': 'nordvpn.com',
  'expressvpn': 'expressvpn.com',
  'surfshark': 'surfshark.com',
  'lastpass': 'lastpass.com',
  '1password': '1password.com',
  'dashlane': 'dashlane.com',
  // Creators / editing / misc
  'capcut': 'capcut.com',
  'patreon': 'patreon.com',
  'vinted': 'vinted.com',
  // Lithuanian services
  'telia': 'telia.lt',
  'teliaplay': 'telia.lt',
  'tv3go': 'tv3.lt',
  'tv3': 'tv3.lt',
  'go3': 'go3.tv',
  'lrt': 'lrt.lt',
  'delfi': 'delfi.lt',
  'lrytas': 'lrytas.lt',
  '15min': '15min.lt',
  'bite': 'bite.lt',
  'tele2': 'tele2.lt',
  'pildyk': 'pildyk.lt',
  'ezys': 'ezys.lt',
  // ── Everyday merchants (bank feeds are mostly these, not subscriptions) ──
  // Groceries
  'maxima': 'maxima.lt',
  'iki': 'iki.lt',
  'rimi': 'rimi.lt',
  'lidl': 'lidl.lt',
  'norfa': 'norfa.lt',
  'aibe': 'aibe.lt',
  'barbora': 'barbora.lt',
  'lastmile': 'lastmile.lt',
  // Food / drink
  'mcdonalds': 'mcdonalds.com',
  'hesburger': 'hesburger.lt',
  'kfc': 'kfc.lt',
  'subway': 'subway.com',
  'starbucks': 'starbucks.com',
  'caffeine': 'caffeine.lt',
  'vero': 'verocafe.lt',
  'verocafe': 'verocafe.lt',
  'wolt': 'wolt.com',
  'bolt': 'bolt.eu',
  'boltfood': 'bolt.eu',
  'uber': 'uber.com',
  'ubereats': 'ubereats.com',
  // Fuel / transport
  'circlek': 'circlek.lt',
  'neste': 'neste.lt',
  'viada': 'viada.lt',
  'orlen': 'orlen.lt',
  'lukoil': 'lukoil.lt',
  'ignitis': 'ignitis.lt',
  'esoshop': 'eso.lt',
  'trafi': 'trafi.com',
  'ryanair': 'ryanair.com',
  'wizzair': 'wizzair.com',
  'airbaltic': 'airbaltic.com',
  'booking': 'booking.com',
  'airbnb': 'airbnb.com',
  // Pharmacy / health
  'eurovaistine': 'eurovaistine.lt',
  'benuvaistine': 'benu.lt',
  'benu': 'benu.lt',
  'gintarine': 'gintarine.lt',
  'gintarinevaistine': 'gintarine.lt',
  'camelia': 'camelia.lt',
  // Retail / home / electronics
  'ikea': 'ikea.lt',
  'senukai': 'senukai.lt',
  'kesko': 'kesko.lt',
  'topocentras': 'topocentras.lt',
  'avitela': 'avitela.lt',
  'pigu': 'pigu.lt',
  'varle': 'varle.lt',
  'kilobaitas': 'kilobaitas.lt',
  'ermitazas': 'ermitazas.lt',
  'jysk': 'jysk.lt',
  'hm': 'hm.com',
  'zara': 'zara.com',
  'reserved': 'reserved.com',
  'lpp': 'lpp.com',
  'sportlandas': 'sportland.lt',
  'sportland': 'sportland.lt',
  'decathlon': 'decathlon.lt',
  'aliexpress': 'aliexpress.com',
  'temu': 'temu.com',
  'ebay': 'ebay.com',
  // Finance / lending / insurance
  'mogo': 'mogo.lt',
  'seb': 'seb.lt',
  'swedbank': 'swedbank.lt',
  'luminor': 'luminor.lt',
  'citadele': 'citadele.lt',
  'revolut': 'revolut.com',
  'paysera': 'paysera.com',
  'wise': 'wise.com',
  'paypal': 'paypal.com',
  'inbank': 'inbank.lt',
  'general': 'gjensidige.lt',
  'gjensidige': 'gjensidige.lt',
  'lietuvosdraudimas': 'ld.lt',
  'sodra': 'sodra.lt',
  'vmi': 'vmi.lt',
  // Gyms
  'lemonhym': 'lemongym.lt',
  'lemongym': 'lemongym.lt',
  'gymplius': 'gymplius.lt',
  'impuls': 'impuls.lt',
};

// Bank feeds spell Lithuanian merchants both ways ("Eurovaistinė" and
// "EUROVAISTINE"), so diacritics are folded before matching — otherwise the
// accented spelling silently loses its letters ("eurovaistinė" → "eurovaistin")
// and never matches anything.
const _fold = {
  'ą': 'a', 'č': 'c', 'ę': 'e', 'ė': 'e', 'į': 'i', 'š': 's',
  'ų': 'u', 'ū': 'u', 'ž': 'z',
  'ä': 'a', 'ö': 'o', 'õ': 'o', 'ü': 'u', 'å': 'a', 'æ': 'a', 'ø': 'o',
  'é': 'e', 'è': 'e', 'ó': 'o', 'ñ': 'n', 'ç': 'c',
};

String _foldDiacritics(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_fold[ch] ?? ch);
  }
  return b.toString();
}

String _normalize(String s) =>
    _foldDiacritics(s).replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Best-effort domain for a merchant name, or null if nothing matches.
///
/// Matches on WHOLE WORDS, never on loose substrings. Bank feeds are full of
/// names that happen to contain a brand's letters — "vaikiškas" contains "iki",
/// "Sebastijonas" contains "seb" — and a substring match would proudly stamp a
/// supermarket's logo on a toy shop. A wrong logo is worse than none: it reads
/// as the app being confidently wrong about the user's own spending.
///
/// Runs of adjacent words are tried longest-first, so "YouTube Premium" beats
/// "YouTube" and "Topo Centras" resolves at all.
String? domainForName(String name) {
  final full = _normalize(name);
  if (full.length < 2) return null;
  final exact = _serviceDomains[full];
  if (exact != null) return exact;
  final words = _foldDiacritics(name)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  for (var n = words.length; n >= 1; n--) {
    for (var i = 0; i + n <= words.length; i++) {
      final joined = words.sublist(i, i + n).join();
      if (joined.length < 2) continue;
      final hit = _serviceDomains[joined];
      if (hit != null) return hit;
    }
  }
  return null;
}

/// The BUNDLED logo asset for a merchant name, or null if we don't ship one.
///
/// This is the whole point of shipping logos: it resolves entirely on-device, so
/// showing a merchant's logo tells no one — no favicon service, no CDN — which
/// merchants a user pays. Keyed off the same name→brand resolution as everything
/// else, so it never guesses loosely.
String? logoAssetForName(String name) {
  final key = _keyForName(name);
  final file = key == null ? null : kBundledLogos[key];
  return file == null ? null : 'assets/logos/$file';
}

// The brand KEY (e.g. "chatgpt") a name resolves to, or null. Same whole-word,
// diacritic-folded matching as domainForName — just returns the key, not the
// domain, so the bundled-asset lookup can't drift from the domain lookup.
String? _keyForName(String name) {
  final full = _normalize(name);
  if (full.length < 2) return null;
  if (_serviceDomains.containsKey(full)) return full;
  final words = _foldDiacritics(name)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  for (var n = words.length; n >= 1; n--) {
    for (var i = 0; i + n <= words.length; i++) {
      final joined = words.sublist(i, i + n).join();
      if (joined.length >= 2 && _serviceDomains.containsKey(joined)) return joined;
    }
  }
  return null;
}
