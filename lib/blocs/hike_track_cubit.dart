import 'dart:async';
import 'dart:io' show Platform;

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:uuid/uuid.dart';

import '../ballistics/conversions.dart';
import '../models/hike_track.dart';
import '../services/hike_track_service.dart';

// ── States ──────────────────────────────────────────────────────────────

abstract class HikeTrackState extends Equatable {
  const HikeTrackState();
  @override
  List<Object?> get props => [];
}

class HikeTrackIdle extends HikeTrackState {
  const HikeTrackIdle();
}

class HikeTrackRecording extends HikeTrackState {
  final List<HikePoint> points;
  final double distanceMeters;
  final int activeDurationSeconds;
  final double elevGainMeters;
  final double elevLossMeters;

  const HikeTrackRecording({
    required this.points,
    required this.distanceMeters,
    required this.activeDurationSeconds,
    required this.elevGainMeters,
    required this.elevLossMeters,
  });

  @override
  List<Object?> get props => [
    points.length,
    distanceMeters,
    activeDurationSeconds,
    elevGainMeters,
    elevLossMeters,
  ];
}

class HikeTrackPaused extends HikeTrackState {
  final List<HikePoint> points;
  final double distanceMeters;
  final int activeDurationSeconds;
  final double elevGainMeters;
  final double elevLossMeters;

  const HikeTrackPaused({
    required this.points,
    required this.distanceMeters,
    required this.activeDurationSeconds,
    required this.elevGainMeters,
    required this.elevLossMeters,
  });

  @override
  List<Object?> get props => [
    points.length,
    distanceMeters,
    activeDurationSeconds,
    elevGainMeters,
    elevLossMeters,
  ];
}

class HikeTrackStopped extends HikeTrackState {
  final HikeTrack track;
  const HikeTrackStopped(this.track);
  @override
  List<Object?> get props => [track];
}

class HikeTrackViewing extends HikeTrackState {
  final HikeTrack track;
  const HikeTrackViewing(this.track);
  @override
  List<Object?> get props => [track];
}

class HikeTrackError extends HikeTrackState {
  final String message;
  const HikeTrackError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ───────────────────────────────────────────────────────────────

class HikeTrackCubit extends Cubit<HikeTrackState> {
  final HikeTrackService _service;
  static const _uuid = Uuid();

  /// Minimum distance in meters between consecutive saved points.
  static const _minDistanceMeters = 2.0;

  /// Dead-band for elevation filtering — ignore altitude changes smaller
  /// than this to reduce GPS altitude noise.
  static const _elevDeadBandMeters = 2.0;

  // ── Recording state ─────────────────────────────────────────────────

  StreamSubscription<Position>? _positionSub;
  final List<HikePoint> _points = [];
  double _distanceMeters = 0;
  double _elevGainMeters = 0;
  double _elevLossMeters = 0;

  /// Wall-clock time when the current active segment started.
  DateTime? _segmentStart;

  /// Accumulated active seconds from completed (paused) segments.
  int _accumulatedSeconds = 0;

  /// Overall hike start time.
  DateTime? _hikeStartTime;

  /// Timer that fires every second to update the displayed duration.
  Timer? _durationTimer;

  HikeTrackCubit({required HikeTrackService service})
    : _service = service,
      super(const HikeTrackIdle());

  // ── Public API ──────────────────────────────────────────────────────

  /// Start recording a hike. Requests "always" location permission on first
  /// call, then begins a background-capable GPS stream.
  Future<void> start() async {
    try {
      // Request "always" permission for background tracking
      final status = await perm.Permission.locationAlways.request();
      if (!status.isGranted && !status.isLimited) {
        // Fall back to "when in use" — background may not work but
        // foreground tracking will still function.
        debugPrint('[HikeTrackCubit] locationAlways not granted: $status');
      }

      _points.clear();
      _distanceMeters = 0;
      _elevGainMeters = 0;
      _elevLossMeters = 0;
      _accumulatedSeconds = 0;
      _hikeStartTime = DateTime.now();
      _segmentStart = DateTime.now();

      await _subscribeToPosition();
      _startDurationTimer();

      _emitRecording();
    } catch (e) {
      emit(HikeTrackError('Failed to start tracking: $e'));
    }
  }

  /// Pause recording — stops the GPS stream and freezes the timer.
  void pause() {
    _positionSub?.cancel();
    _positionSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;

    // Freeze the segment duration
    if (_segmentStart != null) {
      _accumulatedSeconds += DateTime.now()
          .difference(_segmentStart!)
          .inSeconds;
      _segmentStart = null;
    }

    emit(
      HikeTrackPaused(
        points: List.unmodifiable(_points),
        distanceMeters: _distanceMeters,
        activeDurationSeconds: _accumulatedSeconds,
        elevGainMeters: _elevGainMeters,
        elevLossMeters: _elevLossMeters,
      ),
    );
  }

  /// Resume recording after a pause.
  Future<void> resume() async {
    _segmentStart = DateTime.now();
    await _subscribeToPosition();
    _startDurationTimer();
    _emitRecording();
  }

