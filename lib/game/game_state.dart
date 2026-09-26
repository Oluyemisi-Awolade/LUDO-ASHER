// lib/game/game_state.dart
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../core/board_logic.dart';
import 'dart:math';

enum GameMode { vsBot, localMultiplayer, online }
enum BotDifficulty { easy, hard, hardest }
enum GameStatus { waiting, playing, finished }

// Sentinel used by copyWith so nullable fields (winner, roomId) can be
// explicitly reset to null. A plain `x ?? this.x` pattern can NEVER null
// out a field once set, because `null ?? this.x` just returns the old
// value — this was the root cause of Play Again not actually resetting
// gameOver (winner stayed populated from the previous match forever).
const Object _unset = Object();

@immutable
class GameState {
  final GameMode mode;
  final BotDifficulty botDifficulty;
  final GameStatus status;
  final bool twoDiceMode;
  final int numPlayers;
  final int currentTurn;
  final int playerIndex;
  final int playerColorIndex;
  final String playerDisplayName;
  final Map<int, String> playerNames;
  // NEW: color-seat -> real account uid, for online rooms. Populated by
  // createRoom/joinRoom/_pollRoom in game_notifier.dart alongside the
  // existing playerNames map. Empty for local/vsBot (no real accounts
  // per seat there). This is what makes block/report possible — it's
  // the only place a chat message's seat ("Blue") can be resolved back
  // to a specific, stable account.
  final Map<int, String> playerUids;
  final Map<int, List<List<int>>> tokens;
  final int dice1;
  final int dice2;
  final int sixCount;
  final int bonusRolls; // banked extra rolls owed (six/double-6 + captures stack)
  final int pendingDice; // legacy field, kept for compatibility; unused now
  final List<int> finishedPlayers;
  final int? winner;
  final List<ChatMessage> chatMessages;
  final String? roomId;
  final UserData? userData;

  const GameState({
    this.mode = GameMode.vsBot,
    this.botDifficulty = BotDifficulty.hard,
    this.status = GameStatus.waiting,
    this.twoDiceMode = false,
    this.numPlayers = 4,
    this.currentTurn = 0,
    this.playerIndex = 0,
    this.playerColorIndex = 0,
    this.playerDisplayName = 'You',
    this.playerNames = const {},
    this.playerUids = const {},
    this.tokens = const {},
    this.dice1 = 0,
    this.dice2 = 0,
    this.sixCount = 0,
    this.bonusRolls = 0,
    this.pendingDice = 0,
    this.finishedPlayers = const [],
    this.winner = null,
    this.chatMessages = const [],
    this.roomId = null,
    this.userData = null,
  });

  int get totalDice => twoDiceMode ? dice1 + dice2 : dice1;

  // FIX: a die still pending (unplayed) counts as "rolled" — previously
  // this went false the instant dice1 was consumed even if dice2 was
  // still waiting to be played, which broke two-dice mode mid-turn.
  bool get diceRolled => dice1 > 0 || dice2 > 0;

  bool get isPlayerTurn => currentTurn == playerIndex;

  // FIX: local multiplayer is pass-and-play on ONE shared device — there's
  // no single "your color" restriction the way there is for vsBot (the
  // bot plays other colors) or Online (each phone only controls its own
  // color). isPlayerTurn alone made the Roll button permanently disabled
  // the moment the turn passed to any color other than the one that set
  // up the game. This getter is what the UI should actually check.
  bool get canCurrentPlayerAct =>
      mode == GameMode.localMultiplayer || isPlayerTurn;

  bool get gameOver => winner != null;

  // FIX: movable tokens are now the union of what dice1 alone can move
  // and what dice2 alone can move — not what the summed total can move.
  List<int> get movable {
    if (!diceRolled || !tokens.containsKey(currentTurn)) return [];
    final t = tokens[currentTurn]!;
    final set = <int>{};
    if (dice1 > 0) set.addAll(movableTokens(currentTurn, t, dice1));
    if (twoDiceMode && dice2 > 0) {
      set.addAll(movableTokens(currentTurn, t, dice2));
    }
    return set.toList();
  }

  // NOTE on winner/roomId: these two params default to the `_unset`
  // sentinel instead of `null`. That lets callers do three different
  // things explicitly:
  //   - omit the param            -> keeps the existing value
  //   - pass `winner: null`       -> ACTUALLY clears it to null
  //   - pass `winner: 2`          -> sets it to 2
  // Every other (non-nullable-semantically-meaningful) field keeps the
  // simple `x ?? this.x` pattern since those never need to be reset to
  // null (ints/bools/etc. always have a real "no value" default already).
  GameState copyWith({
    GameMode? mode,
    BotDifficulty? botDifficulty,
    GameStatus? status,
    bool? twoDiceMode,
    int? numPlayers,
    int? currentTurn,
    int? playerIndex,
    int? playerColorIndex,
    String? playerDisplayName,
    Map<int, String>? playerNames,
    Map<int, String>? playerUids,
    Map<int, List<List<int>>>? tokens,
    int? dice1,
    int? dice2,
    int? sixCount,
    int? bonusRolls,
    int? pendingDice,
    List<int>? finishedPlayers,
    Object? winner = _unset,
    List<ChatMessage>? chatMessages,
    Object? roomId = _unset,
    UserData? userData,
  }) =>
      GameState(
        mode: mode ?? this.mode,
        botDifficulty: botDifficulty ?? this.botDifficulty,
        status: status ?? this.status,
        twoDiceMode: twoDiceMode ?? this.twoDiceMode,
        numPlayers: numPlayers ?? this.numPlayers,
        currentTurn: currentTurn ?? this.currentTurn,
        playerIndex: playerIndex ?? this.playerIndex,
        playerColorIndex: playerColorIndex ?? this.playerColorIndex,
        playerDisplayName: playerDisplayName ?? this.playerDisplayName,
        playerNames: playerNames ?? this.playerNames,
        playerUids: playerUids ?? this.playerUids,
        tokens: tokens ?? this.tokens,
        dice1: dice1 ?? this.dice1,
        dice2: dice2 ?? this.dice2,
        sixCount: sixCount ?? this.sixCount,
        bonusRolls: bonusRolls ?? this.bonusRolls,
        pendingDice: pendingDice ?? this.pendingDice,
        finishedPlayers: finishedPlayers ?? this.finishedPlayers,
        winner: identical(winner, _unset) ? this.winner : winner as int?,
        chatMessages: chatMessages ?? this.chatMessages,
        roomId: identical(roomId, _unset) ? this.roomId : roomId as String?,
        userData: userData ?? this.userData,
      );
}

