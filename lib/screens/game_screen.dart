// lib/screens/game_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../game/game_notifier.dart';
import '../game/game_state.dart';
import '../services/audio_service.dart';
import '../services/safety_service.dart';
import '../services/profanity_filter.dart';
import '../theme/app_theme.dart';
import '../widgets/board_widget.dart';
import '../widgets/dice_widget.dart';
import '../widgets/common_widgets.dart';
import '../widgets/chat_safety_widgets.dart'
    show kPresetChatPhrases, ReportUserDialog;
import 'menu_screen.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final _chatCtrl = TextEditingController();
  bool _showChat  = false;
  bool _gameOverShown = false;
  bool _waitingActive = false;

  // NEW: age-gated chat mode. Defaults to false (preset-phrase-only)
  // until we've actually confirmed the account is 18+ — same
  // "unknown defaults to restricted" posture as SafetyService itself.
  bool _freeTextAllowed = false;

  // NEW: uids the current account has blocked, loaded once for online
  // games. Filtering happens client-side in _ChatPanel.
  Set<String> _blockedUids = {};

  @override
  void initState() {
    super.initState();
    ref.read(audioServiceProvider).startBgm();
    _loadChatPermission();
    _loadBlockedUids();
  }

  // NEW: loads the caller's blocklist so _ChatPanel can filter messages
  // from anyone already blocked, without waiting on a full app restart.
  Future<void> _loadBlockedUids() async {
    final gs = ref.read(gameProvider);
    final ud = gs.userData;
    if (gs.mode != GameMode.online || ud == null || ud.idToken == null) return;

    final safety = ref.read(safetyServiceProvider);
    final blocked = await safety.getBlockedUids(
      myUid: ud.uid,
      idToken: ud.idToken!,
    );
    if (!mounted) return;
    setState(() => _blockedUids = blocked);
  }

  // NEW: fetches the account's birthdate once (online games only) and
  // decides whether this session gets free-text or preset-only chat.
  Future<void> _loadChatPermission() async {
    final gs = ref.read(gameProvider);
    final ud = gs.userData;
    if (gs.mode != GameMode.online || ud == null || ud.idToken == null) return;

    final safety = ref.read(safetyServiceProvider);
    final birthdate = await safety.getBirthdate(
      uid: ud.uid,
      idToken: ud.idToken!,
    );
    if (!mounted) return;
    setState(() {
      _freeTextAllowed = safety.isFreeTextAllowed(birthdate);
    });
  }

  @override
  void dispose() {
    _chatCtrl.dispose();
    ref.read(audioServiceProvider)
      ..stopBgm()
      ..stopWaiting();
    super.dispose();
  }

  // Waiting loop plays whenever nobody has rolled yet this turn — covers
  // vsBot (your turn, and the bot's brief "thinking" delay before it
  // auto-rolls), and local/online multiplayer (your turn, or waiting on
  // whichever other player's turn it currently is). Stops the instant
  // dice are rolled or the game ends. Guarded by _waitingActive so it's
  // only started/stopped on actual transitions, not every rebuild.
  void _syncWaitingSound(GameState gs) {
    final shouldPlay = !gs.diceRolled && !gs.gameOver;
    if (shouldPlay && !_waitingActive) {
      _waitingActive = true;
      ref.read(audioServiceProvider).startWaiting();
    } else if (!shouldPlay && _waitingActive) {
      _waitingActive = false;
      ref.read(audioServiceProvider).stopWaiting();
    }
  }

  Future<void> _roll() async {
    final gs = ref.read(gameProvider);
    if (!gs.canCurrentPlayerAct || gs.diceRolled || gs.gameOver) return;
    await ref.read(gameProvider.notifier).rollDice();
  }

  void _goBack() {
    ref.read(audioServiceProvider)
      ..stopBgm()
      ..stopWaiting();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MenuScreen()),
    );
  }

  void _checkGameOver(GameState gs) {
    if (gs.gameOver && gs.winner != null && !_gameOverShown) {
      _gameOverShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showGameOverDialog(gs);
      });
    }
  }

  void _showGameOverDialog(GameState gs) {
    final winner = gs.winner!;
    final myWon  = winner == gs.playerIndex;

    // Placement/reward text only makes real sense in multiplayer mode,
    // where the game plays out until a single player remains and
    // finishedPlayers accumulates 1st/2nd/3rd/4th over time. In vsBot
    // mode the game ends the instant the FIRST player finishes, so
    // nobody else ever gets a genuine placement — showing "2nd" for
    // someone who was nowhere close to finishing would be made up.
    late final String placementLine;
    String? rewardLine;

    if (gs.mode == GameMode.vsBot) {
      if (myWon) {
        placementLine = 'You Won! 🏆';
        rewardLine = '+${kPlaceRewards[0]} coins 🪙';
      } else {
        placementLine = "You didn't finish this time";
        rewardLine = null;
      }
    } else {
      final my    = gs.finishedPlayers.indexOf(gs.playerIndex);
      final place = my == -1 ? gs.finishedPlayers.length : my;
      const labels = ['🥇 1st', '🥈 2nd', '🥉 3rd', '4th'];
      placementLine = 'You finished: ${labels[place.clamp(0, 3)]}';
      rewardLine = '+${kPlaceRewards[place.clamp(0, 3)]} coins 🪙';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text('Game Over!',
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 4),
              Text('${kPlayerNames[winner]} wins!',
                  style: TextStyle(
                      fontSize: 18,
                      color: kPlayerColors[winner],
                      fontWeight: FontWeight.w700)),
              const Divider(height: 24, color: AppColors.border),
              Text(placementLine,
                  style: Theme.of(context).textTheme.bodyLarge),
              if (rewardLine != null) ...[
                const SizedBox(height: 4),
                Text(rewardLine,
                    style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
              const Divider(height: 24, color: AppColors.border),
              SupportCard(
                onDonate: () async {
                  final url = Uri.parse(kFlutterwaveUrl);
                  if (await canLaunchUrl(url)) launchUrl(url);
                },
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // Capture the settings to relaunch with BEFORE popping
                      // the dialog, close the dialog, reset the "shown" latch,
                      // then start a brand-new game immediately. Now that
                      // GameState.copyWith can actually clear `winner` back
                      // to null, this rebuilds a genuinely fresh gameOver
                      // state instead of the dialog re-triggering itself.
                      final freshGs = ref.read(gameProvider);
                      Navigator.of(dialogContext, rootNavigator: true).pop();
                      _gameOverShown = false;
                      _waitingActive = false;
                      try {
                        ref.read(gameProvider.notifier).setupGame(
                          mode:        freshGs.mode,
                          difficulty:  freshGs.botDifficulty,
                          twoDice:     freshGs.twoDiceMode,
                          numPlayers:  freshGs.numPlayers,
                          playerColor: freshGs.playerColorIndex,
                        );
                        ref.read(audioServiceProvider).startBgm();
                      } catch (e, st) {
                        debugPrint('Play Again failed: $e\n$st');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Restart failed: $e')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.violet),
                    child: const Text('Play Again'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext, rootNavigator: true).pop();
                      _gameOverShown = false;
                      _waitingActive = false;
                      _goBack();
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade700),
                    child: const Text('Menu'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gs    = ref.watch(gameProvider);
    final audio = ref.read(audioServiceProvider);
    _checkGameOver(gs);
    _syncWaitingSound(gs);

    final canRoll  = gs.canCurrentPlayerAct && !gs.diceRolled && !gs.gameOver;

    String rollLabel;
    Color  rollColor;
    if (gs.gameOver) {
      rollLabel = '🏆 ${kPlayerNames[gs.winner!]} Wins!';
      rollColor = Colors.green.shade700;
    } else if (gs.canCurrentPlayerAct && !gs.diceRolled) {
      rollLabel = '🎲 Roll Dice';
      rollColor = AppColors.violet;
    } else if (gs.canCurrentPlayerAct && gs.diceRolled) {
      rollLabel = '👆 Tap your token';
      rollColor = Colors.orange.shade700;
    } else {
      rollLabel = '⏳ ${kPlayerNames[gs.currentTurn]}\'s Turn';
      rollColor = Colors.blueGrey.shade700;
    }

    // FIX (turn-stuck-on-Red / wrong-name-in-strip bug): the player strip
    // used to loop `for (int i = 0; i < gs.numPlayers; i++)`, which
    // assumes seats are colors 0..numPlayers-1 in order. That's true for
    // local/vsBot (colors are always assigned that way), but online
    // colors are whatever each player actually picked (e.g. Blue=3 and
    // Green=1 with numPlayers=2) — looping 0,1 would show a chip for
    // color 0 (Red, unoccupied, falls back to the literal string "Red")
    // and a chip for color 1 (Green, a real player), producing exactly
    // the mismatched "Red" chip you saw next to a correctly-named
    // opponent. For online, iterate the real occupied colors instead;
    // local/vsBot keep the original 0..numPlayers-1 behaviour untouched.
    final seatColors = gs.mode == GameMode.online
        ? (gs.tokens.keys.toList()..sort())
        : List<int>.generate(gs.numPlayers, (i) => i);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  color: Colors.white,
                  onPressed: _goBack,
                ),
                Expanded(child: _StatusBar(gs: gs)),
                IconButton(
                  icon: Icon(audio.sfxEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded, size: 20),
                  color: Colors.white70,
                  onPressed: () =>
                      setState(() => audio.sfxEnabled = !audio.sfxEnabled),
                ),
                IconButton(
                  icon: Icon(audio.bgmEnabled
                      ? Icons.music_note_rounded
                      : Icons.music_off_rounded, size: 20),
                  color: Colors.white70,
                  onPressed: () {
                    setState(() => audio.bgmEnabled = !audio.bgmEnabled);
                    if (audio.bgmEnabled) audio.startBgm();
                    else audio.stopBgm();
                  },
                ),
                if (gs.mode == GameMode.online)
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        size: 20),
                    color: Colors.white70,
                    onPressed: () =>
                        setState(() => _showChat = !_showChat),
                  ),
              ]),
            ),

            // ── Player strip ──────────────────────────────────────────────
            Container(
              color: AppColors.bg,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // FIX: iterate seatColors (real occupied colors for
                  // online; 0..numPlayers-1 for local/vsBot) instead of
                  // a raw `for (int i = 0; i < gs.numPlayers; i++)`.
                  for (final c in seatColors)
                    PlayerChip(
                      index:    c,
                      name:     gs.playerNames[c] ?? kPlayerNames[c],
                      active:   c == gs.currentTurn && !gs.gameOver,
                      finished: gs.finishedPlayers.contains(c),
                      color:    kPlayerColors[c],
                    ),
                ],
              ),
            ),

            // ── Board ─────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: const BoardWidget(),
              ),
            ),

            // ── Two dice + Roll button ─────────────────────────────────────
            Container(
              color: AppColors.surface,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Always show BOTH dice
                  Row(children: [
                    DiceWidget(value: gs.dice1),
                    if (gs.twoDiceMode) ...[
                      const SizedBox(width: 10),
                      DiceWidget(value: gs.dice2),
                    ],
                    if (gs.diceRolled) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.violet.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.violet),
                        ),
                        child: Text(
                          '= ${gs.totalDice}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                    ],
                  ]),
                  RollButton(
                    label:     rollLabel,
                    enabled:   canRoll,
                    color:     rollColor,
                    onPressed: canRoll ? _roll : null,
                  ),
                ],
              ),
            ),

            // ── Emote bar ─────────────────────────────────────────────────
            Container(
              color: AppColors.bg,
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                itemCount: kEmotes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () =>
                      ref.read(gameProvider.notifier).sendChat(kEmotes[i]),
                  child: Container(
                    width: 36, height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(kEmotes[i],
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ),

            // ── Chat (online only) ─────────────────────────────────────────
            // NEW: freeTextAllowed passed through — decides whether
            // _ChatPanel renders a real text field or preset-phrase chips.
            if (gs.mode == GameMode.online && _showChat)
              _ChatPanel(
                chatCtrl: _chatCtrl,
                gs: gs,
                freeTextAllowed: _freeTextAllowed,
                blockedUids: _blockedUids,
                onBlocked: (uid) =>
                    setState(() => _blockedUids = {..._blockedUids, uid}),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Status bar ────────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  final GameState gs;
  const _StatusBar({required this.gs});

  @override
  Widget build(BuildContext context) {
    final ud = gs.userData;
    if (ud == null) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      StatChip(emoji: '🪙', value: '${ud.coins}'),
      const SizedBox(width: 6),
      StatChip(emoji: '📊', value: '${ud.elo}'),
    ]);
  }
}

