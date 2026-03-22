import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/subscription_service.dart';

// ── States ──────────────────────────────────────────────────────────────

abstract class SubscriptionState extends Equatable {
  const SubscriptionState();
  @override
  List<Object?> get props => [];
}

class SubscriptionInitial extends SubscriptionState {
  const SubscriptionInitial();
}

/// Free tier — ads shown, single profile only.
class SubscriptionFree extends SubscriptionState {
  final ProductDetails? product; // null if store unavailable
  const SubscriptionFree({this.product});
  @override
  List<Object?> get props => [product];
}

/// Pro tier — no ads, unlimited profiles.
class SubscriptionPro extends SubscriptionState {
  const SubscriptionPro();
}

class SubscriptionError extends SubscriptionState {
  final String message;
  const SubscriptionError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ───────────────────────────────────────────────────────────────

class SubscriptionCubit extends Cubit<SubscriptionState> {
  final SubscriptionService _service;
  StreamSubscription<bool>? _sub;

  SubscriptionCubit(this._service) : super(const SubscriptionInitial());

  /// Call after SubscriptionService.init() completes.
  Future<void> load() async {
    // todo: uncomment this for a DEMO BUILD: forces Pro for all users
    // emit(const SubscriptionPro());
    // return;

    // todo: use this for normal build
    _sub = _service.statusStream.listen((isPro) {
      if (isPro) {
        emit(const SubscriptionPro());
      }
    });

    if (_service.isPro) {
      emit(const SubscriptionPro());
    } else {
      emit(SubscriptionFree(product: _service.proProduct));
    }
  }

  /// Kick off the purchase flow.
  Future<void> purchase() async {
    try {
      await _service.buy();
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  /// Restore previous purchases.
  Future<void> restore() async {
    try {
      await _service.restore();
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  bool get isPro => true; // DEMO BUILD: always Pro

  @override
  Future<void> close() {
    _sub?.cancel();
    _service.dispose();
    return super.close();
  }
}
