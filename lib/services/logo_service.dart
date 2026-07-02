/// Maps a subscription name to a brand icon URL via the Google Favicon API
/// (https://www.google.com/s2/favicons?domain={domain}&sz=128).
///
/// We keep a curated name→domain table for popular services (global + a few
/// Lithuanian ones). The name is normalised (lowercased, non-alphanumerics
/// stripped) so "TV3 Go", "tv3go" and "TV3Go" all resolve the same. If nothing
/// matches, callers fall back to coloured initials — and even a wrong guess is
/// harmless: the favicon fails to load and the image's errorBuilder shows
/// initials instead.
library;

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
  // Creators / misc
  'patreon': 'patreon.com',
  'vinted': 'vinted.com',
  // Lithuanian services
  'telia': 'telia.lt',
  'teliaplay': 'telia.lt',
  'tv3go': 'go.tv3.lt',
  'tv3': 'go.tv3.lt',
  'go3': 'go3.tv',
  'lrt': 'lrt.lt',
  'delfi': 'delfi.lt',
  'lrytas': 'lrytas.lt',
  '15min': '15min.lt',
  'bite': 'bite.lt',
  'tele2': 'tele2.lt',
};

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Best-effort domain for a service name, or null if nothing matches.
String? domainForName(String name) {
  final key = _normalize(name);
  if (key.length < 2) return null;
  final exact = _serviceDomains[key];
  if (exact != null) return exact;
  // Partial match (e.g. "netflix family" → netflix). Longest known keys first
  // so "youtubepremium" wins over "youtube", and short keys don't false-match.
  if (key.length >= 3) {
    final keys = _serviceDomains.keys.toList()
      ..sort((a, b) => b.length - a.length);
    for (final k in keys) {
      if (k.length >= 3 && (key.contains(k) || k.contains(key))) {
        return _serviceDomains[k];
      }
    }
  }
  return null;
}

/// Google-favicon icon URL for a service name, or null when no domain is known.
String? logoUrlForName(String name) {
  final domain = domainForName(name);
  return domain == null
      ? null
      : 'https://www.google.com/s2/favicons?domain=$domain&sz=128';
}
