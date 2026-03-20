import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:monyx/features/auth/models/user_model.dart';

/// Key names used in secure storage.
class _StorageKeys {
  static const String currentUser = 'monyx_current_user';
  static const String accountsPrefix = 'monyx_account_';
}

/// Local mock authentication service backed by [FlutterSecureStorage].
///
/// No network calls are made – accounts are stored encrypted on-device.
/// This is the MVP implementation; swap [signInWithEmail] etc. with real
/// backend calls once a backend exists.
class AuthService {
  AuthService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final _authController = StreamController<UserModel?>.broadcast();

  UserModel? _currentUser;

  UserModel? get currentUser => _currentUser;

  Stream<UserModel?> get authStateChanges => _authController.stream;

  // ── Initialise ───────────────────────────────────────────────────────────────

  /// Load persisted session on startup.
  Future<void> initialize() async {
    final json = await _storage.read(key: _StorageKeys.currentUser);
    if (json != null) {
      _currentUser = UserModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
      _authController.add(_currentUser);
    } else {
      _authController.add(null);
    }
  }

  // ── Sign in ───────────────────────────────────────────────────────────────────

  /// Returns the [UserModel] on success, or throws [AuthException] on failure.
  Future<UserModel> signInWithEmail(String email, String password) async {
    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 400));

    final accountJson = await _storage.read(
      key: '${_StorageKeys.accountsPrefix}${email.toLowerCase()}',
    );
    if (accountJson == null) throw AuthException('No account found for $email');

    final data = jsonDecode(accountJson) as Map<String, dynamic>;
    final storedHash = data['passwordHash'] as String;

    if (!_verifyPassword(password, storedHash)) {
      throw AuthException('Incorrect password');
    }

    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    await _persistSession(user);
    return user;
  }

  // ── Sign up ───────────────────────────────────────────────────────────────────

  Future<UserModel> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));

    final key = '${_StorageKeys.accountsPrefix}${email.toLowerCase()}';
    final existing = await _storage.read(key: key);
    if (existing != null) throw AuthException('Email already registered');

    final user = UserModel(
      id: _generateId(),
      email: email.toLowerCase(),
      displayName: displayName,
      createdAt: DateTime.now(),
    );

    final accountData = jsonEncode({
      'user': user.toJson(),
      'passwordHash': _hashPassword(password),
    });
    await _storage.write(key: key, value: accountData);
    await _persistSession(user);
    return user;
  }

  // ── Guest ─────────────────────────────────────────────────────────────────────

  Future<UserModel> continueAsGuest() async {
    final user = UserModel(
      id: 'guest_${_generateId()}',
      email: 'guest@monyx.local',
      displayName: 'Guest',
      createdAt: DateTime.now(),
    );
    await _persistSession(user);
    return user;
  }

  // ── Sign out ──────────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _storage.delete(key: _StorageKeys.currentUser);
    _currentUser = null;
    _authController.add(null);
  }

  // ── Internal helpers ──────────────────────────────────────────────────────────

  Future<void> _persistSession(UserModel user) async {
    _currentUser = user;
    await _storage.write(
      key: _StorageKeys.currentUser,
      value: jsonEncode(user.toJson()),
    );
    _authController.add(user);
  }

  /// Naïve deterministic hash – good enough for a local mock.
  /// Replace with bcrypt / argon2 before any real deployment.
  String _hashPassword(String password) {
    final salt = _generateId();
    // XOR-based scramble purely for obfuscation; not production-grade.
    final combined = '$salt:$password';
    final bytes = utf8.encode(combined);
    final hash = bytes.fold<int>(0, (acc, b) => acc ^ b);
    return '$salt:${hash.toRadixString(16)}';
  }

  bool _verifyPassword(String password, String storedHash) {
    final parts = storedHash.split(':');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final expected = parts[1];
    final combined = '$salt:$password';
    final bytes = utf8.encode(combined);
    final hash = bytes.fold<int>(0, (acc, b) => acc ^ b);
    return hash.toRadixString(16) == expected;
  }

  String _generateId() {
    final rng = Random.secure();
    return List.generate(12, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void dispose() {
    _authController.close();
  }
}

/// Thrown when authentication fails.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => 'AuthException: $message';
}
