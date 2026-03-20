import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monyx/features/map/models/map_pin.dart';
import 'package:monyx/features/map/models/map_state.dart';
import 'package:monyx/features/map/services/location_service.dart';

// ── Location stream provider ──────────────────────────────────────────────────

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final locationProvider = StreamProvider<LocationData>((ref) {
  final service = ref.watch(locationServiceProvider);
  return service.getPositionStream();
});

// ── Map state notifier ────────────────────────────────────────────────────────

class MapStateNotifier extends StateNotifier<MapState> {
  MapStateNotifier(this._locationService) : super(const MapState()) {
    _init();
  }

  final LocationService _locationService;
  StreamSubscription<LocationData>? _locationSub;

  void _init() {
    _locationSub = _locationService.getPositionStream().listen((data) {
      state = state.copyWith(
        userLatitude: data.latitude,
        userLongitude: data.longitude,
        userElevationMeters: data.altitudeMeters,
      );
    });
  }

  // ── Pin management ────────────────────────────────────────────────────────────

  void addPin(MapPin pin) {
    state = state.copyWith(pins: [...state.pins, pin]);
  }

  void removePin(String pinId) {
    final updated = state.pins.where((p) => p.id != pinId).toList();
    state = state.copyWith(
      pins: updated,
      clearSelectedPin: state.selectedPin?.id == pinId,
    );
  }

  void selectPin(MapPin? pin) {
    if (pin == null) {
      state = state.copyWith(clearSelectedPin: true);
    } else {
      state = state.copyWith(selectedPin: pin);
    }
  }

  void toggleLandOverlay() {
    state = state.copyWith(showLandOverlay: !state.showLandOverlay);
  }

  void setOfflineMode(bool offline) {
    state = state.copyWith(isOffline: offline);
  }

  /// Drop a pin at the current user location.
  void dropPinAtCurrentLocation({
    PinType type = PinType.waypoint,
    String? label,
    String? notes,
  }) {
    if (!state.hasLocation) return;
    final pin = MapPin(
      id: _generateId(),
      latitude: state.userLatitude!,
      longitude: state.userLongitude!,
      elevationMeters: state.userElevationMeters,
      type: type,
      label: label,
      notes: notes,
      createdAt: DateTime.now(),
    );
    addPin(pin);
  }

  /// Drop a pin at an arbitrary coordinate.
  void dropPinAt(
    double lat,
    double lon, {
    double? elevationMeters,
    PinType type = PinType.waypoint,
    String? label,
    String? notes,
  }) {
    final pin = MapPin(
      id: _generateId(),
      latitude: lat,
      longitude: lon,
      elevationMeters: elevationMeters,
      type: type,
      label: label,
      notes: notes,
      createdAt: DateTime.now(),
    );
    addPin(pin);
    selectPin(pin);
  }

  String _generateId() {
    final rng = Random.secure();
    return List.generate(
      8,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }
}

final mapStateProvider =
    StateNotifierProvider<MapStateNotifier, MapState>((ref) {
      final service = ref.watch(locationServiceProvider);
      return MapStateNotifier(service);
    });
