// lib/services/profanity_filter.dart
//
// Client-side check that runs BEFORE a free-text chat message is
// sent — blocks it locally rather than reacting after it's already
// in the database. Runs entirely on-device, no backend, no Blaze
// plan needed.
//
// This is a starter list, not a comprehensive one. Expand
// _bannedWords as you see what actually gets typed in your rooms;
// treat this as a first layer, not a guarantee.

class ProfanityFilter {
  // Deliberately short starter list covering the most common English
  // slurs/profanity. Add to this as needed — keep entries lowercase,
  // no punctuation.
  static const List<String> _bannedWords = [
    'fuck',
    'shit',
    'bitch',
    'asshole',
    'bastard',
    'cunt',
    'nigger',
    'nigga',
    'faggot',
    'retard',
    'whore',
    'slut',
    'rape',
  ];

  // Common leetspeak substitutions, so "fvck" / "f*ck" / "f4ck" still
  // match. Applied during normalization before comparing against the
  // banned list.
  static const Map<String, String> _leetMap = {
    '0': 'o',
    '1': 'i',
    '3': 'e',
    '4': 'a',
    '5': 's',
    '7': 't',
    r'$': 's',
    '@': 'a',
  };

  static String _normalize(String input) {
    var s = input.toLowerCase();
    _leetMap.forEach((from, to) {
      s = s.replaceAll(from, to);
    });
    // Strip everything except letters/digits so "f-u-c-k" or "f_u_c_k"
    // still collapses to "fuck".
    s = s.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return s;
  }

  /// Returns true if [text] contains a banned word after
  /// normalization (case, punctuation, leetspeak all collapsed).
  static bool containsBannedWord(String text) {
    final normalized = _normalize(text);
    for (final word in _bannedWords) {
      if (normalized.contains(word)) return true;
    }
    return false;
  }

  /// Rough personal-info check: flags things that look like a phone
  /// number or email address, so players can't move contact off-app.
  /// Intentionally loose (better to over-flag than miss one).
  static bool containsPersonalInfo(String text) {
    final hasEmail = RegExp(r'[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}').hasMatch(text);
    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
    final hasLongNumber = digitsOnly.length >= 7;
    return hasEmail || hasLongNumber;
  }

  /// Combined check used by the chat input before sending.
  static bool isAllowed(String text) {
    if (containsBannedWord(text)) return false;
    if (containsPersonalInfo(text)) return false;
    return true;
  }
}
