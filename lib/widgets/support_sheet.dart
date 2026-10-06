// lib/widgets/support_sheet.dart
//
// Bottom sheet opened by the existing "Buy a Coffee" button.
// Shows the tiers Google Play returned; tapping one opens Google's checkout,
// where the buyer picks how many coffees they want.
// The thank-you popup is shown app-wide by SupportThanks (support_thanks.dart).

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/support_purchase_service.dart';

const Color _kSheetBg = Color(0xFF1E1409);
const Color _kOrange = Color(0xFFF57C00);
const Color _kCardBg = Color(0xFF2B1D0E);
const Color _kMuted = Color(0xFFB8A58C);

/// Call this from the Buy a Coffee button's onPressed.
Future<void> showSupportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _kSheetBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _SupportSheet(),
  );
}

class _SupportSheet extends StatefulWidget {
  const _SupportSheet();

  @override
  State<_SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<_SupportSheet> {
  final SupportPurchaseService _service = SupportPurchaseService.instance;
  StreamSubscription<SupportEvent>? _sub;

  bool _loading = true;
  bool _available = false;
  String? _busyId;
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service.start();
    _sub = _service.events.listen(_onEvent);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final storeOk = await _service.isAvailable();
    final loaded = storeOk ? await _service.loadProducts() : false;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _available = storeOk && loaded;
    });
  }

  void _onEvent(SupportEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case SupportEventType.success:
        // The app-wide popup announces the thanks.
        setState(() {
          _busyId = null;
          _error = null;
          _notice = null;
        });
        break;
      case SupportEventType.pending:
        // Unlock the buttons; the popup appears when payment completes.
        setState(() {
          _busyId = null;
          _error = null;
          _notice = 'Payment pending. We will thank you as soon as it completes.';
        });
        break;
      case SupportEventType.canceled:
        setState(() => _busyId = null);
        break;
      case SupportEventType.failed:
        setState(() {
          _busyId = null;
          _notice = null;
          _error = event.message ?? 'The purchase did not go through.';
        });
        break;
    }
  }

  Future<void> _buy(SupportTier tier) async {
    setState(() {
      _busyId = tier.id;
      _notice = null;
      _error = null;
    });
    final started = await _service.buy(tier.id);
    if (!started && mounted) {
      setState(() {
        _busyId = null;
        _error = 'Could not open checkout. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _kMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Support the Developer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ludo Asher is free. Pick a treat, then choose how many in the next step.',
                style: TextStyle(color: _kMuted, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (_notice != null)
                _banner(_notice!, const Color(0xFFFFB74D)),
              if (_error != null)
                _banner(_error!, const Color(0xFFE57373)),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: _kOrange),
                  ),
                )
              else if (!_available)
                _unavailable()
              else
                ..._service.availableTiers.map(_tierCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 14)),
    );
  }

  Widget _unavailable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Support options are not available right now. Check your connection and try again.',
          style: TextStyle(color: _kMuted, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _load,
          style: OutlinedButton.styleFrom(
            foregroundColor: _kOrange,
            side: const BorderSide(color: _kOrange),
          ),
          child: const Text('Try again'),
        ),
      ],
    );
  }

  Widget _tierCard(SupportTier tier) {
    final product = _service.products[tier.id];
    final price = product?.price ?? tier.fallbackPrice;
    final busy = _busyId == tier.id;
    final disabled = _busyId != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kCardBg,
        border: Border.all(color: _kOrange.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: disabled ? null : () => _buy(tier),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(tier.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tier.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$price each',
                      style: const TextStyle(color: _kMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                height: 40,
                child: ElevatedButton(
                  onPressed: disabled ? null : () => _buy(tier),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _kOrange.withValues(alpha: 0.4),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Buy'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
