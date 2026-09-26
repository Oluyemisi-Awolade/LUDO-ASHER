// lib/widgets/chat_safety_widgets.dart
//
// UI pieces for the chat safety layer:
//   - PresetPhraseChatBar: locked-down chat input for non-adult accounts
//   - FreeTextChatBar: normal text input, only shown to 18+ accounts
//   - BlockUserButton: one-tap block on a player's name/avatar
//   - ReportUserDialog: report form with reason picker
//
// Drop these into your existing room/chat screen. They call into
// SafetyService (safety_service.dart) for the actual read/writes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/safety_service.dart';
import '../services/profanity_filter.dart';
import '../theme/app_theme.dart';

/// Preset phrases shown to accounts that are not confirmed 18+.
/// Keep this list short, positive, and free of anything that could
/// be repurposed as harassment (no phrases implying insults, even
/// jokingly).
const List<String> kPresetChatPhrases = [
  '🎲 Good luck!',
  '👍 Nice roll!',
  '😄 Good game!',
  '🙌 Well played!',
  '⏳ One sec...',
  '👋 Hi!',
  '😅 So close!',
  '🔁 Rematch?',
];

/// Chat bar for restricted (non-adult) accounts. Tapping a phrase
/// sends it immediately via [onSend] — no free-text field at all.
class PresetPhraseChatBar extends StatelessWidget {
  const PresetPhraseChatBar({super.key, required this.onSend});
  final void Function(String phrase) onSend;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: kPresetChatPhrases.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final phrase = kPresetChatPhrases[i];
          return ActionChip(
            label: Text(phrase, style: const TextStyle(fontSize: 13)),
            backgroundColor: AppColors.card,
            onPressed: () => onSend(phrase),
          );
        },
      ),
    );
  }
}

/// Normal free-text chat bar. Only render this widget for accounts
/// where SafetyService.isFreeTextAllowed(birthdate) returned true.
class FreeTextChatBar extends StatefulWidget {
  const FreeTextChatBar({super.key, required this.onSend});
  final void Function(String text) onSend;

  @override
  State<FreeTextChatBar> createState() => _FreeTextChatBarState();
}

class _FreeTextChatBarState extends State<FreeTextChatBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    // Blocked locally, before it ever reaches the database.
    if (!ProfanityFilter.isAllowed(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message blocked — please keep chat respectful and don\'t share contact info.'),
        ),
      );
      return;
    }

    widget.onSend(text);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Message...'),
            onSubmitted: (_) => _submit(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.send_rounded, color: AppColors.violet),
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// One-tap block button — put this on a player's avatar/name in the
/// room UI (e.g. long-press menu or an overflow icon next to them).
class BlockUserButton extends ConsumerWidget {
  const BlockUserButton({
    super.key,
    required this.myUid,
    required this.idToken,
    required this.targetUid,
    required this.targetName,
  });

  final String myUid;
  final String idToken;
  final String targetUid;
  final String targetName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.block, color: Colors.redAccent, size: 18),
      tooltip: 'Block $targetName',
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.card,
            title: Text('Block $targetName?'),
            content: const Text(
              'You won\'t see their messages or presence anymore. '
              'They won\'t be notified.',
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
        await safety.blockUser(
          myUid: myUid,
          idToken: idToken,
          blockedUid: targetUid,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$targetName blocked')),
          );
        }
      },
    );
  }
}

/// Report dialog — reason picker + optional note, writes to
/// /reports/{id} for manual review.
class ReportUserDialog extends ConsumerStatefulWidget {
  const ReportUserDialog({
    super.key,
    required this.myUid,
    required this.idToken,
    required this.targetUid,
    required this.targetName,
    required this.roomId,
    this.messageSnapshot,
  });

  final String myUid;
  final String idToken;
  final String targetUid;
  final String targetName;
  final String roomId;
  final String? messageSnapshot;

  static Future<void> show(
    BuildContext context, {
    required String myUid,
    required String idToken,
    required String targetUid,
    required String targetName,
    required String roomId,
    String? messageSnapshot,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ReportUserDialog(
        myUid: myUid,
        idToken: idToken,
        targetUid: targetUid,
        targetName: targetName,
        roomId: roomId,
        messageSnapshot: messageSnapshot,
      ),
    );
  }

  @override
  ConsumerState<ReportUserDialog> createState() => _ReportUserDialogState();
}

class _ReportUserDialogState extends ConsumerState<ReportUserDialog> {
  ReportReason _reason = ReportReason.harassment;
  bool _sending = false;

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      final safety = ref.read(safetyServiceProvider);
      await safety.reportUser(
        reporterUid: widget.myUid,
        idToken: widget.idToken,
        reportedUid: widget.targetUid,
        roomId: widget.roomId,
        reason: _reason,
        messageSnapshot: widget.messageSnapshot,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Thank you.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Report ${widget.targetName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in ReportReason.values)
            RadioListTile<ReportReason>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(r.label, style: const TextStyle(color: Colors.white)),
              value: r,
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v!),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _sending ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.violet),
          child: _sending
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}