// ── Chat panel ────────────────────────────────────────────────────────────────
// NEW: freeTextAllowed gates which input renders. Preset phrases are the
// same 8 phrases defined in widgets/chat_safety_widgets.dart
// (kPresetChatPhrases) — reused here directly rather than duplicating the
// list, so the restricted vocabulary stays defined in exactly one place.
class _ChatPanel extends ConsumerWidget {
  final TextEditingController chatCtrl;
  final GameState gs;
  final bool freeTextAllowed;
  final Set<String> blockedUids;
  final void Function(String blockedUid) onBlocked;
  const _ChatPanel({
    required this.chatCtrl,
    required this.gs,
    required this.freeTextAllowed,
    required this.blockedUids,
    required this.onBlocked,
  });

  void _send(WidgetRef ref, BuildContext context, String text) {
    if (text.trim().isEmpty) return;
    ref.read(gameProvider.notifier).sendChat(text.trim());
  }

  void _sendFreeText(WidgetRef ref, BuildContext context) {
    final text = chatCtrl.text.trim();
    if (text.isEmpty) return;

    // Blocked locally before it ever reaches the database — same check
    // used in widgets/chat_safety_widgets.dart's FreeTextChatBar.
    if (!ProfanityFilter.isAllowed(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Message blocked — please keep chat respectful and don\'t share contact info.'),
        ),
      );
      return;
    }

    _send(ref, context, text);
    chatCtrl.clear();
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    String targetUid,
    String targetName,
  ) async {
    final myUid = gs.userData!.uid;
    final idToken = gs.userData!.idToken!;

    if (action == 'block') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Block $targetName?'),
          content: const Text(
            'You won\'t see their messages anymore. They won\'t be notified.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final safety = ref.read(safetyServiceProvider);
      await safety.blockUser(myUid: myUid, idToken: idToken, blockedUid: targetUid);
      onBlocked(targetUid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$targetName blocked')),
        );
      }
    } else if (action == 'report') {
      await ReportUserDialog.show(
        context,
        myUid: myUid,
        idToken: idToken,
        targetUid: targetUid,
        targetName: targetName,
        roomId: gs.roomId ?? '',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = gs.userData?.uid;

    // Filter out anyone already blocked before rendering. Messages with
    // no senderUid (older rooms written before this field existed, or
    // local/vsBot) are never filtered — there's nothing to match against.
    final visibleMessages = gs.chatMessages
        .where((m) => m.senderUid == null || !blockedUids.contains(m.senderUid))
        .toList();

    return Container(
      color: AppColors.surface,
      height: 140,
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: visibleMessages.length,
            itemBuilder: (_, i) {
              final msg = visibleMessages[visibleMessages.length - 1 - i];
              final pi  = kPlayerNames.indexOf(msg.player).clamp(0, 3);
              // Only offer block/report for messages with a known sender
              // uid that isn't the current user themselves.
              final canModerate =
                  msg.senderUid != null && msg.senderUid != myUid;
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: kPlayerColors[pi],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(msg.player,
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(msg.msg,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                  ),
                  if (canModerate)
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert,
                          size: 14, color: Colors.white38),
                      onSelected: (action) => _handleMenuAction(
                          context, ref, action, msg.senderUid!, msg.player),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'block', child: Text('Block')),
                        PopupMenuItem(value: 'report', child: Text('Report')),
                      ],
                    ),
                ]),
              );
            },
          ),
        ),

        // NEW: gated input — preset chips for non-adult/unknown accounts,
        // real text field only once confirmed 18+.
        if (freeTextAllowed)
          Row(children: [
            Expanded(
              child: TextField(
                controller: chatCtrl,
                style:
                    const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText:    'Message…',
                  hintStyle:   const TextStyle(color: Colors.white30),
                  filled:      true,
                  fillColor:   AppColors.card,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _sendFreeText(ref, context),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.send_rounded, size: 18),
              color: AppColors.violetLit,
              onPressed: () => _sendFreeText(ref, context),
            ),
          ])
        else
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kPresetChatPhrases.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final phrase = kPresetChatPhrases[i];
                return ActionChip(
                  label: Text(phrase, style: const TextStyle(fontSize: 11)),
                  backgroundColor: AppColors.card,
                  onPressed: () => _send(ref, context, phrase),
                );
              },
            ),
          ),
      ]),
    );
  }
}
