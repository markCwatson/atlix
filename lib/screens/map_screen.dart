import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    hide Size, ImageSource;

import '../blocs/profile_cubit.dart';
import '../blocs/solution_cubit.dart';
import '../blocs/subscription_cubit.dart';
import '../blocs/plant_cubit.dart';
import '../blocs/track_cubit.dart';
import '../models/plant_result.dart';
import '../models/poi.dart';
import '../models/shot_solution.dart';
import '../models/track_result.dart';
import '../services/ad_service.dart';
import '../services/poi_service.dart';
import '../widgets/compass_overlay.dart';
import '../widgets/solution_card.dart';
import 'plant_result_screen.dart';
import 'profile_list_screen.dart';
import 'saved_plants_screen.dart';
import 'saved_tracks_screen.dart';
import 'track_result_screen.dart';

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
  bool _compassEnabled = false;
  double? _heading;
  double? _magnetHeading;
  double? _gpsHeading;
  double _speed = 0;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<geo.Position>? _positionSub;
  PointAnnotationManager? _poiManager;
  final PoiService _poiService = PoiService();
  final Map<String, Poi> _poiAnnotations = {};

  @override
  void initState() {
    super.initState();
    _initLocation();
    _compassSub = FlutterCompass.events?.listen((event) {
      if (mounted && event.heading != null) {
        _magnetHeading = event.heading;
        // Use magnetometer when stationary (speed < 2 m/s)
        if (_speed < 2) {
          setState(() => _heading = _magnetHeading);
          _updateMapBearing();
        }
      }
    });
    // GPS bearing stream for compass while moving
    _positionSub =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((pos) {
          if (!mounted) return;
          _speed = pos.speed;
          _userLat = pos.latitude;
          _userLon = pos.longitude;
          // Use GPS bearing when moving (speed >= 2 m/s) and bearing is valid
          if (_speed >= 2 && pos.heading >= 0) {
            _gpsHeading = pos.heading;
            setState(() => _heading = _gpsHeading);
            _updateMapBearing();
          }
        });
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
    _compassSub?.cancel();
    _positionSub?.cancel();
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
        bearing: _compassEnabled && _heading != null ? _heading! : null,
      ),
      MapAnimationOptions(duration: 1500),
    );
  }

  void _updateMapBearing() {
    if (!_compassEnabled || _heading == null || _mapboxMap == null) return;
    _mapboxMap!.setCamera(CameraOptions(bearing: _heading!));
  }

  void _onMapCreated(MapboxMap map) async {
    _mapboxMap = map;

    // Enable user location puck with bearing indicator
    await map.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
      ),
    );

    // Set up annotation managers for target pins and line
    _annotationManager = await map.annotations.createPointAnnotationManager();
    _lineManager = await map.annotations.createPolylineAnnotationManager();
    _labelManager = await map.annotations.createPointAnnotationManager();
    _poiManager = await map.annotations.createPointAnnotationManager();
    _poiManager?.tapEvents(
      onTap: (annotation) {
        if (!mounted) return;
        final poi = _poiAnnotations[annotation.id];
        if (poi != null) _showPoiDetail(poi, annotation.id);
      },
    );
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

    // Register custom POI pin images
    await _registerPoiIcons();

    // Load saved POIs
    await _loadSavedPois();
  }

  Future<void> _registerPoiIcons() async {
    for (final type in PoiType.values) {
      final bytes = await _renderPoiPin(type);
      await _mapboxMap!.style.addStyleImage(
        'poi-${type.name}',
        2.0,
        MbxImage(width: 128, height: 160, data: bytes),
        false,
        [],
        [],
        null,
      );
    }
  }

  Future<Uint8List> _renderPoiPin(PoiType type) async {
    const int w = 128, h = 160;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    final color = _poiColor(type);

    // Combined pin shape: rounded rect body merged with triangle pointer
    final pinPaint = Paint()..color = color;
    const double bodyTop = 4;
    const double bodyBottom = 104;
    const double bodyLeft = 8;
    const double bodyRight = 120;
    const double r = 24; // corner radius
    const double tipY = 148;
    const double tipX = 64;

    final pin = Path()
      // Start at top-left after corner
      ..moveTo(bodyLeft + r, bodyTop)
      // Top edge
      ..lineTo(bodyRight - r, bodyTop)
      // Top-right corner
      ..arcToPoint(
        const Offset(bodyRight, bodyTop + r),
        radius: const Radius.circular(r),
      )
      // Right edge
      ..lineTo(bodyRight, bodyBottom - r)
      // Bottom-right corner
      ..arcToPoint(
        const Offset(bodyRight - r, bodyBottom),
        radius: const Radius.circular(r),
      )
      // Bottom edge to right side of pointer
      ..lineTo(tipX + 20, bodyBottom)
      // Pointer tip
      ..lineTo(tipX, tipY)
      ..lineTo(tipX - 20, bodyBottom)
      // Bottom edge to left side
      ..lineTo(bodyLeft + r, bodyBottom)
      // Bottom-left corner
      ..arcToPoint(
        Offset(bodyLeft, bodyBottom - r),
        radius: const Radius.circular(r),
      )
      // Left edge
      ..lineTo(bodyLeft, bodyTop + r)
      // Top-left corner
      ..arcToPoint(
        Offset(bodyLeft + r, bodyTop),
        radius: const Radius.circular(r),
      )
      ..close();

    canvas.drawPath(pin, pinPaint);

    // Dark outline
    final outlinePaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(pin, outlinePaint);

    // Icon inside pin
    final icon = _poiIcon(type);
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 56,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((w - tp.width) / 2, (108 - tp.height) / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage(w, h);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
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

  void _onMapTap(MapContentGestureContext gesture) {
    final point = gesture.point;
    final lat = point.coordinates.lat.toDouble();
    final lon = point.coordinates.lng.toDouble();
    _showPoiTypePicker(lat, lon);
  }

  void _showPoiTypePicker(double lat, double lon) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Drop Pin',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ...PoiType.values.map(
                  (type) => _poiTypeOption(ctx, type, lat, lon),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _poiTypeOption(
    BuildContext ctx,
    PoiType type,
    double lat,
    double lon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(_poiIcon(type), color: _poiColor(type)),
        title: Text(type.label, style: const TextStyle(color: Colors.white)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: Colors.grey[800],
        onTap: () {
          Navigator.pop(ctx);
          if (type == PoiType.custom) {
            _showCustomPinNameDialog(lat, lon);
          } else {
            _dropPoiPin(type, lat, lon);
          }
        },
      ),
    );
  }

  void _showCustomPinNameDialog(double lat, double lon) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Custom Pin', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter pin name',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[600]!),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.orangeAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.pop(ctx);
              _dropPoiPin(
                PoiType.custom,
                lat,
                lon,
                note: name.isNotEmpty ? name : null,
              );
            },
            child: const Text(
              'Drop Pin',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dropPoiPin(
    PoiType type,
    double lat,
    double lon, {
    String? note,
  }) async {
    final poi = Poi(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      note: note,
    );

    await _poiService.save(poi);
    await _addPoiAnnotation(poi);
  }

  Future<void> _addPoiAnnotation(Poi poi) async {
    final label = poi.note ?? poi.type.label;
    final annotation = await _poiManager?.create(
      PointAnnotationOptions(
        geometry: Point(coordinates: Position(poi.longitude, poi.latitude)),
        iconImage: 'poi-${poi.type.name}',
        iconSize: 0.8,
        iconAnchor: IconAnchor.BOTTOM,
        textField: label,
        textSize: 11,
        textColor: Colors.white.toARGB32(),
        textHaloColor: Colors.black.toARGB32(),
        textHaloWidth: 1.0,
        textAnchor: TextAnchor.TOP,
        textOffset: [0.0, 0.5],
      ),
    );
    if (annotation != null) {
      _poiAnnotations[annotation.id] = poi;
    }
  }

  Future<void> _loadSavedPois() async {
    final pois = await _poiService.loadAll();
    for (final poi in pois) {
      await _addPoiAnnotation(poi);
    }
  }

  void _showPoiDetail(Poi poi, String annotationId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_poiIcon(poi.type), color: _poiColor(poi.type), size: 40),
              const SizedBox(height: 12),
              Text(
                poi.note ?? poi.type.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (poi.note != null) ...[
                const SizedBox(height: 2),
                Text(
                  poi.type.label,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '${poi.latitude.toStringAsFixed(5)}, ${poi.longitude.toStringAsFixed(5)}',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                icon: const Icon(Icons.delete),
                label: const Text('Delete Pin'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _poiService.delete(poi.id);
                  final entry = _poiAnnotations.entries
                      .where((e) => e.value.id == poi.id)
                      .firstOrNull;
                  if (entry != null) {
                    // Remove the annotation from the map by its manager ID
                    _poiManager?.deleteAll();
                    _poiAnnotations.clear();
                    await _loadSavedPois();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _poiIcon(PoiType type) => switch (type) {
    PoiType.campsite => Icons.cabin,
    PoiType.treeStand => Icons.nature,
    PoiType.trailCam => Icons.videocam,
    PoiType.waterSource => Icons.water_drop,
    PoiType.foodPlot => Icons.grass,
    PoiType.parking => Icons.local_parking,
    PoiType.custom => Icons.place,
  };

  Color _poiColor(PoiType type) => switch (type) {
    PoiType.campsite => Colors.orangeAccent,
    PoiType.treeStand => Colors.green,
    PoiType.trailCam => Colors.lightBlue,
    PoiType.waterSource => Colors.blue,
    PoiType.foodPlot => Colors.lime,
    PoiType.parking => Colors.grey,
    PoiType.custom => Colors.white,
  };

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
                  onTapListener: _onMapTap,
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
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Long press for ballistics calc',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Short press to drop pin',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),

                // ID buttons + history (left side)
                Positioned(
                  left: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 5,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Plant ID
                      BlocConsumer<PlantCubit, PlantState>(
                        listenWhen: (prev, curr) =>
                            (curr is PlantDone &&
                                !curr.saved &&
                                prev is! PlantDone) ||
                            curr is PlantError,
                        listener: (context, state) {
                          if (state is PlantDone) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BlocProvider.value(
                                  value: context.read<PlantCubit>(),
                                  child: PlantResultScreen(
                                    result: state.result,
                                  ),
                                ),
                              ),
                            );
                          } else if (state is PlantError) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(state.message),
                                backgroundColor: Colors.red[700],
                              ),
                            );
                          }
                        },
                        builder: (context, plantState) {
                          final isPro = context
                              .watch<SubscriptionCubit>()
                              .isPro;
                          final isClassifying = plantState is PlantClassifying;
                          return _plantIdButton(
                            isPro: isPro,
                            isClassifying: isClassifying,
                            onTap: () => isPro
                                ? _showPlantPartPicker(context)
                                : _showUpgradeSheet(context),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      // Track ID
                      BlocConsumer<TrackCubit, TrackState>(
                        listenWhen: (prev, curr) =>
                            (curr is TrackDone &&
                                !curr.saved &&
                                prev is! TrackDone) ||
                            curr is TrackError,
                        listener: (context, state) {
                          if (state is TrackDone) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BlocProvider.value(
                                  value: context.read<TrackCubit>(),
                                  child: TrackResultScreen(
                                    result: state.result,
                                  ),
                                ),
                              ),
                            );
                          } else if (state is TrackError) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(state.message),
                                backgroundColor: Colors.red[700],
                              ),
                            );
                          }
                        },
                        builder: (context, trackState) {
                          final isPro = context
                              .watch<SubscriptionCubit>()
                              .isPro;
                          final isDetecting = trackState is TrackDetecting;
                          return _trackIdButton(
                            isPro: isPro,
                            isDetecting: isDetecting,
                            onTap: () => isPro
                                ? _showTraceTypePicker(context)
                                : _showUpgradeSheet(context),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      // Shared history
                      _mapButton(
                        Icons.history,
                        () => _showHistoryPicker(context),
                      ),
                    ],
                  ),
                ),

                // Compass overlay
                if (_compassEnabled && _heading != null)
                  CompassOverlay(heading: _heading!),

                // Zoom controls + compass + my location (right side)
                Positioned(
                  right: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 5,
                  child: Column(
                    children: [
                      _compassButton(),
                      const SizedBox(height: 8),
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

  Widget _compassButton() {
    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: 'compass',
        mini: true,
        backgroundColor: _compassEnabled ? Colors.orangeAccent : Colors.black87,
        onPressed: () {
          if (_heading == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Compass not available on this device'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
          setState(() => _compassEnabled = !_compassEnabled);
          if (!_compassEnabled) {
            // Reset map to north-up when leaving compass mode
            _mapboxMap?.flyTo(
              CameraOptions(bearing: 0),
              MapAnimationOptions(duration: 300),
            );
          } else {
            _updateMapBearing();
          }
        },
        child: Icon(
          Icons.explore,
          color: _compassEnabled ? Colors.black : Colors.white,
          size: 20,
        ),
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

  Widget _trackIdButton({
    required bool isPro,
    required bool isDetecting,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: 'track_id',
        mini: true,
        backgroundColor: isPro ? Colors.black87 : Colors.grey[800],
        onPressed: isDetecting ? null : onTap,
        child: isDetecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.orangeAccent,
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.pets,
                    color: isPro ? Colors.orangeAccent : Colors.white38,
                    size: 20,
                  ),
                  if (!isPro)
                    const Positioned(
                      right: -2,
                      bottom: -2,
                      child: Icon(Icons.lock, color: Colors.white54, size: 10),
                    ),
                ],
              ),
      ),
    );
  }

  void _showTraceTypePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Identify Animal Track',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _traceOption(
                context: ctx,
                icon: Icons.pets,
                label: 'Footprint',
                subtitle: '117 species',
                traceType: TraceType.footprint,
              ),
              const SizedBox(height: 8),
              _traceOption(
                context: ctx,
                icon: Icons.blur_circular,
                label: 'Scat / Feces',
                subtitle: '101 species',
                traceType: TraceType.feces,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _openSavedTracks(ctx),
                child: const Text(
                  'View Saved Tracks',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startCapture(
    BuildContext sheetContext,
    TraceType traceType,
    ImageSource source,
  ) {
    Navigator.pop(sheetContext);
    context.read<TrackCubit>().capture(
      traceType,
      source: source,
      latitude: _userLat,
      longitude: _userLon,
    );
  }

  Widget _traceOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required TraceType traceType,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.orangeAccent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () =>
                _startCapture(context, traceType, ImageSource.camera),
            icon: const Icon(Icons.camera_alt, color: Colors.orangeAccent),
            tooltip: 'Camera',
          ),
          IconButton(
            onPressed: () =>
                _startCapture(context, traceType, ImageSource.gallery),
            icon: const Icon(Icons.photo_library, color: Colors.orangeAccent),
            tooltip: 'Photos',
          ),
        ],
      ),
    );
  }

  void _showUpgradeSheet(BuildContext context) {
    final subCubit = context.read<SubscriptionCubit>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, color: Colors.orangeAccent, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Upgrade to Monyx Pro',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unlock track identification, unlimited profiles, and remove all ads.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              BlocBuilder<SubscriptionCubit, SubscriptionState>(
                bloc: subCubit,
                builder: (context, state) {
                  final price = state is SubscriptionFree
                      ? state.product?.price ?? ''
                      : '';
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () {
                      subCubit.purchase();
                      Navigator.pop(context);
                    },
                    child: Text(
                      price.isNotEmpty
                          ? 'Subscribe — $price / month'
                          : 'Subscribe to Pro',
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  subCubit.restore();
                  Navigator.pop(context);
                },
                child: const Text(
                  'Restore Purchase',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plantIdButton({
    required bool isPro,
    required bool isClassifying,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: 'plant_id',
        mini: true,
        backgroundColor: isPro ? Colors.black87 : Colors.grey[800],
        onPressed: isClassifying ? null : onTap,
        child: isClassifying
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.green,
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.local_florist,
                    color: isPro ? Colors.green : Colors.white38,
                    size: 20,
                  ),
                  if (!isPro)
                    const Positioned(
                      right: -2,
                      bottom: -2,
                      child: Icon(Icons.lock, color: Colors.white54, size: 10),
                    ),
                ],
              ),
      ),
    );
  }

  void _showPlantPartPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Identify Plant',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.eco,
                  label: 'Leaf',
                  plantPart: PlantPart.leaf,
                ),
                const SizedBox(height: 8),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.local_florist,
                  label: 'Flower',
                  plantPart: PlantPart.flower,
                ),
                const SizedBox(height: 8),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.park,
                  label: 'Bark',
                  plantPart: PlantPart.bark,
                ),
                const SizedBox(height: 8),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.apple,
                  label: 'Fruit',
                  plantPart: PlantPart.fruit,
                ),
                const SizedBox(height: 8),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.grass,
                  label: 'Whole Plant',
                  plantPart: PlantPart.wholePlant,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => _openSavedPlants(ctx),
                  child: const Text(
                    'View Saved Plants',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startPlantCapture(
    BuildContext sheetContext,
    PlantPart plantPart,
    ImageSource source,
  ) {
    Navigator.pop(sheetContext);
    context.read<PlantCubit>().capture(
      plantPart,
      source: source,
      latitude: _userLat,
      longitude: _userLon,
    );
  }

  Widget _plantPartOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required PlantPart plantPart,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.green, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () =>
                _startPlantCapture(context, plantPart, ImageSource.camera),
            icon: const Icon(Icons.camera_alt, color: Colors.green),
            tooltip: 'Camera',
          ),
          IconButton(
            onPressed: () =>
                _startPlantCapture(context, plantPart, ImageSource.gallery),
            icon: const Icon(Icons.photo_library, color: Colors.green),
            tooltip: 'Photos',
          ),
        ],
      ),
    );
  }

  void _openSavedPlants(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route is! PopupRoute);
    Navigator.of(this.context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: this.context.read<PlantCubit>(),
          child: const SavedPlantsScreen(),
        ),
      ),
    );
  }

  void _openSavedTracks(BuildContext context) {
    // Dismiss any open bottom sheet first
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route is! PopupRoute);
    Navigator.of(this.context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: this.context.read<TrackCubit>(),
          child: const SavedTracksScreen(),
        ),
      ),
    );
  }

  void _showHistoryPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Saved History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.pets, color: Colors.orangeAccent),
                title: const Text(
                  'Animal Tracks',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () => _openSavedTracks(ctx),
              ),
              ListTile(
                leading: const Icon(Icons.local_florist, color: Colors.green),
                title: const Text(
                  'Plant IDs',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () => _openSavedPlants(ctx),
              ),
            ],
          ),
        ),
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
        child: SolutionCard(
          solution: widget.solution,
          onDismiss: widget.onDismiss,
          onDelete: widget.onDelete,
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
