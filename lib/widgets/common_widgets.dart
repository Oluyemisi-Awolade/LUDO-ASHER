// lib/widgets/common_widgets.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'support_sheet.dart';

// ── App header bar ────────────────────────────────────────────────────────────
class AppHeader extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  const AppHeader({super.key, required this.title, this.actions, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      child: Row(children: [
        if (onBack != null)
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: Colors.white,
            onPressed: onBack,
          ),
        const SizedBox(width: 4),
        const Text('🎲', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: Theme.of(context).textTheme.headlineMedium),
        ),
        if (actions != null) ...actions!,
      ]),
    );
  }
}

// ── Full-width primary button ─────────────────────────────────────────────────
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double? width;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
    this.width = 300,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon, size: 17) : const SizedBox.shrink(),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? AppColors.violet,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Section divider with label ────────────────────────────────────────────────
class LabelDivider extends StatelessWidget {
  final String label;
  const LabelDivider(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        const Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white38, letterSpacing: 0.8)),
        ),
        const Expanded(child: Divider(color: AppColors.border)),
      ]),
    );
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────
class StatChip extends StatelessWidget {
  final String emoji;
  final String value;

  const StatChip({super.key, required this.emoji, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ]),
    );
  }
}

// ── Support / donate card ─────────────────────────────────────────────────────
// Opens the in-app purchase sheet (Google Play Billing) by default.
// [onDonate] can override that, but is normally left null.
class SupportCard extends StatelessWidget {
  final VoidCallback? onDonate;
  const SupportCard({super.key, this.onDonate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2D1F0A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.volunteer_activism,
                color: Colors.orange, size: 15),
            const SizedBox(width: 6),
            Text('Support the Developer',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: Colors.white)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Ludo Asher is free — buy the dev a coffee ☕',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onDonate ?? () => showSupportSheet(context),
              icon: const Icon(Icons.favorite_rounded, size: 15),
              label: const Text('☕  Buy a Coffee'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Player strip chip ─────────────────────────────────────────────────────────
class PlayerChip extends StatelessWidget {
  final int    index;
  final String name;
  final bool   active;
  final bool   finished;
  final Color  color;

  const PlayerChip({
    super.key,
    required this.index,
    required this.name,
    required this.active,
    required this.finished,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.25) : AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? color : AppColors.border,
          width: active ? 1.8 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(height: 3),
          Text(
            name.length > 6 ? '${name.substring(0, 6)}…' : name,
            style: TextStyle(
              fontSize: 9,
              color: active ? Colors.white : Colors.white54,
              fontWeight:
                  active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          Text(
            finished ? '✅' : (active ? '🎲' : ''),
            style: const TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }
}

// ── Snackbar helper ───────────────────────────────────────────────────────────
void showSnack(BuildContext context, String msg, {Color? color}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: color ?? AppColors.violet,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(milliseconds: 2200),
    ),
  );
}
