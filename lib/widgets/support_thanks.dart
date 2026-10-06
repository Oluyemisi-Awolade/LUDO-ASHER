// lib/widgets/support_thanks.dart
//
// Shows a thank-you popup anywhere in the app when a support purchase
// completes, even if the support sheet was closed (delayed payments).
//
// Setup in main.dart:
//   final navigatorKey = GlobalKey<NavigatorState>();
//   ...
//   SupportPurchaseService.instance.start();
//   SupportThanks.init(navigatorKey);
//   ...
//   MaterialApp(navigatorKey: navigatorKey, ...)

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/support_purchase_service.dart';

const Color _kBg = Color(0xFF1E1409);
const Color _kOrange = Color(0xFFF57C00);
const Color _kMuted = Color(0xFFB8A58C);

class SupportThanks {
  SupportThanks._();

  static StreamSubscription<SupportEvent>? _sub;

  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _sub?.cancel();
    _sub = SupportPurchaseService.instance.events.listen((event) {
      if (event.type != SupportEventType.success) return;
      final context = navigatorKey.currentContext;
      if (context == null) return;

      final tier = kSupportTiers.firstWhere(
        (t) => t.id == event.productId,
        orElse: () => kSupportTiers.first,
      );

      showDialog<void>(
        context: context,
        builder: (_) => _ThanksDialog(tier: tier, quantity: event.quantity),
      );
    });
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

class _ThanksDialog extends StatelessWidget {
  final SupportTier tier;
  final int quantity;

  const _ThanksDialog({required this.tier, required this.quantity});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: _kOrange.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tier.emoji, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            const Text(
              'Thank you!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$quantity × ${tier.title} received. Your support keeps Ludo Asher free.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kMuted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
