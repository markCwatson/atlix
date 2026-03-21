import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../blocs/profile_cubit.dart';
import '../blocs/solution_cubit.dart';
import '../blocs/subscription_cubit.dart';
import '../models/shot_solution.dart';
import '../services/ad_service.dart';
import '../widgets/solution_card.dart';
import 'profile_list_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _annotationManager;
  PolylineAnnotationManager? _lineManager;
  PointAnnotationManager? _labelManager;
  double? _userLat;
  double? _userLon;
  bool _locationReady = false;
  final Map<String, ShotSolution> _lineSolutions = {};
  final Map<String, _AnnotationGroup> _annotationGroups = {};
  BannerAd? _bannerAd;
  StreamSubscription<SubscriptionState>? _subSub;

  @override
  void initState() {
    super.initState();
    _initLocation();
    // Only load ads for free-tier users
    final subCubit = context.read<SubscriptionCubit>();
    if (subCubit.state is! SubscriptionPro) {
      // Defer ad loading until after the first frame so MediaQuery is available
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadBannerAd();
      });
    }
    // Listen for subscription changes to hide ads after purchase
    _subSub = subCubit.stream.listen((state) {
      if (state is SubscriptionPro && _bannerAd != null) {
        _bannerAd!.dispose();
        if (mounted) setState(() => _bannerAd = null);
      }
    });
  }

  @override
  void dispose() {
    _subSub?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() async {
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width == 0) return;

    // Use an anchored adaptive banner sized to the screen width
    final adSize = await AdSize.getAnchoredAdaptiveBannerAdSize(
      Orientation.portrait,
      width,
    );

    if (adSize == null || !mounted) return;

    _bannerAd = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          //debugPrint('Banner ad loaded successfully');
          if (mounted) setState(() {});
        },
        onAdFailedToLoad: (ad, error) {
          //debugPrint('Banner ad failed to load: ${error.message}');
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) return;
    }
    if (permission == geo.LocationPermission.deniedForever) return;

    final pos = await geo.Geolocator.getCurrentPosition(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
      ),
    );
    if (mounted) {
      setState(() {
        _userLat = pos.latitude;
        _userLon = pos.longitude;
        _locationReady = true;
      });
      // Fly the map to the user's actual location
      _flyToUser();
    }
  }

  Future<void> _flyToUser() async {
    if (_mapboxMap == null || _userLat == null || _userLon == null) return;
    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(_userLon!, _userLat!)),
        zoom: 15.0,
      ),
      MapAnimationOptions(duration: 1500),
    );
  }

  void _onMapCreated(MapboxMap map) async {
    _mapboxMap = map;

    // Enable user location puck
    await map.location.updateSettings(
      LocationComponentSettings(enabled: true, pulsingEnabled: true),
    );

    // Set up annotation managers for target pins and line
    _annotationManager = await map.annotations.createPointAnnotationManager();
    _lineManager = await map.annotations.createPolylineAnnotationManager();
    _labelManager = await map.annotations.createPointAnnotationManager();
    _lineManager?.tapEvents(
      onTap: (annotation) {
        if (!mounted) return;
        final solution = _lineSolutions[annotation.id];
        if (solution != null) {
          context.read<SolutionCubit>().show(solution, lineId: annotation.id);
        }
      },
    );

    // If location already arrived before map was created, fly now
    if (_locationReady) _flyToUser();
  }

  Future<void> _zoomIn() async {
    if (_mapboxMap == null) return;
    final camera = await _mapboxMap!.getCameraState();
    await _mapboxMap!.flyTo(
      CameraOptions(zoom: camera.zoom + 1),
      MapAnimationOptions(duration: 300),
    );
  }

  Future<void> _zoomOut() async {
    if (_mapboxMap == null) return;
    final camera = await _mapboxMap!.getCameraState();
    await _mapboxMap!.flyTo(
      CameraOptions(zoom: camera.zoom - 1),
      MapAnimationOptions(duration: 300),
    );
  }

  void _onMapLongTap(MapContentGestureContext gesture) async {
    final point = gesture.point;
    final lat = point.coordinates.lat.toDouble();
    final lon = point.coordinates.lng.toDouble();

    // Check we have a profile
    final profileState = context.read<ProfileCubit>().state;
    if (profileState is! ProfileLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a rifle profile first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check we have user location
    if (_userLat == null || _userLon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Waiting for GPS location...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Drop pin on map
    final cubit = context.read<SolutionCubit>();
    final pin = await _annotationManager?.create(
      PointAnnotationOptions(
        geometry: point,
        iconSize: 1.5,
        iconImage: 'marker-15',
      ),
    );

    // Draw red line from user to target
    final line = await _lineManager?.create(
      PolylineAnnotationOptions(
        geometry: LineString(
          coordinates: [Position(_userLon!, _userLat!), Position(lon, lat)],
        ),
        lineColor: Colors.red.toARGB32(),
        lineWidth: 3.0,
      ),
    );

    // Compute solution
    if (!mounted) return;
    // note: the equivalent of this.$store.dispatch('compute', payload) in Vuex.
    // The Cubit fetches weather, runs the solver, and calls
    // emit(SolutionReady(solution)). The UI sees the new state and
    // shows the solution card.
    cubit.compute(
      profile: profileState.profile,
      shooterLat: _userLat!,
      shooterLon: _userLon!,
      targetLat: lat,
      targetLon: lon,
      lineId: line?.id,
    );

    // Map the result to this line when it arrives
    if (line != null) {
      final midLat = (_userLat! + lat) / 2;
      final midLon = (_userLon! + lon) / 2;
      late final StreamSubscription<SolutionState> sub;
      sub = cubit.stream.listen((state) {
        if (state is SolutionReady) {
          _lineSolutions[line.id] = state.solution;
          final s = state.solution;
          final label =
              '${s.rangeYards.round()} / ${s.dropMoa.abs().toStringAsFixed(1)} / ${s.windDriftMoa.abs().toStringAsFixed(1)}';
          _labelManager
              ?.create(
                PointAnnotationOptions(
                  geometry: Point(coordinates: Position(midLon, midLat)),
                  textField: label,
                  textSize: 13,
                  textColor: Colors.white.toARGB32(),
                  textHaloColor: Colors.black.toARGB32(),
                  textHaloWidth: 1.5,
                  textAnchor: TextAnchor.CENTER,
                  iconSize: 0,
                ),
              )
              .then((labelAnnotation) {
                _annotationGroups[line.id] = _AnnotationGroup(
                  line: line,
                  pin: pin,
                  label: labelAnnotation,
                );
              });
          sub.cancel();
        } else if (state is SolutionError) {
          sub.cancel();
        }
      });
    }
  }

  void _deleteEntry(String lineId) {
    final group = _annotationGroups.remove(lineId);
    if (group != null) {
      _lineManager?.delete(group.line);
      if (group.pin != null) _annotationManager?.delete(group.pin!);
      _labelManager?.delete(group.label);
    }
    _lineSolutions.remove(lineId);
    context.read<SolutionCubit>().clear();
  }

  void _openProfileScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: context.read<ProfileCubit>()),
              BlocProvider.value(value: context.read<SubscriptionCubit>()),
            ],
            child: const ProfileListScreen(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // Map
                MapWidget(
                  key: const ValueKey('mapWidget'),
                  cameraOptions: CameraOptions(
                    center: _locationReady
                        ? Point(coordinates: Position(_userLon!, _userLat!))
                        : Point(coordinates: Position(-98.5795, 39.8283)),
                    zoom: _locationReady ? 14.0 : 4.0,
                  ),
                  styleUri: MapboxStyles.SATELLITE_STREETS,
                  onMapCreated: _onMapCreated,
                  onLongTapListener: _onMapLongTap,
                ),

                // Profile indicator (top left) — tappable when profiles exist
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 12,
                  child: BlocBuilder<ProfileCubit, ProfileState>(
                    builder: (context, state) {
                      final hasProfile = state is ProfileLoaded;
                      return GestureDetector(
                        onTap: _openProfileScreen,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasProfile ? Icons.edit : Icons.add,
                                color: hasProfile
                                    ? Colors.orangeAccent
                                    : Colors.orange,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                hasProfile
                                    ? state.profile.name
                                    : 'Create Profile',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              if (hasProfile) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white38,
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Crosshair hint
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Long-press to drop pin',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ),
                ),

                // Zoom controls + my location (right side)
                Positioned(
                  right: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 5,
                  child: Column(
                    children: [
                      _mapButton(Icons.my_location, _flyToUser),
                      const SizedBox(height: 8),
                      _mapButton(Icons.add, _zoomIn),
                      const SizedBox(height: 8),
                      _mapButton(Icons.remove, _zoomOut),
                    ],
                  ),
                ),

                // Solution computing indicator
                BlocBuilder<SolutionCubit, SolutionState>(
                  builder: (context, state) {
                    if (state is SolutionComputing) {
                      return const Center(
                        child: Card(
                          color: Colors.black87,
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: Colors.orangeAccent,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Computing solution...',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Solution card (bottom sheet)
                BlocBuilder<SolutionCubit, SolutionState>(
                  builder: (context, state) {
                    if (state is SolutionReady) {
                      return Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _DismissibleSolutionCard(
                          solution: state.solution,
                          onDismiss: () =>
                              context.read<SolutionCubit>().clear(),
                          onDelete: state.lineId != null
                              ? () => _deleteEntry(state.lineId!)
                              : null,
                        ),
                      );
                    }
                    if (state is SolutionError) {
                      return Positioned(
                        left: 16,
                        right: 16,
                        bottom: MediaQuery.of(context).padding.bottom + 90,
                        child: Card(
                          color: Colors.red[900],
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              state.message,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
          // Banner ad
          if (_bannerAd != null)
            SafeArea(
              top: false,
              child: SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mapButton(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: icon.hashCode.toString(),
        mini: true,
        backgroundColor: Colors.black87,
        onPressed: onPressed,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Wraps the solution card with swipe-to-dismiss and a close button.
class _DismissibleSolutionCard extends StatefulWidget {
  final ShotSolution solution;
  final VoidCallback onDismiss;
  final VoidCallback? onDelete;

  const _DismissibleSolutionCard({
    required this.solution,
    required this.onDismiss,
    this.onDelete,
  });

  @override
  State<_DismissibleSolutionCard> createState() =>
      _DismissibleSolutionCardState();
}

class _DismissibleSolutionCardState extends State<_DismissibleSolutionCard> {
  double _dragOffset = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 400.0);
        });
      },
      onVerticalDragEnd: (details) {
        if (_dragOffset > 80 || details.primaryVelocity! > 300) {
          widget.onDismiss();
        } else {
          setState(() => _dragOffset = 0);
        }
      },
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Stack(
          children: [
            SolutionCard(
              solution: widget.solution,
              onDismiss: widget.onDismiss,
            ),
            // Close button (top right)
            Positioned(
              top: 12,
              right: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onDelete != null)
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.red[800],
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ),
                  if (widget.onDelete != null) const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnotationGroup {
  final PolylineAnnotation line;
  final PointAnnotation? pin;
  final PointAnnotation label;

  _AnnotationGroup({required this.line, this.pin, required this.label});
}
