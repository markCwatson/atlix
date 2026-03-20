import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:monyx/../core/theme/app_theme.dart';
import 'package:monyx/features/auth/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool _isSignUp = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authNotifierProvider.notifier);

    if (_isSignUp) {
      await notifier.signUp(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
        _displayNameCtrl.text.trim(),
      );
    } else {
      await notifier.signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
    }

    if (!mounted) return;
    final authState = ref.read(authNotifierProvider);
    authState.when(
      data: (user) {
        if (user != null) context.go('/map');
      },
      loading: () {},
      error: (e, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('AuthException: ', '')),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      },
    );
  }

  Future<void> _continueAsGuest() async {
    await ref.read(authNotifierProvider.notifier).continueAsGuest();
    if (mounted) context.go('/map');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Logo ────────────────────────────────────────────────────
                  Icon(
                    Icons.terrain,
                    size: 72,
                    color: AppTheme.primaryOrange,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'MONYX',
                    style: TextStyle(
                      color: AppTheme.primaryOrange,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hunt smarter. Plan farther.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // ── Display name (sign-up only) ──────────────────────────────
                  if (_isSignUp) ...[
                    TextFormField(
                      controller: _displayNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Enter your name'
                                  : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Email ───────────────────────────────────────────────────
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter email';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Password ────────────────────────────────────────────────
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed:
                            () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter password';
                      if (_isSignUp && v.length < 6) {
                        return 'At least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // ── Primary action ──────────────────────────────────────────
                  ElevatedButton(
                    onPressed: isLoading ? null : _submit,
                    child:
                        isLoading
                            ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                            : Text(_isSignUp ? 'Create Account' : 'Sign In'),
                  ),
                  const SizedBox(height: 12),

                  // ── Toggle sign-in / sign-up ────────────────────────────────
                  TextButton(
                    onPressed:
                        () => setState(() {
                          _isSignUp = !_isSignUp;
                          _formKey.currentState?.reset();
                        }),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : 'New here? Create account',
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),

                  // ── Guest ───────────────────────────────────────────────────
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : _continueAsGuest,
                    icon: const Icon(Icons.explore_outlined),
                    label: const Text('Continue as Guest'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: BorderSide(color: AppTheme.dividerColor),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
