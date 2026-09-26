// lib/game/game_notifier.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/board_logic.dart';
import '../services/firebase_service.dart';
import '../services/audio_service.dart';
import 'game_state.dart';

final gameProvider = StateNotifierProvider<GameNotifier, GameState>(
  (ref) => GameNotifier(ref),
);

class GameNotifier extends StateNotifier<GameState> {
  GameNotifier(this._ref) : super(const GameState());

  final Ref _ref;
  final _rng = Random();
  Timer? _pollTimer;
  bool _botRunning = false;
  bool _moveLock = false;
  int _gameSession = 0; // bumped every setupGame(); invalidates stale timers

  // FIX (online move/poll race): bumped every time a local move is applied
  // in online mode. _pollRoom() snapshots this before its network GET and
  // checks it again after — if a local move happened mid-flight, the GET's
  // result is now stale (older than what's on screen) and is discarded
  // instead of being applied, which is what was causing a moved token to
  // visibly snap back and then re-move a moment later. Local/vsBot modes
  // never touch this.
  int _localMoveSeq = 0;

  AudioService get _audio => _ref.read(audioServiceProvider);
  FirebaseService get _fb => _ref.read(firebaseServiceProvider);

  // FIX (online join/poll bug): Firebase RTDB's REST API silently returns
  // small-integer-keyed objects ("0","1","2"...) as a JSON ARRAY instead
  // of a JSON object. players/colors/tokens are all keyed by color index
  // (0-3), so a read of these paths can come back as either a Map or a
  // List depending on which slots happen to be filled. The old code did
  // `room['colors'] as Map?`, which throws a runtime type error the
  // instant Firebase hands back a List — this was happening inside
  // joinRoom() BEFORE the patchRoom() call that adds the second player,
  // so joins were failing silently (no catch around the call in
  // lobby_screen.dart, so no error surfaced) and rooms stayed stuck on
  // "waiting" forever. This normalizes either shape into a
  // Map<String, dynamic> keyed by index string. Local play and vsBot
  // never touch this — it's only used in joinRoom/_pollRoom below.
  Map<String, dynamic> _asIndexMap(dynamic raw) {
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is List) {
      final out = <String, dynamic>{};
      for (int i = 0; i < raw.length; i++) {
        if (raw[i] != null) out[i.toString()] = raw[i];
      }
      return out;
    }
    return {};
  }

  // FIX (turn-stuck-on-Red bug): online color assignments are whatever
  // each player actually picked on the colour-select screen (0-3) — they
  // are NOT guaranteed to be contiguous starting at 0. With two players
  // choosing, say, Blue(3) and Green(1), a naive `0..numPlayers-1` cycle
  // (numPlayers=2 -> colors 0,1) lands on color 0 = Red, which nobody
  // occupies, and the game gets stuck showing "Red's Turn" forever.
  // This returns the real, sorted list of occupied colors for online
  // mode so turn-cycling and win-checks always land on someone who
  // actually exists in the room. Local/vsBot never call this — they
  // keep their original 0..numPlayers-1 behaviour untouched below.
  List<int> _onlineOccupiedColors() => state.tokens.keys.toList()..sort();

  // —— Setup ——
  void setupGame({
    required GameMode mode,
    BotDifficulty difficulty = BotDifficulty.hard,
    bool twoDice = false,
    int numPlayers = 4,
    int playerColor = 0,
  }) {
    _stopPoll();
    _botRunning = false;
    _moveLock = false;
    _gameSession++;

    final n = mode == GameMode.vsBot ? 4 : numPlayers;

    // Build player names with human at chosen colour seat
    final Map<int, String> names = {};
    if (mode == GameMode.vsBot) {
      int botNum = 1;
      for (int i = 0; i < 4; i++) {
        if (i == playerColor) {
          names[i] = 'You';
        } else {
          names[i] = 'Bot $botNum';
          botNum++;
        }
      }
    } else {
      for (int i = 0; i < n; i++) {
        names[i] = i == playerColor ? 'You' : 'Player ${i + 1}';
      }
    }

    final tokens = {
      for (int i = 0; i < n; i++)
        i: kNestPositions[i].map((p) => List<int>.from(p)).toList(),
    };

    state = state.copyWith(
      mode: mode,
      botDifficulty: difficulty,
      twoDiceMode: twoDice,
      numPlayers: n,
      playerIndex: playerColor,
      playerColorIndex: playerColor,
      currentTurn: 0,
      playerNames: names,
      playerUids: const {}, // NEW: reset per-seat uid map on every fresh setup
      tokens: tokens,
      dice1: 0,
      dice2: 0,
      sixCount: 0,
      bonusRolls: 0,
      pendingDice: 0,
      finishedPlayers: [],
      winner: null,
      status: GameStatus.playing,
      chatMessages: [],
    );

    // FIX (#1): if the human didn't pick the colour that goes first,
    // currentTurn (0) belongs to a bot and nothing was kicking it off.
    if (mode == GameMode.vsBot && state.currentTurn != state.playerIndex) {
      _scheduleBotTurn();
    }
  }

  // —— Set player colour (online / picker) ——
  void setPlayerColor(int colorIndex, String displayName) {
    state = state.copyWith(
      playerIndex: colorIndex,
      playerColorIndex: colorIndex,
      playerDisplayName: displayName,
    );
    final ud = state.userData;
    if (ud != null) {
      state = state.copyWith(userData: ud.copyWith(displayName: displayName));
    }
  }

  // —— Roll dice ——
  Future<void> rollDice() async {
    if (_moveLock) return;

    // FIX (online roll/poll race — turn skipped before it could be
    // played): every other place that mutates online state (_doMove,
    // _advanceTurn) bumps _localMoveSeq before its first await, so a
    // poll GET already in flight at that moment is recognized as stale
    // and discarded when it returns (see _pollRoom). rollDice() was the
    // one place that never did this. Its own `await _syncRoom();` below
    // yields control back to the event loop, and the periodic poll timer
    // keeps firing independently of that — so a poll response could land
    // in that window and overwrite the just-rolled dice1/dice2 back to
    // their pre-roll (usually 0) values. The legal-move check right
    // after gates on `state.dice1 > 0`/`state.dice2 > 0` (not the local
    // d1/d2 variables), so a zeroed-out state.dice1/dice2 made it look
    // like there was no legal move — even when there genuinely was one —
    // and immediately forfeited the turn to the next player. No effect
    // on local/vsBot: _localMoveSeq is only ever read/used by the online
    // poll/sync path.
    if (state.mode == GameMode.online) _localMoveSeq++;

    final d1 = _rng.nextInt(6) + 1;
    final d2 = state.twoDiceMode ? _rng.nextInt(6) + 1 : 0;
    await _audio.play('dice');

    // Extra turn only on double-6 in two-dice mode, or a 6 in single-dice mode.
    // Bonus rolls STACK: a six/double-6 banks one roll, and a capture (handled
    // in _doMove) banks another — both can be owed at once. sixCount caps
    // SIX-based bonuses at 3 in a row, but the 3rd six is still fully played;
    // it just doesn't bank a 4th six-based bonus on top.
    final isDouble = state.twoDiceMode ? (d1 == 6 && d2 == 6) : d1 == 6;
    int sixCount = state.sixCount;
    // Consume the banked roll that justified this call (if any); any leftover
    // banked rolls from a prior capture/six combo are preserved.
    int bonus = state.bonusRolls > 0 ? state.bonusRolls - 1 : 0;

    if (isDouble) {
      await _audio.play('six');
      sixCount++;
      if (sixCount < 3) bonus += 1;
    } else {
      sixCount = 0;
    }

    state = state.copyWith(
      dice1: d1,
      dice2: d2,
      sixCount: sixCount,
      bonusRolls: bonus,
      pendingDice: 0,
    );
    await _syncRoom();

    // FIX (#turn-stuck / local play): this must check whoever's turn it
    // ACTUALLY is (state.currentTurn), not state.playerIndex (which is
    // fixed at whichever colour originally set up the game). In vsBot and
    // online, currentTurn == playerIndex is already guaranteed whenever
    // rollDice() runs (the UI only lets the human roll on their own
    // turn), so this is a no-op for those modes. In LOCAL pass-and-play,
    // currentTurn cycles through every colour on the same device, but
    // this was still evaluating the setup player's (red's) tokens no
    // matter whose turn it was. So once it was, say, green's turn and
    // green's tokens genuinely had no legal move for that roll, the game
    // silently checked red's tokens instead, never detected "no move",
    // and never called _advanceTurn() — dice stuck on screen, no sound,
    // no button, forever. Same root cause explained the 3-sixes freeze:
    // whichever player actually rolled 3 sixes in a row was never the
    // one being checked here if they weren't the setup player.
    final playerTokens = state.tokens[state.currentTurn];
    if (playerTokens == null) return;

    // A move is possible this turn if EITHER die can move something
    final movesD1 = state.dice1 > 0
        ? movableTokens(state.currentTurn, playerTokens, d1)
        : <int>[];
    final movesD2 = (state.twoDiceMode && state.dice2 > 0)
        ? movableTokens(state.currentTurn, playerTokens, d2)
        : <int>[];

    if (movesD1.isEmpty && movesD2.isEmpty) {
      await _audio.play('invalid');
      await Future.delayed(const Duration(milliseconds: 1000));
      state = state.copyWith(dice1: 0, dice2: 0, pendingDice: 0);
      if (state.bonusRolls <= 0) {
        await _advanceTurn();
      } else {
        // FIX (online turn/dice desync): banked rolls remain, so we stay
        // on the same player's turn and never reach _advanceTurn() below
        // (which is the only place that used to sync this reset). Without
        // this, the dice1/dice2=0 reset above only ever existed on this
        // device — Firebase still held the old dice values, and the next
        // 1.5s poll would fetch them back and re-populate stale dice on
        // screen. Local/vsBot are unaffected: _syncRoom() no-ops for them.
        await _syncRoom();
      }
    }
  }

  // —— Move token ——
  // dieChoice: 1 = use dice1's value, 2 = use dice2's value (twoDiceMode only)
  Future<bool> moveToken(int player, int tokenIdx, {int dieChoice = 1}) async {
    if (_moveLock) return false;
    _moveLock = true;
    try {
      return await _doMove(player, tokenIdx, dieChoice: dieChoice);
    } finally {
      _moveLock = false;
    }
  }

  Future<bool> _doMove(int player, int tokenIdx, {int dieChoice = 1}) async {
    // FIX (online move/poll race): mark that a local move is happening
    // in online mode BEFORE any awaits below, so a poll GET that was
    // already in flight when this move started is recognized as stale
    // once it comes back (see _pollRoom). No effect on local/vsBot.
    if (state.mode == GameMode.online) _localMoveSeq++;

    final d1 = state.dice1;
    final d2 = state.dice2;
    final steps = (dieChoice == 2 && state.twoDiceMode) ? d2 : d1;
    if (steps == 0) return false;

    final tokens = Map<int, List<List<int>>>.from(
      state.tokens.map(
          (k, v) => MapEntry(k, v.map((p) => List<int>.from(p)).toList())),
    );

    if (!canMove(player, tokens[player]!, tokenIdx, steps)) return false;

    final newPos = calcNewPos(player, tokens[player]!, tokenIdx, steps);
    bool captured = false;

    // Capture check
    if (!isSafe(newPos) &&
        !(newPos[0] == kFinalHome[0] && newPos[1] == kFinalHome[1])) {
      for (final entry in tokens.entries) {
        if (entry.key == player) continue;
        for (int ti = 0; ti < entry.value.length; ti++) {
          final tp = entry.value[ti];
          if (tp[0] == newPos[0] && tp[1] == newPos[1] && !isSafe(tp)) {
            tokens[entry.key]![ti] =
                List<int>.from(kNestPositions[entry.key][ti]);
            captured = true;
          }
        }
      }
    }
    if (captured) await _audio.play('capture');

    tokens[player]![tokenIdx] = newPos;
    await _audio.play('move');

    // Which die(s), if any, are still unplayed after this move
    final remainingD1 = dieChoice == 1 ? 0 : d1;
    final remainingD2 = (dieChoice == 2 && state.twoDiceMode) ? 0 : d2;

    List<int> finished = List<int>.from(state.finishedPlayers);
    int? winner = state.winner;

    if (allHome(tokens[player]!)) {
      if (!finished.contains(player)) finished.add(player);

      if (state.mode == GameMode.vsBot) {
        // Single-player vs bots: first to finish all 4 tokens wins
        // immediately — the game ends right here.
        winner = player;

        if (player == state.playerIndex) {
          final ud = state.userData;
          if (ud != null) {
            final updated = ud.copyWith(
              wins: ud.wins + 1,
              coins: ud.coins + kPlaceRewards[0],
              games: ud.games + 1,
              elo: newElo(ud.elo, kDefaultElo, won: true),
            );
            state = state.copyWith(userData: updated);
            _fb.saveUser(updated);
          }
          await _audio.play('win');
        } else {
          final ud = state.userData;
          if (ud != null) {
            final updated = ud.copyWith(
              losses: ud.losses + 1,
              elo: newElo(ud.elo, kDefaultElo, won: false),
            );
            state = state.copyWith(userData: updated);
            _fb.saveUser(updated);
          }
        }
      } else {
        // Local or online multiplayer: play out full placements —
        // the game only ends once a single player is left unfinished.
        if (player == state.playerIndex) {
          final place = finished.indexOf(player);
          final reward = kPlaceRewards[place.clamp(0, 3)];
          final ud = state.userData;
          if (ud != null) {
            final updated = ud.copyWith(
              wins: ud.wins + 1,
              coins: ud.coins + reward,
              games: ud.games + 1,
              elo: newElo(ud.elo, kDefaultElo, won: true),
            );
            state = state.copyWith(userData: updated);
            _fb.saveUser(updated);
          }
          await _audio.play('win');
        }
        // FIX (turn-stuck-on-Red bug): "who's still playing" must be
        // computed over the colors that actually exist in this game.
        // For online, that's the real occupied colors (e.g. {1,3} for
        // Green+Blue) — NOT 0..numPlayers-1, which for numPlayers=2
        // would check colors {0,1} and could falsely conclude color 0
        // (Red, unoccupied) is "still playing" or miscount who's left.
        // Local/vsBot keep the exact original 0..numPlayers-1 behaviour.
        final activeColors = state.mode == GameMode.online
            ? _onlineOccupiedColors()
            : List<int>.generate(state.numPlayers, (i) => i);
        final remaining = [
          for (final c in activeColors)
            if (!finished.contains(c)) c,
        ];
        if (remaining.length <= 1) {
          if (remaining.isNotEmpty &&
              remaining.first == state.playerIndex &&
              !finished.contains(state.playerIndex)) {
            final ud = state.userData;
            if (ud != null) {
              final updated = ud.copyWith(
                losses: ud.losses + 1,
                elo: newElo(ud.elo, kDefaultElo, won: false),
              );
              state = state.copyWith(userData: updated);
              _fb.saveUser(updated);
            }
          }
          winner = finished.isNotEmpty ? finished.first : player;
        }
      }
    }

    // FIX (#4/#5): only the used die is cleared. If the other die is
    // still unplayed (two-dice mode), the SAME turn continues so it can
    // be applied to a different token, instead of being discarded.
    final stillHasDie =
        (remainingD1 > 0) || (state.twoDiceMode && remainingD2 > 0);

    if (stillHasDie && winner == null) {
      state = state.copyWith(
        tokens: tokens,
        dice1: remainingD1,
        dice2: remainingD2,
        finishedPlayers: finished,
        winner: winner,
        bonusRolls: state.bonusRolls + (captured ? 1 : 0),
      );
      await _syncRoom();

      final movesLeft = movableTokens(
        player,
        tokens[player]!,
        remainingD1 > 0 ? remainingD1 : remainingD2,
      );
      if (movesLeft.isEmpty) {
        // Remaining die can't be used by anything — forfeit just that die
        final bonus = state.bonusRolls;
        state = state.copyWith(dice1: 0, dice2: 0, pendingDice: 0);
        if (bonus <= 0) {
          await _advanceTurn();
        } else {
          // FIX (online turn/dice desync): staying on the same player's
          // turn (bonus banked) means _advanceTurn() — the only other
          // place that used to sync this reset — never runs. Without
          // this, Firebase kept the pre-reset dice values and the next
          // poll would restore stale dice on screen. No-ops off online.
          await _syncRoom();
          if (state.mode != GameMode.online) _scheduleBotTurn();
        }
      }
      return true;
    }

    // Both dice used (or single-die mode) — finish the turn
    final bonus = state.bonusRolls + (captured ? 1 : 0);
    state = state.copyWith(
      tokens: tokens,
      dice1: 0,
      dice2: 0,
      pendingDice: 0,
      finishedPlayers: finished,
      winner: winner,
      bonusRolls: bonus,
    );
    await _syncRoom();

    if (winner == null) {
      if (bonus <= 0) {
        await _advanceTurn();
      } else {
        // Bonus roll(s) banked — same player rolls again
        if (state.mode != GameMode.online) _scheduleBotTurn();
      }
    }
    return true;
  }

  // —— Turn management ——
  Future<void> _advanceTurn() async {
    if (state.gameOver) return;
    // FIX (online move/poll race): advancing the turn also mutates
    // state that a stale poll could clobber (currentTurn, dice, bonus
    // counters), so this counts as a "local move" too.
    if (state.mode == GameMode.online) _localMoveSeq++;

    int nxt;
    if (state.mode == GameMode.online) {
      // FIX (turn-stuck-on-Red bug): cycle through the REAL occupied
      // colors (e.g. Blue=3, Green=1), not a 0..numPlayers-1 range.
      // The old `(currentTurn + 1) % numPlayers` logic assumed colors
      // were assigned contiguously starting at 0, which online colors
      // are not (players freely pick any of the 4). With numPlayers=2
      // and colors {1,3} chosen, that old math could land on color 0
      // (Red) or 2, neither of which any device occupies — the game
      // then shows "Red's Turn" forever with no one able to act.
      final occupied = _onlineOccupiedColors();
      if (occupied.isEmpty) return;
      final curIdx = occupied.indexOf(state.currentTurn);
      // If currentTurn isn't found (shouldn't normally happen), start
      // just before index 0 so the loop below lands on occupied[0].
      int i = curIdx == -1 ? -1 : curIdx;
      int loops = 0;
      do {
        i = (i + 1) % occupied.length;
        loops++;
      } while (state.finishedPlayers.contains(occupied[i]) &&
          loops <= occupied.length);
      nxt = occupied[i];
    } else {
      // Local / vsBot: exact original behaviour, untouched.
      nxt = (state.currentTurn + 1) % state.numPlayers;
      int loops = 0;
      while (state.finishedPlayers.contains(nxt) && loops < state.numPlayers) {
        nxt = (nxt + 1) % state.numPlayers;
        loops++;
      }
    }

    state = state.copyWith(
      currentTurn: nxt,
      dice1: 0,
      dice2: 0,
      pendingDice: 0,
      bonusRolls: 0,
      sixCount: 0,
    );

    // FIX (online turn snap-back bug): every call site above updates
    // state.currentTurn locally and returns, but NONE of them used to
    // push that new currentTurn to Firebase. The room's 'current_turn'
    // field stayed on the PREVIOUS player indefinitely, since nothing
    // else ever wrote it. The very next _pollRoom() (1.5s later) would
    // then fetch that stale value and overwrite the just-advanced local
    // state back to the old player — visibly snapping the turn indicator
    // backwards, and the other device's player would never actually get
    // a turn. _syncRoom() itself already no-ops for local/vsBot
    // (`if (state.mode != GameMode.online || state.roomId == null)
    // return;`), so this call is a no-op there and cannot affect Solo vs.
    // Bot or Local Multiplayer.
    await _syncRoom();

    if (state.mode != GameMode.online) _scheduleBotTurn();
  }

  void _scheduleBotTurn() {
    if (_botRunning) return;
    if (state.gameOver) return;
    if (state.mode == GameMode.localMultiplayer) return;
    if (state.currentTurn == state.playerIndex) return;
    final session = _gameSession;
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (session != _gameSession) return; // a new game started meanwhile
      _runBot();
    });
  }

  // FIX (#3): the bot now runs the same doubles/six extra-turn detection
  // as the human path (rollDice), and plays each die as its own move
  // instead of always moving one token by the summed total.
  Future<void> _runBot() async {
    if (_botRunning || state.gameOver) return;
    if (state.mode == GameMode.localMultiplayer) return;
    if (state.currentTurn == state.playerIndex) return;
    _botRunning = true;
    try {
      final bot = state.currentTurn;
      final d1 = _rng.nextInt(6) + 1;
      final d2 = state.twoDiceMode ? _rng.nextInt(6) + 1 : 0;
      await _audio.play('dice');

      final isDouble = state.twoDiceMode ? (d1 == 6 && d2 == 6) : d1 == 6;
      int sixCount = state.sixCount;
      int bonus = state.bonusRolls > 0 ? state.bonusRolls - 1 : 0;

      if (isDouble) {
        await _audio.play('six');
        sixCount++;
        if (sixCount < 3) bonus += 1;
      } else {
        sixCount = 0;
      }

      state = state.copyWith(
        dice1: d1,
        dice2: d2,
        sixCount: sixCount,
        bonusRolls: bonus,
      );
      await Future.delayed(const Duration(milliseconds: 700));
      if (state.gameOver || state.currentTurn != bot) return;

      await _botPlayDie(bot, 1);
      if (state.gameOver || state.currentTurn != bot) return;

      if (state.twoDiceMode && state.dice2 > 0 && state.currentTurn == bot) {
        await _botPlayDie(bot, 2);
      }
    } finally {
      _botRunning = false;
      if (!state.gameOver &&
          state.currentTurn != state.playerIndex &&
          state.mode != GameMode.localMultiplayer) {
        final session = _gameSession;
        Future.delayed(const Duration(milliseconds: 800), () {
          if (session != _gameSession) return; // a new game started meanwhile
          _runBot();
        });
      }
    }
  }

  Future<void> _botPlayDie(int bot, int dieChoice) async {
    final dieVal = dieChoice == 1 ? state.dice1 : state.dice2;
    if (dieVal == 0) return;

    final ti = botChooseToken(
      player: bot,
      tokens: state.tokens[bot]!,
      steps: dieVal,
      difficulty: state.botDifficulty,
      allTokens: state.tokens,
      dice1: state.dice1,
      dice2: state.dice2,
    );

    if (ti == -1) {
      state =
          dieChoice == 1 ? state.copyWith(dice1: 0) : state.copyWith(dice2: 0);

      if (state.dice1 == 0 && (!state.twoDiceMode || state.dice2 == 0)) {
        final bonus = state.bonusRolls;
        state = state.copyWith(pendingDice: 0);
        if (bonus <= 0) {
          await _advanceTurn();
        }
        // else: banked rolls remain, bot stays on its own turn
      }
    } else {
      await _doMove(bot, ti, dieChoice: dieChoice);
    }
  }

  // —— Online ——
  // FEATURE (online player count): mirrors the 2P/3P/4P choice already
  // offered on the Local Play screen. numPlayers is clamped to [2,4] and
  // written into the room as 'max_players', which joinRoom() below now
  // uses to decide room capacity and when to flip the room to 'playing'
  // — replacing the old hardcoded "cap at 4 / start at 2" behavior. Only
  // used for the online room this creates; vsBot/local setupGame() is
  // untouched and still takes its own numPlayers argument separately.
  Future<String> createRoom({bool twoDice = false, int numPlayers = 4}) async {
    final code = (100000 + _rng.nextInt(899999)).toString();
    final ud = state.userData!;
    final targetPlayers = numPlayers.clamp(2, 4);
    // FIX (color-not-honored bug): this used to be
    // `_rng.nextInt(4)` — a random color, chosen without any regard
    // for whatever the player actually picked on the color-select
    // screen. state.playerColorIndex is set via setPlayerColor() before
    // createRoom() is called, so it reflects the player's real choice;
    // use that instead.
    final myColor = state.playerColorIndex;
    final mySlot = myColor.toString();

    // FIX: putRoom now returns whether the write actually succeeded.
    // Previously this was fire-and-forget, so a rules-rejected write
    // (e.g. locked ".write": false rules) went unnoticed here — the
    // code below would still run, showing a room code and "Waiting for
    // players…" even though nothing was ever saved, which is exactly
    // why joiners got "Room not found" for a code that looked valid.
    final ok = await _fb.putRoom(
        code,
        {
          'players': {mySlot: ud.displayName},
          'colors': {mySlot: myColor},
          // NEW: color-seat -> real account uid. This is what lets
          // block/report resolve a chat message ("Blue said X") back
          // to a specific, stable account instead of just a seat that
          // gets reassigned every game.
          'uids': {mySlot: ud.uid},
          'tokens': {
            mySlot:
                kNestPositions[myColor].map((p) => List<int>.from(p)).toList(),
          },
          // FIX (turn-stuck-on-Red bug): the first turn must belong to
          // the room creator's ACTUAL color, not a hardcoded 0 (Red).
          // If the creator picked, say, Blue (3), hardcoding 0 here
          // meant the game started on a turn that belonged to no one
          // in the room — nobody could ever roll, and the UI was stuck
          // showing "Red's Turn" forever.
          'current_turn': myColor,
          'dice1': 0,
          'dice2': 0,
          'winner': null,
          'state': 'waiting',
          'two_dice_mode': twoDice,
          'max_players': targetPlayers, // NEW: room capacity chosen by creator
          'finished_players': [],
          'chat': {},
        },
        ud.idToken ?? '');

    if (!ok) {
      throw Exception(
          'Could not create room — check your connection and try again.');
    }

    state = state.copyWith(
      roomId: code,
      playerColorIndex: myColor,
      playerIndex: myColor,
      mode: GameMode.online,
      twoDiceMode: twoDice,
      status: GameStatus.waiting,
      numPlayers: 1, // FIX: keeps turn-cycling math correct as joiners land
      currentTurn: myColor, // FIX: matches the current_turn written above
      tokens: {
        myColor: kNestPositions[myColor].map((p) => List<int>.from(p)).toList(),
      },
      playerNames: {myColor: ud.displayName},
      playerUids: {myColor: ud.uid}, // NEW: mirrors the room write above
    );
    _startPoll();
    return code;
  }

  Future<(bool, String)> joinRoom(String code) async {
    final ud = state.userData!;
    final room = await _fb.getRoom(code, ud.idToken ?? '');
    if (room == null) return (false, 'Room not found');
    if (room['state'] == 'playing') {
      return (false, 'Game already in progress');
    }

    // FIX (online join bug): was `Map<String, dynamic>.from(room['players']
    // as Map? ?? {})`. Firebase RTDB's REST API silently returns small-
    // integer-keyed objects ("0","1","2"...) as a JSON ARRAY instead of a
    // JSON object — and players/colors/tokens are keyed by color index, so
    // this cast could throw a runtime type error the moment a room had,
    // say, only slot "2" filled. That exception was being thrown BEFORE
    // the patchRoom() call below that actually adds the joining player,
    // so joins were failing silently (no catch around this in
    // lobby_screen.dart) and rooms stayed stuck on "waiting" forever with
    // no error shown to the user. _asIndexMap normalizes either shape.
    final players = _asIndexMap(room['players']);
    final colors = _asIndexMap(room['colors']);
    // NEW: same normalization for the uids map (see 'uids' write in
    // createRoom above). Rooms created before this feature existed simply
    // won't have this key — _asIndexMap returns {} for that, which is
    // fine: those older rooms' messages just come back with no senderUid.
    final uids = _asIndexMap(room['uids']);
    // FEATURE (online player count): rooms created before this feature
    // (or by any client that omits the field) have no 'max_players' key
    // — default to 4 so those old rooms behave exactly as before. This
    // replaces the previous hardcoded `>= 4` cap with the creator's
    // actual chosen capacity (2, 3, or 4).
    final maxPlayers = ((room['max_players'] as num?)?.toInt() ?? 4).clamp(2, 4);
    if (players.length >= maxPlayers) return (false, 'Room is full');

    // FIX (color-not-honored bug): was
    // `availableColors[_rng.nextInt(availableColors.length)]` — always
    // random, regardless of what the joining player actually picked on
    // the color-select screen (state.playerColorIndex). Now the joiner's
    // chosen color is used whenever it's still free; only when someone
    // else already claimed that exact color does this fall back to a
    // random one from what's left, and the returned message says so.
    final takenColors = colors.values.map((v) => v as int).toSet();
    final availableColors =
        [0, 1, 2, 3].where((c) => !takenColors.contains(c)).toList();
    if (availableColors.isEmpty) return (false, 'Room is full');
    final desired = state.playerColorIndex;
    final bool desiredFree = availableColors.contains(desired);
    final myColor = desiredFree
        ? desired
        : availableColors[_rng.nextInt(availableColors.length)];
    final mySlot = myColor.toString();

    players[mySlot] = ud.displayName;
    colors[mySlot] = myColor;
    uids[mySlot] = ud.uid; // NEW: mirrors createRoom's per-seat uid write
    // FIX: same array-vs-map normalization for tokens (see _asIndexMap note above).
    final tokens = _asIndexMap(room['tokens']);
    tokens[mySlot] =
        kNestPositions[myColor].map((p) => List<int>.from(p)).toList();

    // FEATURE (online player count): the room now starts once the
    // creator's CHOSEN capacity is reached (2P room starts at 2, 3P at
    // 3, 4P at 4) — mirroring how Local Play's numPlayers is fixed
    // upfront rather than always starting the instant a 2nd player
    // shows up. This replaces the previous "always start at 2,
    // regardless of table size" product decision; see the note below.
    final newState = players.length >= maxPlayers ? 'playing' : 'waiting';

    await _fb.patchRoom(
        code,
        {
          'players': players,
          'colors': colors,
          'uids': uids, // NEW
          'tokens': tokens,
          'state': newState,
        },
        ud.idToken ?? '');
    final pMap = {
      for (final e in players.entries) int.parse(e.key): e.value as String,
    };
    // NEW: same shape as pMap, for the uids map.
    final uMap = {
      for (final e in uids.entries) int.parse(e.key): e.value as String,
    };
    final tMap = {
      for (final e in tokens.entries)
        int.parse(e.key):
            (e.value as List).map((r) => List<int>.from(r as List)).toList(),
    };
    state = state.copyWith(
      roomId: code,
      playerColorIndex: myColor,
      playerIndex: myColor,
      numPlayers: players.length, // FIX: keeps % state.numPlayers turn math correct
      mode: GameMode.online,
      twoDiceMode: room['two_dice_mode'] as bool? ?? false,
      playerNames: pMap,
      playerUids: uMap, // NEW
      tokens: tMap,
      // FIX (turn-stuck-on-Red bug): keep whatever current_turn the room
      // already has (set correctly by createRoom to the creator's real
      // color) instead of leaving it defaulted/unset here — the next
      // _pollRoom() will pick up room['current_turn'] anyway, but this
      // avoids a one-frame flash of an incorrect value on the joiner's
      // device between joining and the first poll.
      currentTurn: (room['current_turn'] as num?)?.toInt() ?? state.currentTurn,
      status:
          newState == 'playing' ? GameStatus.playing : GameStatus.waiting,
    );
    _startPoll();
    return (
      true,
      desiredFree
          ? 'Joined!'
          : '${kPlayerNames[desired]} was taken — you got ${kPlayerNames[myColor]} instead'
    );
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
        const Duration(milliseconds: 1500), (_) => _pollRoom());
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollRoom() async {
    if (state.roomId == null || state.userData?.idToken == null) return;
    // FIX (online move/poll race): snapshot the sequence counter before
    // the network round-trip. If a local move bumps it while this GET
    // is in flight, the response we get back is now older than what's
    // already on screen (it reflects pre-move state) — applying it would
    // visibly snap the just-moved token back, until the *next* poll
    // (1.5s later, reflecting the synced move) corrected it again. That
    // round trip is exactly the "goes, comes back, goes again" you saw.
    final pollSeq = _localMoveSeq;
    final room = await _fb.getRoom(state.roomId!, state.userData!.idToken!);
    if (room == null) return;
    if (pollSeq != _localMoveSeq) return; // stale — a local move happened meanwhile, skip
    final tokens = <int, List<List<int>>>{};
    // FIX: was `room['tokens'] as Map?` guarded by an `if (rawT != null)`.
    // Same array-vs-map issue as joinRoom — _asIndexMap always returns a
    // (possibly empty) Map, so this loop is now safe regardless of which
    // shape Firebase returned, and the null guard is no longer needed.
    final rawT = _asIndexMap(room['tokens']);
    for (final e in rawT.entries) {
      tokens[int.parse(e.key.toString())] =
          (e.value as List).map((r) => List<int>.from(r as List)).toList();
    }
    final players = <int, String>{};
    // FIX: same normalization as above, for the same reason.
    final rawP = _asIndexMap(room['players']);
    for (final e in rawP.entries) {
      players[int.parse(e.key.toString())] = e.value.toString();
    }
    // NEW: same normalization for uids, kept in sync every poll so a
    // player who joins mid-game is resolvable for block/report without
    // anyone needing to reload.
    final playerUids = <int, String>{};
    final rawU = _asIndexMap(room['uids']);
    for (final e in rawU.entries) {
      playerUids[int.parse(e.key.toString())] = e.value.toString();
    }
    final finished = ((room['finished_players'] as List?) ?? [])
        .map((e) => e as int)
        .toList();
    final chats = <ChatMessage>[];
    final rawChat = room['chat'] as Map?;
    if (rawChat != null) {
      final sorted = rawChat.values
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      chats.addAll(sorted);
    }
    state = state.copyWith(
      tokens: tokens,
      currentTurn:
          (room['current_turn'] as num?)?.toInt() ?? state.currentTurn,
      dice1: (room['dice1'] as num?)?.toInt() ?? 0,
      dice2: (room['dice2'] as num?)?.toInt() ?? 0,
      winner: room['winner'] as int?,
      playerNames: players,
      playerUids: playerUids, // NEW
      numPlayers: players.isNotEmpty ? players.length : state.numPlayers, // FIX: keep turn math in sync as more players join mid-poll
      finishedPlayers: finished,
      chatMessages: chats,
      status:
          room['state'] == 'playing' ? GameStatus.playing : GameStatus.waiting,
    );
  }

  Future<void> _syncRoom() async {
    if (state.mode != GameMode.online || state.roomId == null) return;
    final tok = {
      for (final e in state.tokens.entries) e.key.toString(): e.value
    };
    await _fb.patchRoom(
        state.roomId!,
        {
          'tokens': tok,
          'current_turn': state.currentTurn,
          'dice1': state.dice1,
          'dice2': state.dice2,
          'winner': state.winner,
          'finished_players': state.finishedPlayers,
        },
        state.userData!.idToken!);
  }

  Future<void> sendChat(String msg) async {
    if (msg.trim().isEmpty) return;
    final entry = ChatMessage(
      player: kPlayerNames[state.playerIndex],
      msg: msg.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      // NEW: tags the message with the real sender uid, when known —
      // this is what block/report actually match against. Falls back to
      // null for local/vsBot (no real per-seat account there), same as
      // before this field existed.
      senderUid: state.userData?.uid,
    );
    if (state.mode == GameMode.online && state.roomId != null) {
      await _fb.patchRoom(
          state.roomId!,
          {'chat/${entry.timestamp}': entry.toJson()},
          state.userData!.idToken!);
    } else {
      state = state.copyWith(chatMessages: [...state.chatMessages, entry]);
    }
  }

  void setUser(UserData ud) => state = state.copyWith(userData: ud);
  void clearUser() => state = state.copyWith(userData: null);

  @override
  void dispose() {
    _stopPoll();
    super.dispose();
  }
}
