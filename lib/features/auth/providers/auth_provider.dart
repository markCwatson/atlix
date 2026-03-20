import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monyx/features/auth/models/user_model.dart';
import 'package:monyx/features/auth/services/auth_service.dart';

// ── Service provider ──────────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService();
  ref.onDispose(service.dispose);
  return service;
});

// ── Auth state stream ─────────────────────────────────────────────────────────

/// Watches the auth state stream.  Yields [AsyncLoading] until the service
/// initialises, then [AsyncData<UserModel?>] where null means signed-out.
final authStateProvider = StreamProvider<UserModel?>((ref) async* {
  final service = ref.watch(authServiceProvider);
  await service.initialize();
  yield* service.authStateChanges;
});

// ── Current user (nullable) ───────────────────────────────────────────────────

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

// ── Auth notifier for actions ─────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  AuthNotifier(this._authService) : super(const AsyncValue.loading());

  final AuthService _authService;

  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _authService.signInWithEmail(email, password),
    );
  }

  Future<void> signUp(
    String email,
    String password,
    String displayName,
  ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _authService.signUpWithEmail(email, password, displayName),
    );
  }

  Future<void> continueAsGuest() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _authService.continueAsGuest());
  }

  Future<void> signOut() async {
    await _authService.signOut();
    state = const AsyncValue.data(null);
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>((ref) {
      final service = ref.watch(authServiceProvider);
      return AuthNotifier(service);
    });
