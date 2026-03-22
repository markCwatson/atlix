import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Manages subscription state via App Store / Google Play.
///
/// Product ID — register this exact string in App Store Connect and
/// Google Play Console as an auto-renewable subscription.
const String kProSubscriptionId = 'monyx_pro_monthly_2';

class SubscriptionService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Whether the store is available on this device.
  bool storeAvailable = false;

  /// The subscription product details (price, title, etc.).
  ProductDetails? proProduct;

  /// Stream controller that emits `true` when the user has an active sub.
  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  bool _isPro = false;
  bool get isPro => _isPro;

  /// Call once at app start.
  Future<void> init() async {
    storeAvailable = await _iap.isAvailable();
    //debugPrint('[IAP] Store available: $storeAvailable');
    if (!storeAvailable) return;

    // Listen for purchase updates BEFORE querying products
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (error) {
        debugPrint('[IAP] Purchase stream error: $error');
      },
    );

    // Load product details
    final response = await _iap.queryProductDetails({kProSubscriptionId});
    // debugPrint(
    //   '[IAP] Product query: found=${response.productDetails.length}, '
    //   'notFound=${response.notFoundIDs}, error=${response.error?.message}',
    // );
    if (response.productDetails.isNotEmpty) {
      proProduct = response.productDetails.first;
      debugPrint(
        '[IAP] Product loaded: ${proProduct!.id} — ${proProduct!.price}',
      );
    }
  }

  /// Initiate a purchase flow.
  Future<bool> buy() async {
    if (proProduct == null) {
      debugPrint(
        '[IAP] buy() called but proProduct is null — store may be unavailable',
      );
      return false;
    }
    //debugPrint('[IAP] Starting purchase for ${proProduct!.id}');
    final param = PurchaseParam(productDetails: proProduct!);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Restore previous purchases (e.g. after reinstall).
  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      debugPrint(
        '[IAP] Purchase update: ${purchase.productID} '
        'status=${purchase.status} error=${purchase.error?.message}',
      );

      if (purchase.productID == kProSubscriptionId) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          _isPro = true;
          _statusController.add(true);
          debugPrint('[IAP] ✓ Pro subscription active');
        }
      }

      // Complete pending purchases (required by the store APIs).
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _statusController.close();
  }
}
