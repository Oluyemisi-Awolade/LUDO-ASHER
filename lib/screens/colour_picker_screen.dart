// lib/screens/colour_picker_screen.dart
// Used for BOTH offline and online play — player picks colour before game starts
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../game/game_notifier.dart';
import '../game/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';

class ColourPickerScreen extends ConsumerStatefulWidget {
  final GameMode   mode;
  final BotDifficulty? difficulty;
  final bool       twoDice;
  final int        numPlayers;
  final bool       goToLobby; // true = online, false = start game directly

  const ColourPickerScreen({
    super.key,
    required this.mode,
    this.difficulty,
    this.twoDice     = false,
    this.numPlayers  = 4,
    this.goToLobby   = false,
  });

  @override
  ConsumerState<ColourPickerScreen> createState() =>
      _ColourPickerScreenState();
}

class _ColourPickerScreenState extends ConsumerState<ColourPickerScreen> {
  int? _selected;

  static const _names  = ['Red', 'Green', 'Yellow', 'Blue'];
  static const _emojis = ['🔴', '🟢', '🟡', '🔵'];

  // FIX (local play colour bug): setupGame() in game_notifier.dart only
  // ever builds player slots 0..numPlayers-1 for local multiplayer
  // (`final n = mode == GameMode.vsBot ? 4 : numPlayers;`) — vsBot always
  // gets all 4 seats regardless of numPlayers, and online's colour
  // availability is decided server-side later in joinRoom/createRoom, not
  // here. So this screen was offering all 4 colours unconditionally, and
  // picking one outside 0..numPlayers-1 in a LOCAL game (e.g. Yellow in a
  // 2P game) got silently dropped: setupGame's `for (i in 0..<n)` loop
  // never reached that index, so no slot was ever named 'You' and that
  // colour's tokens were never created — the board just showed the two
  // colours that do exist under generic "Player…" labels. Restricting the
  // grid to the colours that will actually exist fixes it at the source
  // instead of letting an invalid pick be made at all.
  int get _maxColours =>
      widget.mode == GameMode.localMultiplayer
          ? widget.numPlayers.clamp(2, 4)
          : 4;

  void _proceed() {
    if (_selected == null) {
      showSnack(context, 'Pick a colour first!',
          color: Colors.orange.shade700);
      return;
    }

    if (widget.goToLobby) {
      // Online: store colour then go to lobby
      ref.read(gameProvider.notifier).setPlayerColor(
          _selected!, ref.read(gameProvider).userData?.displayName ?? 'Player');
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LobbyScreen()));
    } else {
      // Offline / VS Bot / Local: start game directly with chosen colour
      ref.read(gameProvider.notifier).setupGame(
        mode:        widget.mode,
        difficulty:  widget.difficulty ?? BotDifficulty.hard,
        twoDice:     widget.twoDice,
        numPlayers:  widget.numPlayers,
        playerColor: _selected!,
      );
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GameScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxColours = _maxColours;

    // LANDSCAPE TIDY: when the phone is rotated, the 2x2 grid used to
    // stretch across the whole wide screen, making huge tiles. Now the
    // content is centred and limited to 440 px wide, and the tiles are
    // shorter in landscape. Portrait phones are unaffected (a phone is
    // narrower than 440 px, and the tile shape stays 1.1 as before).
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Choose Your Colour',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Center(
                child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Pick your token colour.\nYou will play as this colour for the whole game.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.white60, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    // FIX (local play colour bug): tells the player why
                    // fewer than 4 tiles show up, instead of the colours
                    // just silently not being there.
                    if (maxColours < 4) ...[
                      const SizedBox(height: 8),
                      Text(
                        'This is a ${widget.numPlayers}-player local game, '
                        'so only ${maxColours == 2 ? "2 colours are" : "$maxColours colours are"} available.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white38),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 32),

                    // 2×2 colour grid — only as many tiles as can actually
                    // exist in this game (see _maxColours above).
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing:  16,
                      childAspectRatio: isLandscape ? 1.4 : 1.1,
                      children: List.generate(maxColours, (i) {
                        final sel = _selected == i;
                        final color = kPlayerColors[i];
                        return GestureDetector(
                          onTap: () => setState(() => _selected = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            decoration: BoxDecoration(
                              color: sel
                                  ? color.withOpacity(0.22)
                                  : AppColors.card,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: sel ? color : AppColors.border,
                                width: sel ? 2.5 : 1,
                              ),
                              boxShadow: sel
                                  ? [BoxShadow(
                                      color: color.withOpacity(0.4),
                                      blurRadius: 16)]
                                  : [],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width:  sel ? 70 : 56,
                                  height: sel ? 70 : 56,
                                  decoration: BoxDecoration(
                                    color:  color,
                                    shape:  BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white
                                          .withOpacity(sel ? 0.9 : 0.4),
                                      width: sel ? 3 : 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withOpacity(0.5),
                                        blurRadius:   10,
                                        spreadRadius: sel ? 3 : 0,
                                      )
                                    ],
                                  ),
                                  child: Icon(
                                    sel
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    color: Colors.white,
                                    size:  sel ? 28 : 22,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _emojis[i] + '  ' + _names[i],
                                  style: TextStyle(
                                    fontSize:   14,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: sel ? color : Colors.white70,
                                  ),
                                ),
                                if (sel) ...[
                                  const SizedBox(height: 4),
                                  Text('Selected ✓',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: color,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ],
                            ),
                          )
                              .animate(target: sel ? 1 : 0)
                              .scale(
                                  begin: const Offset(1, 1),
                                  end:   const Offset(1.03, 1.03),
                                  duration: 200.ms),
                        );
                      }),
                    ),

                    const SizedBox(height: 32),

                    // Proceed button
                    AnimatedOpacity(
                      opacity: _selected != null ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _selected != null ? _proceed : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selected != null
                                ? kPlayerColors[_selected!]
                                : AppColors.violet,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_selected != null) ...[
                                Text(_emojis[_selected!],
                                    style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 10),
                              ],
                              Text(widget.goToLobby
                                  ? 'Continue to Lobby'
                                  : 'Start Game'),
                              const SizedBox(width: 6),
                              const Icon(
                                  Icons.arrow_forward_ios_rounded, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
