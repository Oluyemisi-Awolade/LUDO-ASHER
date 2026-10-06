// lib/services/support_purchase_service.dart
//
// Handles the "Support the Developer" in-app purchases for Ludo Pro Max.
// Three consumable products, each with multi-quantity checkout enabled in
// Play Console. Google's checkout sheet lets the buyer pick the quantity;
// this service reads the quantity back from the completed purchase.
//
// pubspec.yaml needs:   in_app_purchase: ^3.2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// One support tier. [id] must match the Product ID in Play Console.
class SupportTier {
  final String id;
  final String title;
  final String emoji;
  final String fallbackPrice;

  const SupportTier({
    required this.id,
    required this.title,
    required this.emoji,
    required this.fallbackPrice,
  });
}

const List<SupportTier> kSupportTiers = [
  SupportTier(
    id: 'support_coffee',
    title: 'Coffee',
    emoji: '☕',
    fallbackPrice: '\$0.99',
  ),
  SupportTier(
    id: 'support_coffee_latte',
    title: 'Coffee and Latte',
    emoji: '☕🥛',
    fallbackPrice: '\$4.99',
  ),
  SupportTier(
    id: 'support_coffee_biscuits',
    title: 'Coffee and Biscuits',
    emoji: '☕🍪',
    fallbackPrice: '\$6.00',
  ),
];

enum SupportEventType { success, pending, canceled, failed }

class SupportEvent {
  final SupportEventType type;
  final String? productId;
  final int quantity;
  final String? message;

  const SupportEvent({
    required this.type,
    this.productId,
    this.quantity = 1,
    this.message,
  });
}

class SupportPurchaseService {
  SupportPurchaseService._();
  static final SupportPurchaseService instance = SupportPurchaseService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final StreamController<SupportEvent> _events =
      StreamController<SupportEvent>.broadcast();

  /// Loaded product details, keyed by product ID.
  final Map<String, ProductDetails> products = {};

  /// Purchase IDs already announced, so one purchase never thanks twice.
  final Set<String> _announced = {};

  bool _started = false;

  Stream<SupportEvent> get events => _events.stream;

  /// Tiers that Google Play actually returned.
  List<SupportTier> get availableTiers =>
      kSupportTiers.where((t) => products.containsKey(t.id)).toList();

  /// Call once in main(), before runApp, so purchases that finish while the
  /// app is closed or the sheet is dismissed are still processed.
  void start() {
    if (_started) return;
    _started = true;
    _subscription = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object error) {
        debugPrint('Support purchase stream error: $error');
        _events.add(const SupportEvent(
          type: SupportEventType.failed,
          message: 'Something went wrong with the purchase.',
        ));
      },
    );
  }

  Future<bool> isAvailable() => _iap.isAvailable();

  /// Loads localized product details from Google Play.
  /// Returns true when at least one tier was found.
  Future<bool> loadProducts() async {
    products.clear();
    try {
      final response = await _iap
          .queryProductDetails(kSupportTiers.map((t) => t.id).toSet());
      for (final p in response.productDetails) {
        products[p.id] = p;
      }
      if (response.error != null) {
        debugPrint('Support product query error: ${response.error}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('Support products not found: ${response.notFoundIDs}');
      }
    } catch (e) {
      debugPrint('Support product query failed: $e');
    }
    return products.isNotEmpty;
  }

  /// Opens Google's checkout for the tier. The buyer picks the quantity there.
  /// Returns false if the checkout could not be started.
  Future<bool> buy(String productId) async {
    final product = products[productId];
    if (product == null) return false;
    try {
      // Consumable: the plugin consumes the purchase after it completes, so
      // the same coffee can be bought again.
      return await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (e) {
      debugPrint('Support buy failed: $e');
      return false;
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _events.add(SupportEvent(
            type: SupportEventType.pending,
            productId: purchase.productID,
          ));
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final id = purchase.purchaseID;
          if (id == null || _announced.add(id)) {
            _events.add(SupportEvent(
              type: SupportEventType.success,
              productId: purchase.productID,
              quantity: _quantityOf(purchase),
            ));
          }
          break;
        case PurchaseStatus.canceled:
          _events.add(const SupportEvent(type: SupportEventType.canceled));
          break;
        case PurchaseStatus.error:
          _events.add(SupportEvent(
            type: SupportEventType.failed,
            message: purchase.error?.message,
          ));
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  /// Google includes a "quantity" field in the purchase JSON when the buyer
  /// chose more than one. Defaults to 1 if it is missing.
  int _quantityOf(PurchaseDetails purchase) {
    try {
      final data = jsonDecode(purchase.verificationData.localVerificationData);
      if (data is Map) {
        final q = data['quantity'];
        if (q is int && q > 0) return q;
        if (q is String) {
          final parsed = int.tryParse(q);
          if (parsed != null && parsed > 0) return parsed;
        }
      }
    } catch (_) {
      // Fall through to the default.
    }
    return 1;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
