import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monyx/features/profiles/models/rifle_profile.dart';

// ── Profiles list notifier ────────────────────────────────────────────────────

class RifleProfilesNotifier extends StateNotifier<List<RifleProfile>> {
  RifleProfilesNotifier() : super([kDefaultRifleProfile]);

  void addProfile(RifleProfile profile) {
    state = [...state, profile];
  }

  void updateProfile(RifleProfile updated) {
    state = [
      for (final p in state)
        if (p.id == updated.id) updated else p,
    ];
  }

  void deleteProfile(String id) {
    if (state.length <= 1) return; // keep at least one profile
    state = state.where((p) => p.id != id).toList();
  }

  RifleProfile createBlank() => RifleProfile(
    id: _generateId(),
    name: 'New Profile',
    caliber: '',
    barrelLengthInches: 24.0,
    twistRateInchesPerTwist: 10.0,
    zeroDistanceYards: 100.0,
    sightHeightInches: 1.5,
    opticUnit: OpticUnit.moa,
    clickValueMoa: 0.25,
    bulletProfile: const BulletProfile(
      bulletName: '',
      bulletWeightGrains: 168.0,
      muzzleVelocityFps: 2650.0,
      ballisticCoefficientG1: 0.447,
      bulletDiameterInches: 0.308,
    ),
    createdAt: DateTime.now(),
  );

  String _generateId() {
    final rng = Random.secure();
    return List.generate(
      8,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

final rifleProfilesProvider =
    StateNotifierProvider<RifleProfilesNotifier, List<RifleProfile>>(
      (ref) => RifleProfilesNotifier(),
    );

// ── Active profile ────────────────────────────────────────────────────────────

final activeRifleProfileProvider = StateProvider<RifleProfile?>((ref) {
  // Default to the first profile in the list.
  final profiles = ref.watch(rifleProfilesProvider);
  return profiles.isNotEmpty ? profiles.first : null;
});