// —— UserData ——
@immutable
class UserData {
  final String uid;
  final String email;
  final String displayName;
  final int coins;
  final int wins;
  final int losses;
  final int games;
  final int elo;
  final String? idToken;

  const UserData({
    required this.uid,
    required this.email,
    required this.displayName,
    this.coins = 500,
    this.wins = 0,
    this.losses = 0,
    this.games = 0,
    this.elo = kDefaultElo,
    this.idToken,
  });

  UserData copyWith({
    int? coins,
    int? wins,
    int? losses,
    int? games,
    int? elo,
    String? idToken,
    String? displayName,
  }) =>
      UserData(
        uid: uid,
        email: email,
        displayName: displayName ?? this.displayName,
        coins: coins ?? this.coins,
        wins: wins ?? this.wins,
        losses: losses ?? this.losses,
        games: games ?? this.games,
        elo: elo ?? this.elo,
        idToken: idToken ?? this.idToken,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'coins': coins,
        'wins': wins,
        'losses': losses,
        'games': games,
        'elo': elo,
      };

  factory UserData.fromJson(Map<dynamic, dynamic> j, String uid,
          {String? idToken}) =>
      UserData(
        uid: uid,
        email: j['email'] as String? ?? '',
        displayName:
            j['displayName'] as String? ?? j['email'] as String? ?? 'Player',
        coins: (j['coins'] as num?)?.toInt() ?? 500,
        wins: (j['wins'] as num?)?.toInt() ?? 0,
        losses: (j['losses'] as num?)?.toInt() ?? 0,
        games: (j['games'] as num?)?.toInt() ?? 0,
        elo: (j['elo'] as num?)?.toInt() ?? kDefaultElo,
        idToken: idToken,
      );

  factory UserData.offline() => const UserData(
        uid: 'offline',
        email: 'offline@local',
        displayName: 'Player',
      );
}

// —— ChatMessage ——
@immutable
class ChatMessage {
  final String player;
  final String msg;
  final int timestamp;
  // NEW: the sender's real account uid, when known. Nullable/optional so
  // messages already stored in existing rooms (written before this field
  // existed) still parse fine — they just come back with senderUid=null,
  // which simply means "can't be blocked/reported" rather than crashing.
  final String? senderUid;
  const ChatMessage({
    required this.player,
    required this.msg,
    required this.timestamp,
    this.senderUid,
  });
  Map<String, dynamic> toJson() =>
      {'player': player, 'msg': msg, 'time': timestamp, 'uid': senderUid};
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        player: j['player'] as String? ?? '',
        msg: j['msg'] as String? ?? '',
        timestamp: (j['time'] as num?)?.toInt() ?? 0,
        senderUid: j['uid'] as String?,
      );
}

// —— Bot AI ——
int botChooseToken({
  required int player,
  required List<List<int>> tokens,
  required int steps,
  required BotDifficulty difficulty,
  required Map<int, List<List<int>>> allTokens,
  int dice1 = 0,
  int dice2 = 0,
}) {
  final rng = Random();
  final moves =
      movableTokens(player, tokens, steps, dice1: dice1, dice2: dice2);
  if (moves.isEmpty) return -1;
  if (difficulty == BotDifficulty.easy) return moves[rng.nextInt(moves.length)];

  int bestToken = moves.first;
  double bestScore = -1;

  for (final ti in moves) {
    final newPos = calcNewPos(player, tokens, ti, steps);
    final npIdx = pathIndex(player, newPos);
    double score = 0;
    for (final entry in allTokens.entries) {
      if (entry.key == player) continue;
      for (final tp in entry.value) {
        if (tp[0] == newPos[0] && tp[1] == newPos[1] && !isSafe(newPos)) {
          score += difficulty == BotDifficulty.hardest ? 300 : 150;
        }
      }
    }
    if (npIdx >= 100) score += difficulty == BotDifficulty.hardest ? 200 : 80;
    if (newPos[0] == kFinalHome[0] && newPos[1] == kFinalHome[1]) {
      score += difficulty == BotDifficulty.hardest ? 500 : 300;
    }
    final pidx = pathIndex(player, tokens[ti]);
    if (pidx == -1) score += difficulty == BotDifficulty.hardest ? 80 : 40;
    if (pidx >= 0 && pidx < 100) {
      score += difficulty == BotDifficulty.hardest ? pidx * 2 : pidx.toDouble();
    }
    if (difficulty == BotDifficulty.hardest) score += rng.nextInt(20);
    if (score > bestScore) {
      bestScore = score;
      bestToken = ti;
    }
  }
  return bestToken;
}