  /// Stop recording and emit the final summary.
  void stop() {
    _positionSub?.cancel();
    _positionSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;

    if (_segmentStart != null) {
      _accumulatedSeconds += DateTime.now()
          .difference(_segmentStart!)
          .inSeconds;
      _segmentStart = null;
    }

    final now = DateTime.now();
    final track = HikeTrack(
      id: _uuid.v4(),
      name: _defaultName(now),
      points: List.unmodifiable(_points),
      startTime: _hikeStartTime ?? now,
      endTime: now,
      totalDistanceMeters: _distanceMeters,
      activeDurationSeconds: _accumulatedSeconds,
      elevationGainMeters: _elevGainMeters,
      elevationLossMeters: _elevLossMeters,
    );

    emit(HikeTrackStopped(track));
  }

  /// Persist the stopped track with a user-provided name.
  Future<void> save(String name) async {
    final current = state;
    if (current is! HikeTrackStopped) return;

    final track = HikeTrack(
      id: current.track.id,
      name: name.trim().isEmpty ? current.track.name : name.trim(),
      points: current.track.points,
      startTime: current.track.startTime,
      endTime: current.track.endTime,
      totalDistanceMeters: current.track.totalDistanceMeters,
      activeDurationSeconds: current.track.activeDurationSeconds,
      elevationGainMeters: current.track.elevationGainMeters,
      elevationLossMeters: current.track.elevationLossMeters,
    );

    await _service.save(track);
    emit(const HikeTrackIdle());
  }

  /// Discard the current recording without saving.
  void discard() {
    _positionSub?.cancel();
    _positionSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _points.clear();
    emit(const HikeTrackIdle());
  }

  /// View a previously saved track on the map.
  void viewSaved(HikeTrack track) => emit(HikeTrackViewing(track));

  /// Clear the viewed track and return to idle.
  void clear() => emit(const HikeTrackIdle());

  /// Load all saved hike tracks.
  Future<List<HikeTrack>> loadSaved() => _service.loadAll();

  /// Delete a saved hike track by ID.
  Future<void> deleteSaved(String id) => _service.delete(id);

  /// Rename a saved hike track.
  Future<void> renameSaved(String id, String newName) async {
    final all = await _service.loadAll();
    final idx = all.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final old = all[idx];
    final updated = HikeTrack(
      id: old.id,
      name: newName.trim().isEmpty ? old.name : newName.trim(),
      points: old.points,
      startTime: old.startTime,
      endTime: old.endTime,
      totalDistanceMeters: old.totalDistanceMeters,
      activeDurationSeconds: old.activeDurationSeconds,
      elevationGainMeters: old.elevationGainMeters,
      elevationLossMeters: old.elevationLossMeters,
    );
    await _service.update(updated);
  }

  // ── Private ─────────────────────────────────────────────────────────

  Future<void> _subscribeToPosition() async {
    await _positionSub?.cancel();

    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Monyx — Tracking Hike',
          notificationText: 'Recording your path',
          enableWakeLock: true,
        ),
      );
    } else {
      // iOS
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          _onPosition,
          onError: (e) => debugPrint('[HikeTrackCubit] position error: $e'),
        );
  }

  void _onPosition(Position pos) {
    final point = HikePoint(
      lat: pos.latitude,
      lon: pos.longitude,
      altitudeMeters: pos.altitude,
      timestamp: DateTime.now(),
    );

    if (_points.isEmpty) {
      _points.add(point);
      _emitRecording();
      return;
    }

    final last = _points.last;
    final dist = haversineMeters(last.lat, last.lon, point.lat, point.lon);

    if (dist < _minDistanceMeters) return;

    // Accumulate distance
    _distanceMeters += dist;

    // Accumulate elevation with dead-band filter
    final elevDelta = point.altitudeMeters - last.altitudeMeters;
    if (elevDelta.abs() >= _elevDeadBandMeters) {
      if (elevDelta > 0) {
        _elevGainMeters += elevDelta;
      } else {
        _elevLossMeters += elevDelta.abs();
      }
    }

    _points.add(point);
    _emitRecording();
  }

  void _emitRecording() {
    final activeSeconds =
        _accumulatedSeconds +
        (_segmentStart != null
            ? DateTime.now().difference(_segmentStart!).inSeconds
            : 0);

    emit(
      HikeTrackRecording(
        points: List.unmodifiable(_points),
        distanceMeters: _distanceMeters,
        activeDurationSeconds: activeSeconds,
        elevGainMeters: _elevGainMeters,
        elevLossMeters: _elevLossMeters,
      ),
    );
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state is HikeTrackRecording) {
        _emitRecording();
      }
    });
  }

  String _defaultName(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return 'Hike — $month/$day/${dt.year} $hour:$minute $ampm';
  }

  @override
  Future<void> close() {
    _positionSub?.cancel();
    _durationTimer?.cancel();
    return super.close();
  }
}
