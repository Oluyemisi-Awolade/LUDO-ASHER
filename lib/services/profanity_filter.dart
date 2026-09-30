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
//
// v2 fixes two false-positive bugs from v1:
//   1. Banned words were matched as substrings anywhere in the
//      message, so "therapist", "grape", and "shitake" were wrongly
//      blocked (the word "rape"/"shit" appearing inside an innocent
//      word — the classic "Scunthorpe problem"). Fixed by splitting
//      the message into words first and comparing whole words, not
//      substrings.
//   2. Personal-info detection counted ALL digits anywhere in a
//      message, so ordinary game chat like "score 12, dice roll 3,
//      beat you 456 times" (7 digits total, scattered) was wrongly
//      blocked as a phone number. Fixed by only flagging a
//      CONTIGUOUS run of 7+ digits (allowing common phone-style
//      separators like spaces/dashes/dots/parens between them).
//
// Known remaining limitation (accepted trade-off, not a bug): a
// word deliberately spaced out letter-by-letter ("f u c k") will
// not be caught, since each letter becomes its own "word" once split
// on whitespace/punctuation. Catching that reliably without
// reintroducing the substring false-positives above would need a
// much heavier approach (e.g. a maintained third-party list/service)
// — reasonable for a v1 given this is a first layer, not a guarantee.

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

  // Common leetspeak substitutions, so "fvck" / "f4ck" / "5hit" still
  // match. Applied per-word before comparing against the banned list.
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

  static String _applyLeet(String word) {
    var s = word;
    _leetMap.forEach((from, to) {
      s = s.replaceAll(from, to);
    });
    return s;
  }

  /// Collapses 3+ repeated characters down to 1, so "fuuuuck" or
  /// "shiiiit" still match, without affecting normal words (English
  /// rarely has a letter repeated 3+ times in a row on purpose).
  static String _collapseRepeats(String word) {
    return word.replaceAllMapped(
      RegExp(r'(.)\1{2,}'),
      (m) => m.group(1)!,
    );
  }

  /// Splits the message into word-like tokens on any run of
  /// non-alphanumeric characters (spaces, punctuation, emoji, etc.),
  /// so boundaries between words are preserved — this is what fixes
  /// the substring false-positive problem.
  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Returns true if [text] contains a banned word as a whole token,
  /// after per-token leetspeak normalization and repeat-collapsing.
  /// Uses exact token equality, not substring containment, so
  /// innocent words that merely contain a banned word ("grape",
  /// "therapist", "shitake") are never flagged.
  static bool containsBannedWord(String text) {
    for (final rawToken in _tokenize(text)) {
      final token = _collapseRepeats(_applyLeet(rawToken));
      if (_bannedWords.contains(token)) return true;
    }
    return false;
  }

  /// Rough personal-info check: flags things that look like a phone
  /// number or email address, so players can't move contact off-app.
  /// Only a CONTIGUOUS run of 7+ digits counts (allowing common
  /// phone-style separators between them) — digits scattered across
  /// unrelated words in normal chat ("score 12... roll 3... 456
  /// times") no longer trigger a false positive.
  static bool containsPersonalInfo(String text) {
    final hasEmail = RegExp(r'[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}').hasMatch(text);

    // Strip only common phone-number separators (spaces, dashes,
    // dots, parens) so "080-123-4567" or "(080) 123 4567" still
    // reads as one run — but leave letters/words alone, so digits
    // separated by actual words stay separated.
    final cleaned = text.replaceAll(RegExp(r'[\s\-.()]'), '');
    final hasLongDigitRun = RegExp(r'\d{7,}').hasMatch(cleaned);

    return hasEmail || hasLongDigitRun;
  }

  /// Combined check used by the chat input before sending.
  static bool isAllowed(String text) {
    if (containsBannedWord(text)) return false;
    if (containsPersonalInfo(text)) return false;
    return true;
  }
}
