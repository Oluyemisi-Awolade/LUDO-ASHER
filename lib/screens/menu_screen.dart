// lib/screens/menu_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../game/game_notifier.dart';
import '../game/game_state.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'colour_picker_screen.dart';
import 'tournament_screen.dart';
import 'leaderboard_screen.dart';
import 'login_screen.dart';
import 'how_to_play_screen.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  void _goPickColour(BuildContext ctx, {
    required GameMode mode,
    BotDifficulty difficulty = BotDifficulty.hard,
    bool twoDice    = false,
    int  numPlayers = 4,
  }) {
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => ColourPickerScreen(
        mode:       mode,
        difficulty: difficulty,
        twoDice:    twoDice,
        numPlayers: numPlayers,
        goToLobby:  false,
      ),
    ));
  }

  // "Delete My Account" flow. Re-verifies the password via a
  // fresh signIn call (so we never rely on a possibly-stale idToken
  // for something irreversible), deletes the RTDB record, then
  // deletes the Auth credential itself, then clears local session.
  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
    UserData ud,
  ) async {
    final passCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your account, gameplay stats, '
              'and chat history. This cannot be undone.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passCtrl,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Confirm your password',
                prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (passCtrl.text.isEmpty) {
      if (context.mounted) {
        showSnack(context, 'Password required', color: Colors.red.shade700);
      }
      return;
    }

    final fb = ref.read(firebaseServiceProvider);

    // Re-authenticate to get a guaranteed-fresh idToken before
    // performing an irreversible delete.
    final res = await fb.signIn(ud.email, passCtrl.text);
    if (res == null || res.containsKey('error')) {
      if (context.mounted) {
        showSnack(context, 'Incorrect password', color: Colors.red.shade700);
      }
      return;
    }

    final freshToken = res['idToken'] as String;
    final uid = res['localId'] as String;

    final dataDeleted = await fb.deleteUserData(uid, freshToken);
    final authDeleted = await fb.deleteAuthAccount(freshToken);

    if (!dataDeleted || !authDeleted) {
      if (context.mounted) {
        showSnack(
          context,
          'Something went wrong deleting your account. Please try again '
          'or email oluyemisiitunuolu111@gmail.com.',
          color: Colors.red.shade700,
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    await prefs.remove('id_token');

    ref.read(gameProvider.notifier).clearUser();
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ud = ref.watch(gameProvider).userData;
    final isOnlineAccount = ud != null && ud.uid != 'offline';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Ludo Pro Max',
              // "How to Play" entry point, top-right of the header —
              // matches the existing AppHeader(actions: ...) pattern used
              // elsewhere in the app.
              actions: [
                IconButton(
                  icon: const Icon(Icons.help_outline_rounded, size: 20),
                  color: Colors.white70,
                  tooltip: 'How to Play',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const HowToPlayScreen()),
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Profile card ────────────────────────────────────────
                    _ProfileCard(ud: ud),
                    const SizedBox(height: 16),

                    // ── VS AI (single dice) ─────────────────────────────────
                    const LabelDivider('VS AI'),
                    const SizedBox(height: 8),
                    _Btn(
                      label: 'Easy Bot  😊',
                      color: Colors.green.shade700,
                      onTap: () => _goPickColour(context,
                          mode: GameMode.vsBot,
                          difficulty: BotDifficulty.easy),
                    ),
                    const SizedBox(height: 8),
                    _Btn(
                      label: 'Hard Bot  😤',
                      color: Colors.orange.shade700,
                      onTap: () => _goPickColour(context,
                          mode: GameMode.vsBot,
                          difficulty: BotDifficulty.hard),
                    ),
                    const SizedBox(height: 8),
                    _Btn(
                      label: 'Hardest Bot  💀',
                      color: Colors.red.shade700,
                      onTap: () => _goPickColour(context,
                          mode: GameMode.vsBot,
                          difficulty: BotDifficulty.hardest),
                    ),
                    const SizedBox(height: 8),
                    _Btn(
                      label: '2-Dice vs Bot  🎲🎲',
                      color: Colors.deepPurple.shade600,
                      onTap: () => _goPickColour(context,
                          mode: GameMode.vsBot,
                          difficulty: BotDifficulty.hard,
                          twoDice: true),
                    ),

                    // ── Local Play ──────────────────────────────────────────
                    const SizedBox(height: 16),
                    const LabelDivider('LOCAL PLAY'),
                    const SizedBox(height: 8),
                    Row(children: [
                      _SmallBtn(
                        label: '2P',
                        color: Colors.blue.shade700,
                        onTap: () => _goPickColour(context,
                            mode: GameMode.localMultiplayer,
                            numPlayers: 2),
                      ),
                      const SizedBox(width: 8),
                      _SmallBtn(
                        label: '3P',
                        color: Colors.teal.shade700,
                        onTap: () => _goPickColour(context,
                            mode: GameMode.localMultiplayer,
                            numPlayers: 3),
                      ),
                      const SizedBox(width: 8),
                      _SmallBtn(
                        label: '4P',
                        color: Colors.indigo.shade600,
                        onTap: () => _goPickColour(context,
                            mode: GameMode.localMultiplayer,
                            numPlayers: 4),
                      ),
                    ]),

                    // ── Online ──────────────────────────────────────────────
                    const SizedBox(height: 16),
                    const LabelDivider('ONLINE'),
                    const SizedBox(height: 8),
                    _Btn(
                      label: 'Online Multiplayer  🌍',
                      icon:  Icons.wifi_rounded,
                      color: Colors.cyan.shade700,
                      onTap: () {
                        if (ud == null || ud.uid == 'offline') {
                          showSnack(context,
                              'Log in to play online',
                              color: Colors.red.shade700);
                          return;
                        }
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ColourPickerScreen(
                            mode:      GameMode.online,
                            goToLobby: true,
                          ),
                        ));
                      },
                    ),
                    const SizedBox(height: 8),
                    _Btn(
                      label: 'Tournaments  🏆',
                      icon:  Icons.emoji_events_rounded,
                      color: Colors.amber.shade700,
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const TournamentScreen())),
                    ),
                    const SizedBox(height: 8),
                    _Btn(
                      label: 'Leaderboard  📊',
                      icon:  Icons.leaderboard_rounded,
                      color: Colors.pink.shade700,
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const LeaderboardScreen())),
                    ),

                    const SizedBox(height: 20),
                    SupportCard(
                      onDonate: () async {
                        final url = Uri.parse(kFlutterwaveUrl);
                        if (await canLaunchUrl(url)) {
                          launchUrl(url,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        ref.read(gameProvider.notifier).clearUser();
                        Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()));
                      },
                      child: const Text('Log Out',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 13)),
                    ),

                    // Only shown for real (non-offline) accounts —
                    // matches Play Console's in-app account deletion
                    // requirement.
                    if (isOnlineAccount) ...[
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => _confirmDeleteAccount(context, ref, ud),
                        child: const Text('Delete My Account',
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 12.5)),
                      ),
                    ],

                    // Privacy Policy / Terms of Service links — shown to
                    // everyone regardless of login state, since Play
                    // requires the privacy policy reachable at all times.
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse(
                                'https://oluyemisi-awolade.github.io/LUDO-PRO-MAX/privacy-policy.html'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('Privacy Policy',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ),
                        const Text('·',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 11)),
                        TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse(
                                'https://oluyemisi-awolade.github.io/LUDO-PRO-MAX/terms-of-service.html'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('Terms of Service',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final UserData? ud;
  const _ProfileCard({this.ud});

  @override
  Widget build(BuildContext context) {
    final name = ud?.displayName ?? 'Player';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.violet,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'P',
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                StatChip(emoji: '🪙', value: '${ud?.coins ?? 0}'),
                StatChip(emoji: '🏆', value: '${ud?.wins ?? 0}W'),
                StatChip(
                    emoji: '📊',
                    value: '${ud?.elo ?? kDefaultElo} ELO'),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Btn extends StatelessWidget {
  final String    label;
  final Color     color;
  final VoidCallback onTap;
  final IconData? icon;

  const _Btn({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.centerLeft,
            textStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 17),
                const SizedBox(width: 8),
              ],
              Text(label),
            ]),
          ),
        ),
      );
}

class _SmallBtn extends StatelessWidget {
  final String    label;
  final Color     color;
  final VoidCallback onTap;

  const _SmallBtn({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700),
          ),
          child: Text(label),
        ),
      );
}
