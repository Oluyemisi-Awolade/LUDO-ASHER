// lib/screens/login_screen.dart
//
// Adds a Date of Birth field to the "Create Account" flow so the
// app can default new accounts to restricted (preset-phrase-only)
// chat and only unlock free-text chat once SafetyService confirms
// the account is 18+. See services/safety_service.dart.
//
// Everything else is unchanged from the previous version.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../core/constants.dart';
import '../game/game_notifier.dart';
import '../game/game_state.dart';
import '../services/firebase_service.dart';
import '../services/safety_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'menu_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  DateTime? _birthdate; // only asked for on the Create Account path
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  Future<void> _auth(bool signup) async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      showSnack(context, 'Enter email and password', color: Colors.red.shade700);
      return;
    }
    if (signup && _birthdate == null) {
      showSnack(context, 'Please enter your date of birth', color: Colors.red.shade700);
      return;
    }
    setState(() => _loading = true);
    try {
      final fb  = ref.read(firebaseServiceProvider);
      final res = signup
          ? await fb.signUp(_emailCtrl.text.trim(), _passCtrl.text)
          : await fb.signIn(_emailCtrl.text.trim(), _passCtrl.text);

      if (res == null || res.containsKey('error')) {
        final msg = (res?['error'] as Map?)?['message'] ?? 'Auth failed';
        if (mounted) showSnack(context, msg.toString(), color: Colors.red.shade700);
        return;
      }

      final uid   = res['localId'] as String;
      final token = res['idToken'] as String;

      // Load or create user record
      var raw = await fb.getUser(uid, token);
      UserData ud;
      if (raw == null || !raw.containsKey('email')) {
        ud = UserData(
          uid: uid, email: _emailCtrl.text.trim(),
          displayName: _emailCtrl.text.split('@').first,
          idToken: token,
        );
        await fb.saveUser(ud);

        // New account: save birthdate so chat mode can be gated.
        // Defaults to restricted (preset-phrase) chat until this
        // implies 18+ — see SafetyService.isFreeTextAllowed.
        if (signup && _birthdate != null) {
          final safety = ref.read(safetyServiceProvider);
          await safety.saveBirthdate(
            uid: uid,
            idToken: token,
            birthdate: _birthdate!,
          );
        }
      } else {
        ud = UserData.fromJson(raw, uid, idToken: token);
      }

      // Persist offline
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(ud.toJson()));
      await prefs.setString('id_token', token);

      ref.read(gameProvider.notifier).setUser(ud);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MenuScreen()),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _offline() async {
    // Try loading saved session first
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('user_data');
      if (raw != null) {
        final map = jsonDecode(raw) as Map;
        final ud  = UserData.fromJson(map, map['uid'] as String? ?? 'offline');
        ref.read(gameProvider.notifier).setUser(ud);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MenuScreen()),
          );
          return;
        }
      }
    } catch (_) {}

    ref.read(gameProvider.notifier).setUser(UserData.offline());
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MenuScreen()),
      );
    }
  }

  // "Forgot password?" flow. Pre-fills whatever the user already typed
  // into the email field (if anything), lets them confirm/edit it, then
  // calls FirebaseService.sendPasswordReset. The confirmation message is
  // intentionally the same whether or not the email exists in the
  // system, so this can't be used to probe registered emails.
  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Reset password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your account email. We\'ll send a link to set a new password.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined, color: Colors.white38, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.violet),
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );

    if (email == null || email.isEmpty) return;

    setState(() => _loading = true);
    try {
      final fb = ref.read(firebaseServiceProvider);
      await fb.sendPasswordReset(email);
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    if (!mounted) return;
    showSnack(
      context,
      'If an account exists for that email, a reset link has been sent.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 52),
              Text('🎲', style: const TextStyle(fontSize: 72))
                  .animate().scale(delay: 100.ms, duration: 500.ms, curve: Curves.elasticOut),
              const SizedBox(height: 10),
              Text('Ludo Pro Max',
                  style: Theme.of(context).textTheme.displayMedium)
                  .animate().fadeIn(delay: 200.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0),
              Text('v$kAppVersion',
                  style: Theme.of(context).textTheme.labelSmall)
                  .animate().fadeIn(delay: 350.ms),
              const SizedBox(height: 40),

              // Email
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined, color: Colors.white38, size: 18),
                ),
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.15, end: 0),
              const SizedBox(height: 12),

              // Password
              TextField(
                controller: _passCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 18),
                ),
              ).animate().fadeIn(delay: 480.ms).slideY(begin: 0.15, end: 0),
              const SizedBox(height: 12),

              // Date of birth — only relevant for Create Account, but
              // shown always so returning users aren't confused by a
              // field that appears/disappears based on which button
              // they're about to tap. Tapping Log In simply ignores it.
              InkWell(
                onTap: _pickBirthdate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date of birth (required to create an account)',
                    prefixIcon: Icon(Icons.cake_outlined, color: Colors.white38, size: 18),
                  ),
                  child: Text(
                    _birthdate == null
                        ? 'Tap to select'
                        : '${_birthdate!.year}-${_birthdate!.month.toString().padLeft(2, '0')}-${_birthdate!.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: _birthdate == null ? Colors.white38 : Colors.white,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.15, end: 0),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    'Used to keep chat age-appropriate. Accounts under 18 '
                    'get preset-phrase chat only.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ),

              // Forgot password link, right-aligned under the password
              // field (standard placement for this pattern).
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _forgotPassword,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Forgot password?',
                      style: TextStyle(color: Colors.white54, fontSize: 12.5)),
                ),
              ).animate().fadeIn(delay: 520.ms),
              const SizedBox(height: 12),

              if (_loading) ...[
                const CircularProgressIndicator(color: AppColors.violet),
                const SizedBox(height: 20),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _auth(false),
                    icon: const Icon(Icons.login_rounded, size: 17),
                    label: const Text('Log In'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.violet,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ).animate().fadeIn(delay: 540.ms),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _auth(true),
                    icon: const Icon(Icons.person_add_rounded, size: 17),
                    label: const Text('Create Account'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3730A3),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ).animate().fadeIn(delay: 590.ms),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: _offline,
                  child: const Text('Play Offline',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ).animate().fadeIn(delay: 640.ms),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
