// lib/services/safety_service.dart
//
// Chat safety layer: blocking, reporting, and age-gated chat mode
// for online multiplayer. Does not touch offline mode.
//
// Every call here goes through the new methods added to
// firebase_service.dart (blockUser, unblockUser, getBlockedUids,
// putReport, saveBirthdate) — no invented endpoints, no changes to
// any existing FirebaseService method.
//
// RTDB shape this relies on (all under nodes FirebaseService already
// owns):
//   users/{uid}/blockedUids/{blockedUid}: true
//   users/{uid}/birthdate: "YYYY-MM-DD"   (merged via saveBirthdate)
//   users/{uid}/banned: true|false        (set manually, see below)
//   reports/{reportId}: {
//     reporterUid, reportedUid, roomId, reason, messageSnapshot, timestamp
//   }

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';

enum ReportReason { harassment, spam, inappropriateContent, other }

extension ReportReasonLabel on ReportReason {
  String get label {
    switch (this) {
      case ReportReason.harassment:
        return 'Harassment or bullying';
      case ReportReason.spam:
        return 'Spam';
      case ReportReason.inappropriateContent:
        return 'Inappropriate content';
      case ReportReason.other:
        return 'Other';
    }
  }
}

class SafetyService {
  SafetyService(this._fb);
  final FirebaseService _fb;

  // ---------------------------------------------------------------
  // BLOCKING
  // Client-side filtering: the blocked user isn't removed from the
  // room, they just stop appearing for the blocker.
  // ---------------------------------------------------------------

  Future<void> blockUser({
    required String myUid,
    required String idToken,
    required String blockedUid,
  }) async {
    await _fb.blockUser(myUid, blockedUid, idToken);
  }

  Future<void> unblockUser({
    required String myUid,
    required String idToken,
    required String blockedUid,
  }) async {
    await _fb.unblockUser(myUid, blockedUid, idToken);
  }

  /// Fetch the current user's blocklist as a set of uids.
  Future<Set<String>> getBlockedUids({
    required String myUid,
    required String idToken,
  }) async {
    final raw = await _fb.getBlockedUids(myUid, idToken);
    if (raw == null) return {};
    return raw.keys.map((k) => k.toString()).toSet();
  }

  /// Filter a list of chat messages, dropping any authored by a
  /// blocked uid. Call this right before rendering the chat list.
  List<T> filterBlocked<T>({
    required List<T> messages,
    required Set<String> blockedUids,
    required String Function(T) authorUidOf,
  }) {
    return messages
        .where((m) => !blockedUids.contains(authorUidOf(m)))
        .toList();
  }

  // ---------------------------------------------------------------
  // REPORTING
  // Logs an incident for manual review. Does not take automatic
  // action — pair with the manual ban flag below.
  // ---------------------------------------------------------------

  Future<void> reportUser({
    required String reporterUid,
    required String idToken,
    required String reportedUid,
    required String roomId,
    required ReportReason reason,
    String? messageSnapshot,
  }) async {
    final reportId = DateTime.now().millisecondsSinceEpoch.toString();
    await _fb.putReport(
      reportId,
      {
        'reporterUid': reporterUid,
        'reportedUid': reportedUid,
        'roomId': roomId,
        'reason': reason.name,
        if (messageSnapshot != null) 'messageSnapshot': messageSnapshot,
        'timestamp': DateTime.now().toIso8601String(),
      },
      idToken,
    );
  }

  // ---------------------------------------------------------------
  // BANNING (manual, developer-triggered)
  // Reads the same node getUser() already fetches — no new endpoint.
  // There's no in-app UI for setting this on purpose; you set
  // users/{uid}/banned = true by hand in the Firebase console (or a
  // small admin script) after reviewing a report, then check it here
  // at login / room-join time and reject if true.
  // ---------------------------------------------------------------

  Future<bool> isBanned({
    required String uid,
    required String idToken,
  }) async {
    final raw = await _fb.getUser(uid, idToken);
    if (raw == null) return false;
    return raw['banned'] == true;
  }

  // ---------------------------------------------------------------
  // AGE-GATED CHAT MODE
  // Default posture: restricted (preset-phrase-only) chat for
  // everyone, unless the account has a birthdate on file that
  // implies 18+. No birthdate on file -> restricted.
  // ---------------------------------------------------------------

  static const int adultAge = 18;

  /// Reads birthdate off the same user node getUser() already
  /// returns (saveBirthdate merges it in alongside existing fields).
  Future<String?> getBirthdate({
    required String uid,
    required String idToken,
  }) async {
    final raw = await _fb.getUser(uid, idToken);
    return raw?['birthdate'] as String?;
  }

  /// true => user may use free-text chat.
  /// false => user is limited to preset phrases only.
  bool isFreeTextAllowed(String? birthdateIso) {
    if (birthdateIso == null || birthdateIso.isEmpty) return false;
    final dob = DateTime.tryParse(birthdateIso);
    if (dob == null) return false;
    final now = DateTime.now();
    var age = now.year - dob.year;
    final hadBirthdayThisYear =
        now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) age -= 1;
    return age >= adultAge;
  }

  Future<void> saveBirthdate({
    required String uid,
    required String idToken,
    required DateTime birthdate,
  }) async {
    final iso =
        '${birthdate.year.toString().padLeft(4, '0')}-'
        '${birthdate.month.toString().padLeft(2, '0')}-'
        '${birthdate.day.toString().padLeft(2, '0')}';
    await _fb.saveBirthdate(uid, iso, idToken);
  }
}

// ---------------------------------------------------------------
// Riverpod wiring — mirrors firebaseServiceProvider's own pattern.
// ---------------------------------------------------------------
final safetyServiceProvider = Provider<SafetyService>((ref) {
  final fb = ref.read(firebaseServiceProvider);
  return SafetyService(fb);
});
