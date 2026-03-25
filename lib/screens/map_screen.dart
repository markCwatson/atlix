import 'dart:async';
import 'dart:io';
import 'dart:math' show pi;
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
import 'package:url_launcher/url_launcher.dart';

import '../blocs/hike_track_cubit.dart';
import '../blocs/profile_cubit.dart';
import '../blocs/solution_cubit.dart';
import '../blocs/subscription_cubit.dart';
import '../blocs/plant_cubit.dart';
import '../blocs/track_cubit.dart';
import '../models/hike_track.dart';
import '../models/plant_result.dart';
import '../models/poi.dart';
import '../models/shot_solution.dart';
import '../models/track_result.dart';
import '../models/weather_data.dart';
import '../ballistics/conversions.dart';
import '../models/weather_profile.dart';
import '../models/wind_data.dart';
import '../services/ad_service.dart';
import '../services/poi_service.dart';
import '../services/weather_profile_service.dart';
import '../services/weather_service.dart';
import '../widgets/bullet_arc_overlay.dart';
import '../widgets/compass_overlay.dart';
import '../widgets/solution_card.dart';
import '../widgets/wind_overlay.dart';
import 'plant_result_screen.dart';
import 'hike_summary_screen.dart';
import 'profile_list_screen.dart';
import 'saved_hike_tracks_screen.dart';
import 'saved_plants_screen.dart';
import 'saved_tracks_screen.dart';
import 'saved_weather_screen.dart';
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
  final Map<String, ({double sLat, double sLon, double tLat, double tLon})>
  _lineEndpoints = {};
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
  final WeatherProfileService _weatherProfileService = WeatherProfileService();
  final Map<String, Poi> _poiAnnotations = {};
  bool _windEnabled = false;
  bool _windLoading = false;
  bool _windManual =
      false; // true when wind was entered manually (no animation)
  WindField? _windField;
  double _windBearingDeg = 0;
  double _windSpeedMph = 0;
  double? _manualTempF;
  double? _manualPressureInHg;
  double? _manualHumidity;
  double _mapBearing = 0;
  double _mapZoom = 14;
  bool _lineTapped = false; // suppress POI picker when a line is tapped
  bool _windPickLocation = false; // true while user is tapping a wind location
  DateTime? _windForecastTime; // non-null when "Later" flow is active

  // ── Hike tracking state ───────────────────────────────────────────
  bool _hikeTrackLayerReady = false; // true once GeoJSON source + layers exist
  StreamSubscription<HikeTrackState>? _hikeTrackSub;

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
    // Listen for hike track state changes to update the path on the map
    _hikeTrackSub = context.read<HikeTrackCubit>().stream.listen((state) {
      if (!mounted) return;
      if (state is HikeTrackRecording) {
        _updateHikeTrackPath(state.points);
        setState(() {});
      } else if (state is HikeTrackPaused) {
        setState(() {});
      } else if (state is HikeTrackStopped) {
        _updateHikeTrackPath(state.track.points);
        setState(() {});
        _openHikeSummary(state.track);
      } else if (state is HikeTrackViewing) {
        _updateHikeTrackPath(state.track.points);
        setState(() {});
        _openHikeSummary(state.track, viewOnly: true);
      } else if (state is HikeTrackIdle) {
        _clearHikeTrackPath();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _positionSub?.cancel();
    _subSub?.cancel();
    _hikeTrackSub?.cancel();
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
    if (_windEnabled) _syncCamera();
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
        _lineTapped = true;
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
        lineWidth: 6.0,
      ),
    );

    // Compute solution
    if (!mounted) return;
    // note: the equivalent of this.$store.dispatch('compute', payload) in Vuex.
    // The Cubit fetches weather, runs the solver, and calls
    // emit(SolutionReady(solution)). The UI sees the new state and
    // shows the solution card.
    final isPro = context.read<SubscriptionCubit>().isPro;
    final hasManualWeather =
        _manualTempF != null ||
        _manualPressureInHg != null ||
        _manualHumidity != null;
    cubit.compute(
      profile: profileState.profile,
      shooterLat: _userLat!,
      shooterLon: _userLon!,
      targetLat: lat,
      targetLon: lon,
      lineId: line?.id,
      windSpeedMph: _windEnabled ? _windSpeedMph : 0,
      windDirectionDeg: _windEnabled ? _windBearingDeg : 0,
      skipWeatherApi: !isPro,
      manualWeather: (!isPro && hasManualWeather)
          ? WeatherData(
              temperatureF: _manualTempF ?? 59.0,
              pressureInHg: _manualPressureInHg ?? 29.92,
              humidityPercent: _manualHumidity ?? 50.0,
              windSpeedMph: _windEnabled ? _windSpeedMph : 0,
              windDirectionDeg: _windEnabled ? _windBearingDeg : 0,
              source: WeatherSource.estimated,
            )
          : null,
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
                _lineEndpoints[line.id] = (
                  sLat: _userLat!,
                  sLon: _userLon!,
                  tLat: lat,
                  tLon: lon,
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
    // Skip POI picker if a line annotation was just tapped
    if (_lineTapped) {
      _lineTapped = false;
      return;
    }

    final point = gesture.point;
    final lat = point.coordinates.lat.toDouble();
    final lon = point.coordinates.lng.toDouble();

    // Intercept tap for wind location picking
    if (_windPickLocation) {
      _handleWindLocationPick(lat, lon);
      return;
    }

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
          _showPoiMetadataForm(type, lat, lon);
        },
      ),
    );
  }

  /// Shows a form to enter notes and optionally attach a photo before
  /// dropping the pin.
  void _showPoiMetadataForm(PoiType type, double lat, double lon) {
    final noteCtrl = TextEditingController();
    String? pickedPhotoPath;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(_poiIcon(type), color: _poiColor(type), size: 28),
                      const SizedBox(width: 12),
                      Text(
                        type.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Add notes (optional)',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Photo preview or add button
                  if (pickedPhotoPath != null)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(pickedPhotoPath!),
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () =>
                                setSheetState(() => pickedPhotoPath = null),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.grey[600]!),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Add Photo'),
                      onPressed: () async {
                        final source = await _pickImageSource(ctx);
                        if (source == null) return;
                        final xFile = await ImagePicker().pickImage(
                          source: source,
                          maxWidth: 1920,
                          imageQuality: 85,
                        );
                        if (xFile != null) {
                          setSheetState(() => pickedPhotoPath = xFile.path);
                        }
                      },
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white54,
                            side: BorderSide(color: Colors.grey[700]!),
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _dropPoiPin(
                              type,
                              lat,
                              lon,
                              note: noteCtrl.text.trim().isNotEmpty
                                  ? noteCtrl.text.trim()
                                  : null,
                              tempPhotoPath: pickedPhotoPath,
                            );
                          },
                          child: const Text('Drop Pin'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Let the user choose camera or gallery.
  Future<ImageSource?> _pickImageSource(BuildContext ctx) async {
    return showModalBottomSheet<ImageSource>(
      context: ctx,
      backgroundColor: Colors.grey[850],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text(
                'Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dropPoiPin(
    PoiType type,
    double lat,
    double lon, {
    String? note,
    String? tempPhotoPath,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // Copy photo to permanent storage if provided
    String? photoPath;
    if (tempPhotoPath != null) {
      photoPath = await _poiService.savePhoto(tempPhotoPath, id);
    }

    final poi = Poi(
      id: id,
      type: type,
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      note: note,
      photoPath: photoPath,
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

  // ── Hike track path rendering ─────────────────────────────────────

  String _pointsGeoJson(List<HikePoint> points) {
    final features = points
        .map(
          (p) =>
              '{"type":"Feature","geometry":{"type":"Point","coordinates":[${p.lon},${p.lat}]},"properties":{}}',
        )
        .join(',');
    return '{"type":"FeatureCollection","features":[$features]}';
  }

  Future<void> _updateHikeTrackPath(List<HikePoint> points) async {
    if (_mapboxMap == null || points.length < 2) return;

    final coords = points.map((p) => Position(p.lon, p.lat)).toList();
    final lineString = LineString(coordinates: coords);
    final geojson =
        '{"type":"Feature","geometry":${lineString.toJson()},"properties":{}}';

    if (!_hikeTrackLayerReady) {
      // Create source + layers the first time
      await _mapboxMap!.style.addSource(
        GeoJsonSource(id: 'hike-track-source', data: geojson),
      );
      // Thin semi-transparent line as backbone
      await _mapboxMap!.style.addLayer(
        LineLayer(
          id: 'hike-track-line',
          sourceId: 'hike-track-source',
          lineColor: Colors.teal.toARGB32(),
          lineWidth: 3.0,
          lineOpacity: 0.5,
        ),
      );
      // Point markers along the path (circle layer on a separate point source)
      await _mapboxMap!.style.addSource(
        GeoJsonSource(id: 'hike-track-pts', data: _pointsGeoJson(points)),
      );
      await _mapboxMap!.style.addLayer(
        CircleLayer(
          id: 'hike-track-circles',
          sourceId: 'hike-track-pts',
          circleRadius: 4.0,
          circleColor: Colors.teal.toARGB32(),
          circleStrokeWidth: 1.5,
          circleStrokeColor: Colors.white.toARGB32(),
          circleOpacity: 0.9,
        ),
      );
      _hikeTrackLayerReady = true;
    } else {
      // Update existing source data
      final source =
          await _mapboxMap!.style.getSource('hike-track-source')
              as GeoJsonSource;
      await source.updateGeoJSON(geojson);
      final ptSource =
          await _mapboxMap!.style.getSource('hike-track-pts') as GeoJsonSource;
      await ptSource.updateGeoJSON(_pointsGeoJson(points));
    }
  }

  Future<void> _clearHikeTrackPath() async {
    if (!_hikeTrackLayerReady || _mapboxMap == null) return;
    try {
      await _mapboxMap!.style.removeStyleLayer('hike-track-circles');
      await _mapboxMap!.style.removeStyleLayer('hike-track-line');
      await _mapboxMap!.style.removeStyleSource('hike-track-pts');
      await _mapboxMap!.style.removeStyleSource('hike-track-source');
    } catch (_) {}
    _hikeTrackLayerReady = false;
  }

  void _showPoiDetail(Poi poi, String annotationId) {
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
                // Header
                Row(
                  children: [
                    Icon(
                      _poiIcon(poi.type),
                      color: _poiColor(poi.type),
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            poi.note ?? poi.type.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (poi.note != null)
                            Text(
                              poi.type.label,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${poi.latitude.toStringAsFixed(5)}, ${poi.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatTimestamp(poi.timestamp),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),

                // Photo
                if (poi.photoPath != null) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _showFullPhoto(poi.photoPath!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(poi.photoPath!),
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],

                // Notes
                if (poi.note != null && poi.note!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      poi.note!,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Action buttons
                _poiActionButton(
                  icon: Icons.edit,
                  label: poi.note != null ? 'Edit Notes' : 'Add Notes',
                  color: Colors.orangeAccent,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final updated = await _editPoiNote(poi);
                    if (updated != null) {
                      _refreshPoiAnnotations();
                    }
                  },
                ),
                const SizedBox(height: 8),
                _poiActionButton(
                  icon: Icons.camera_alt,
                  label: poi.photoPath != null ? 'Change Photo' : 'Add Photo',
                  color: Colors.lightBlue,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _addPoiPhoto(poi);
                  },
                ),
                const SizedBox(height: 8),
                _poiActionButton(
                  icon: Icons.directions,
                  label: 'Get Directions',
                  color: Colors.green,
                  onTap: () {
                    _openDirections(poi.latitude, poi.longitude);
                  },
                ),
                const SizedBox(height: 8),
                _poiActionButton(
                  icon: Icons.delete,
                  label: 'Delete Pin',
                  color: Colors.red,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _poiService.delete(poi.id);
                    _poiManager?.deleteAll();
                    _poiAnnotations.clear();
                    await _loadSavedPois();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _poiActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.3)),
          ),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }

  Future<Poi?> _editPoiNote(Poi poi) async {
    final controller = TextEditingController(text: poi.note ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Edit Notes', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter notes',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.grey[800],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
    if (result == null) return null;
    final updated = poi.copyWith(note: result.isNotEmpty ? result : null);
    await _poiService.update(updated);
    return updated;
  }

  Future<void> _addPoiPhoto(Poi poi) async {
    final source = await _pickImageSource(context);
    if (source == null) return;
    final xFile = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (xFile == null) return;

    // Delete old photo if replacing
    if (poi.photoPath != null) {
      await _poiService.deletePhoto(poi.photoPath);
    }

    final photoPath = await _poiService.savePhoto(xFile.path, poi.id);
    final updated = poi.copyWith(photoPath: photoPath);
    await _poiService.update(updated);
    _refreshPoiAnnotations();
  }

  void _refreshPoiAnnotations() {
    _poiManager?.deleteAll();
    _poiAnnotations.clear();
    _loadSavedPois();
  }

  void _openDirections(double lat, double lon) {
    // Try Apple Maps on iOS, falls back to Google Maps
    final appleMapsUrl = Uri.parse(
      'https://maps.apple.com/?daddr=$lat,$lon&dirflg=d',
    );
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving',
    );

    launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication).catchError(
      (_) => launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication),
    );
  }

  void _showFullPhoto(String photoPath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(child: Image.file(File(photoPath))),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}/${dt.year}';
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
    _lineEndpoints.remove(lineId);
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
                  onCameraChangeListener: _windEnabled
                      ? (_) => _syncCamera()
                      : null,
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
                      // Weather / Wind
                      _windButton(),
                      const SizedBox(height: 8),
                      // Hike tracking
                      BlocBuilder<HikeTrackCubit, HikeTrackState>(
                        builder: (context, hikeState) {
                          final isPro = context
                              .watch<SubscriptionCubit>()
                              .isPro;
                          return _hikeTrackButton(
                            isPro: isPro,
                            hikeState: hikeState,
                            onTap: () => isPro
                                ? _handleHikeButtonTap(context, hikeState)
                                : _showUpgradeSheet(context),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
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

                // Wind particle overlay
                if (_windEnabled && _windField != null)
                  WindOverlay(
                    windField: _windField!,
                    mapBearingDeg: _mapBearing,
                    zoom: _mapZoom,
                  ),

                // Bullet arc animation for active solution
                BlocBuilder<SolutionCubit, SolutionState>(
                  builder: (context, state) {
                    if (state is SolutionReady &&
                        state.lineId != null &&
                        _mapboxMap != null) {
                      final ep = _lineEndpoints[state.lineId];
                      if (ep != null) {
                        return BulletArcOverlay(
                          key: ValueKey(state.lineId),
                          mapboxMap: _mapboxMap!,
                          shooterLat: ep.sLat,
                          shooterLon: ep.sLon,
                          targetLat: ep.tLat,
                          targetLon: ep.tLon,
                          crosswindMph: state.solution.crosswindMph,
                          rangeYards: state.solution.rangeYards,
                        );
                      }
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Location-pick mode banner
                if (_windPickLocation)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 52,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.pin_drop,
                              color: Colors.black87,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Tap a location for wind',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _windPickLocation = false),
                              child: const Icon(
                                Icons.close,
                                color: Colors.black54,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Wind speed badge (top-left, below profile indicator)
                if (_windEnabled)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 52,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.rotate(
                            angle:
                                ((_windBearingDeg + 180) % 360) * pi / 180 -
                                pi / 2,
                            child: const Icon(
                              Icons.air,
                              color: Colors.white70,
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_windSpeedMph.round()} mph ${_compassLabel(_windBearingDeg)}'
                            '${_windManual ? '  ✎' : ''}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Zoom controls + compass + my location (right side)

                // Hike recording banner (top, below wind badge area)
                BlocBuilder<HikeTrackCubit, HikeTrackState>(
                  builder: (context, hikeState) {
                    if (hikeState is HikeTrackRecording ||
                        hikeState is HikeTrackPaused) {
                      final isRecording = hikeState is HikeTrackRecording;
                      final double dist;
                      final int secs;
                      if (hikeState is HikeTrackRecording) {
                        dist = hikeState.distanceMeters;
                        secs = hikeState.activeDurationSeconds;
                      } else {
                        final p = hikeState as HikeTrackPaused;
                        dist = p.distanceMeters;
                        secs = p.activeDurationSeconds;
                      }
                      final h = secs ~/ 3600;
                      final m = (secs % 3600) ~/ 60;
                      final s = secs % 60;
                      final timeStr =
                          '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
                      final distMi = dist * 0.000621371;
                      final distStr = distMi >= 0.1
                          ? '${distMi.toStringAsFixed(1)} mi'
                          : '${dist.round()} m';
                      return Positioned(
                        top:
                            MediaQuery.of(context).padding.top +
                            (_windEnabled ? 82 : 52),
                        left: 12,
                        child: GestureDetector(
                          onTap: () => _handleHikeButtonTap(context, hikeState),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isRecording
                                  ? Colors.teal.withAlpha(220)
                                  : Colors.amber.withAlpha(220),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isRecording
                                      ? Icons.fiber_manual_record
                                      : Icons.pause,
                                  color: isRecording
                                      ? Colors.redAccent
                                      : Colors.black87,
                                  size: 12,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$distStr  •  $timeStr',
                                  style: TextStyle(
                                    color: isRecording
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
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

  void _syncCamera() async {
    if (_mapboxMap == null) return;
    final cam = await _mapboxMap!.getCameraState();
    if (!mounted) return;
    setState(() {
      _mapBearing = cam.bearing;
      _mapZoom = cam.zoom;
    });
  }

  Future<void> _toggleWind() async {
    if (_windEnabled) {
      setState(() {
        _windEnabled = false;
        _windField = null;
        _windManual = false;
        _windForecastTime = null;
      });
      return;
    }
    _showWindSheet();
  }

  /// Compass cardinal/intercardinal label for a meteorological bearing.
  static String _compassLabel(double deg) => WeatherProfile.compassLabel(deg);

  /// Bottom sheet: Manual entry (free) / Now / Later / Saved (Pro).
  void _showWindSheet() {
    final isPro = context.read<SubscriptionCubit>().isPro;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Wind',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // --- Free: manual entry ---
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.orangeAccent),
                title: const Text(
                  'Enter Manually',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Type wind speed & direction for ballistics',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showManualWindEntry();
                },
              ),
              const Divider(color: Colors.white24),
              // --- Pro: live weather + animation ---
              _proListTile(
                isPro: isPro,
                icon: Icons.my_location,
                title: 'Now — Current Location',
                subtitle: 'Live wind + animation at your GPS position',
                onTap: () {
                  Navigator.pop(ctx);
                  _fetchWindNow(useGps: true);
                },
                ctx: ctx,
              ),
              _proListTile(
                isPro: isPro,
                icon: Icons.pin_drop,
                title: 'Now — Pick Location',
                subtitle: 'Tap a spot on the map',
                onTap: () {
                  Navigator.pop(ctx);
                  _startLocationPick(forecastTime: null);
                },
                ctx: ctx,
              ),
              _proListTile(
                isPro: isPro,
                icon: Icons.schedule,
                title: 'Later — Pick Time & Location',
                subtitle: 'Forecast wind at a future time',
                onTap: () {
                  Navigator.pop(ctx);
                  _pickForecastDateTime();
                },
                ctx: ctx,
              ),
              const Divider(color: Colors.white24),
              _proListTile(
                isPro: isPro,
                icon: Icons.bookmark,
                title: 'Saved Profiles',
                subtitle: 'View, apply or delete saved weather',
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openSavedWeather();
                },
                ctx: ctx,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A ListTile that is either active (Pro) or shows a lock (free).
  Widget _proListTile({
    required bool isPro,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required BuildContext ctx,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: isPro ? Colors.orangeAccent : Colors.white24),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: isPro ? Colors.white : Colors.white38),
            ),
          ),
          if (!isPro) const Icon(Icons.lock, color: Colors.white24, size: 14),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isPro ? Colors.white54 : Colors.white24,
          fontSize: 12,
        ),
      ),
      trailing: trailing,
      onTap: isPro
          ? onTap
          : () {
              Navigator.pop(ctx);
              _showUpgradeSheet(context);
            },
    );
  }

  /// Manual wind & weather entry dialog (available to all users).
  void _showManualWindEntry() {
    double speed = _windEnabled ? _windSpeedMph : 0;
    double direction = _windEnabled ? _windBearingDeg : 0;
    final speedController = TextEditingController(
      text: speed > 0 ? speed.round().toString() : '',
    );
    final dirController = TextEditingController(
      text: direction > 0 ? direction.round().toString() : '',
    );
    final tempController = TextEditingController(
      text: _manualTempF != null ? _manualTempF!.round().toString() : '',
    );
    final pressureController = TextEditingController(
      text: _manualPressureInHg != null
          ? _manualPressureInHg!.toStringAsFixed(2)
          : '',
    );
    final humidityController = TextEditingController(
      text: _manualHumidity != null ? _manualHumidity!.round().toString() : '',
    );

    showDialog<void>(
      context: context,
      builder: (ctx) {
        String? selectedCardinal;
        bool showWeather =
            _manualTempF != null ||
            _manualPressureInHg != null ||
            _manualHumidity != null;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: Colors.grey[850],
            title: const Text(
              'Enter Conditions',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: speedController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Wind Speed (mph)',
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.orangeAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: dirController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Wind FROM direction (0–360°)',
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.orangeAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in {
                        'N': 0.0,
                        'NE': 45.0,
                        'E': 90.0,
                        'SE': 135.0,
                        'S': 180.0,
                        'SW': 225.0,
                        'W': 270.0,
                        'NW': 315.0,
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.key),
                          selected: selectedCardinal == entry.key,
                          selectedColor: Colors.orangeAccent,
                          backgroundColor: Colors.grey[700],
                          labelStyle: TextStyle(
                            color: selectedCardinal == entry.key
                                ? Colors.black
                                : Colors.white70,
                            fontSize: 12,
                          ),
                          onSelected: (_) {
                            setDialogState(() {
                              selectedCardinal = entry.key;
                              dirController.text = entry.value
                                  .round()
                                  .toString();
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () =>
                        setDialogState(() => showWeather = !showWeather),
                    child: Row(
                      children: [
                        Icon(
                          showWeather ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Weather Conditions',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (showWeather) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: tempController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Temperature (°F)',
                        hintText: '59',
                        hintStyle: TextStyle(color: Colors.white24),
                        labelStyle: TextStyle(color: Colors.white54),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.orangeAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pressureController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Pressure (inHg)',
                        hintText: '29.92',
                        hintStyle: TextStyle(color: Colors.white24),
                        labelStyle: TextStyle(color: Colors.white54),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.orangeAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: humidityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Humidity (%)',
                        hintText: '50',
                        hintStyle: TextStyle(color: Colors.white24),
                        labelStyle: TextStyle(color: Colors.white54),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.orangeAccent),
                        ),
                      ),
                    ),
                  ],
                ],
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
                  final s = double.tryParse(speedController.text) ?? 0;
                  final d = double.tryParse(dirController.text) ?? 0;
                  final t = double.tryParse(tempController.text);
                  final p = double.tryParse(pressureController.text);
                  final h = double.tryParse(humidityController.text);
                  Navigator.pop(ctx);
                  _applyManualWind(
                    s,
                    d % 360,
                    tempF: t,
                    pressureInHg: p,
                    humidity: h,
                  );
                },
                child: const Text(
                  'Apply',
                  style: TextStyle(color: Colors.orangeAccent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Apply manually entered wind & weather (no animation).
  void _applyManualWind(
    double speedMph,
    double directionDeg, {
    double? tempF,
    double? pressureInHg,
    double? humidity,
  }) {
    setState(() {
      _windSpeedMph = speedMph;
      _windBearingDeg = directionDeg;
      _windEnabled = true;
      _windManual = true;
      _windField = null; // no animation for manual entry
      _manualTempF = tempF;
      _manualPressureInHg = pressureInHg;
      _manualHumidity = humidity;
    });
  }

  /// "Now — Current Location" flow: fetch weather at GPS position.
  Future<void> _fetchWindNow({
    required bool useGps,
    double? lat,
    double? lon,
  }) async {
    if (!context.read<SubscriptionCubit>().isPro) return;
    final targetLat = useGps ? _userLat : lat;
    final targetLon = useGps ? _userLon : lon;

    if (targetLat == null || targetLon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Waiting for GPS location...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _windLoading = true);
    try {
      final weather = await WeatherService().fetchWeather(targetLat, targetLon);
      if (!mounted) return;

      final speedKmh = mphToKmh(weather.windSpeedMph);
      setState(() {
        _windSpeedMph = weather.windSpeedMph;
        _windBearingDeg = weather.windDirectionDeg;
        _windField = UniformWindField(
          WindVector(speedKmh: speedKmh, bearingDeg: weather.windDirectionDeg),
        );
        _windEnabled = true;
        _windLoading = false;
        _windForecastTime = null;
      });
      _syncCamera();
      // Auto-save as a profile
      _autoSaveProfile(
        targetLat,
        targetLon,
        weather.windSpeedMph,
        weather.windDirectionDeg,
        DateTime.now(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _windLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not fetch wind data'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Fetch forecast wind for "Later" flow.
  Future<void> _fetchWindForecast(
    double lat,
    double lon,
    DateTime targetUtc,
  ) async {
    if (!context.read<SubscriptionCubit>().isPro) return;
    setState(() => _windLoading = true);
    try {
      final result = await WeatherService().fetchWindForecast(
        lat,
        lon,
        targetUtc,
      );
      if (!mounted) return;
      if (result == null) throw Exception('forecast unavailable');

      final speedKmh = mphToKmh(result.speedMph);
      setState(() {
        _windSpeedMph = result.speedMph;
        _windBearingDeg = result.directionDeg;
        _windField = UniformWindField(
          WindVector(speedKmh: speedKmh, bearingDeg: result.directionDeg),
        );
        _windEnabled = true;
        _windLoading = false;
        _windForecastTime = targetUtc;
      });
      _syncCamera();
      _autoSaveProfile(
        lat,
        lon,
        result.speedMph,
        result.directionDeg,
        targetUtc,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _windLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not fetch forecast wind data'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Apply a saved weather profile directly (offline).
  void _applyWindProfile(WeatherProfile p) {
    final speedKmh = mphToKmh(p.windSpeedMph);
    setState(() {
      _windSpeedMph = p.windSpeedMph;
      _windBearingDeg = p.windDirectionDeg;
      _windField = UniformWindField(
        WindVector(speedKmh: speedKmh, bearingDeg: p.windDirectionDeg),
      );
      _windEnabled = true;
      _windForecastTime = null;
    });
    _syncCamera();
  }

  /// Auto-save the current wind fetch as a WeatherProfile.
  Future<void> _autoSaveProfile(
    double lat,
    double lon,
    double speedMph,
    double dirDeg,
    DateTime target,
  ) async {
    final label =
        '${_compassLabel(dirDeg)} ${speedMph.round()} mph — '
        '${target.month}/${target.day} ${target.hour}:${target.minute.toString().padLeft(2, '0')}';
    final profile = WeatherProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      latitude: lat,
      longitude: lon,
      windSpeedMph: speedMph,
      windDirectionDeg: dirDeg,
      targetTime: target,
      fetchedAt: DateTime.now(),
    );
    await _weatherProfileService.save(profile);
  }

  /// Enter "pick location" mode. User taps the map to choose a wind location.
  void _startLocationPick({DateTime? forecastTime}) {
    if (!context.read<SubscriptionCubit>().isPro) return;
    setState(() {
      _windPickLocation = true;
      _windForecastTime = forecastTime;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tap a location on the map'),
        backgroundColor: Colors.orangeAccent,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Handle a map tap when in location-pick mode.
  void _handleWindLocationPick(double lat, double lon) {
    setState(() => _windPickLocation = false);
    if (_windForecastTime != null) {
      _fetchWindForecast(lat, lon, _windForecastTime!);
    } else {
      _fetchWindNow(useGps: false, lat: lat, lon: lon);
    }
  }

  /// Pick a future date + time for the "Later" flow.
  Future<void> _pickForecastDateTime() async {
    if (!context.read<SubscriptionCubit>().isPro) return;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.orangeAccent,
            surface: Color(0xFF1E1E1E),
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.orangeAccent,
            surface: Color(0xFF1E1E1E),
          ),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final target = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    _startLocationPick(forecastTime: target);
  }

  Widget _windButton() {
    // Wind blows FROM _windBearingDeg; icon should point the direction the
    // wind is going TOWARDS. Convert geographic bearing to screen rotation:
    // geographic 0° = north (up), but Transform.rotate 0 = right, so subtract π/2.
    final towardsDeg = (_windBearingDeg + 180) % 360;
    final iconAngleRad = _windEnabled ? towardsDeg * pi / 180 - pi / 2 : 0.0;

    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: 'wind',
        mini: true,
        backgroundColor: _windEnabled ? Colors.orangeAccent : Colors.black87,
        onPressed: _toggleWind,
        child: _windLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.orangeAccent,
                ),
              )
            : Transform.rotate(
                angle: iconAngleRad,
                child: Icon(
                  Icons.air,
                  color: _windEnabled ? Colors.black : Colors.white,
                  size: 20,
                ),
              ),
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

  void _openSavedWeather() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SavedWeatherScreen(onApply: (p) => _applyWindProfile(p)),
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

  void _openSavedHikeTracks(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route is! PopupRoute);
    Navigator.of(this.context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: this.context.read<HikeTrackCubit>(),
          child: const SavedHikeTracksScreen(),
        ),
      ),
    );
  }

  // ── Hike tracking UI helpers ──────────────────────────────────────

  Widget _hikeTrackButton({
    required bool isPro,
    required HikeTrackState hikeState,
    required VoidCallback onTap,
  }) {
    final isRecording = hikeState is HikeTrackRecording;
    final isPaused = hikeState is HikeTrackPaused;
    final isActive = isRecording || isPaused;

    Color bgColor;
    if (!isPro) {
      bgColor = Colors.grey[800]!;
    } else if (isRecording) {
      bgColor = Colors.teal;
    } else if (isPaused) {
      bgColor = Colors.amber;
    } else {
      bgColor = Colors.black87;
    }

    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: 'hike_track',
        mini: true,
        backgroundColor: bgColor,
        onPressed: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.directions_walk,
              color: isActive
                  ? Colors.white
                  : (isPro ? Colors.teal : Colors.white38),
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

  void _handleHikeButtonTap(BuildContext context, HikeTrackState hikeState) {
    final cubit = context.read<HikeTrackCubit>();

    if (hikeState is HikeTrackIdle || hikeState is HikeTrackError) {
      _showHikeStartConfirm(context, cubit);
      return;
    }

    if (hikeState is HikeTrackRecording) {
      _showHikeControlSheet(
        context,
        isRecording: true,
        onPause: cubit.pause,
        onStop: cubit.stop,
      );
      return;
    }

    if (hikeState is HikeTrackPaused) {
      _showHikeControlSheet(
        context,
        isRecording: false,
        onResume: cubit.resume,
        onStop: cubit.stop,
        onDiscard: () {
          cubit.discard();
          Navigator.pop(context);
        },
      );
      return;
    }
  }

  void _showHikeStartConfirm(BuildContext context, HikeTrackCubit cubit) {
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
                'Start Hike?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'GPS tracking will begin in the background.',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 20),
              _hikeActionTile(
                icon: Icons.play_arrow,
                label: 'Start Tracking',
                color: Colors.teal,
                onTap: () {
                  Navigator.pop(ctx);
                  cubit.start();
                },
              ),
              const SizedBox(height: 8),
              _hikeActionTile(
                icon: Icons.close,
                label: 'Cancel',
                color: Colors.white38,
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHikeControlSheet(
    BuildContext context, {
    required bool isRecording,
    VoidCallback? onPause,
    VoidCallback? onResume,
    required VoidCallback onStop,
    VoidCallback? onDiscard,
  }) {
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
              Text(
                isRecording ? 'Recording Hike' : 'Hike Paused',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              if (isRecording && onPause != null)
                _hikeActionTile(
                  icon: Icons.pause,
                  label: 'Pause',
                  color: Colors.amber,
                  onTap: () {
                    Navigator.pop(ctx);
                    onPause();
                  },
                ),
              if (!isRecording && onResume != null)
                _hikeActionTile(
                  icon: Icons.play_arrow,
                  label: 'Resume',
                  color: Colors.teal,
                  onTap: () {
                    Navigator.pop(ctx);
                    onResume();
                  },
                ),
              const SizedBox(height: 8),
              _hikeActionTile(
                icon: Icons.stop,
                label: 'End',
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  onStop();
                },
              ),
              if (onDiscard != null) ...[
                const SizedBox(height: 8),
                _hikeActionTile(
                  icon: Icons.delete_outline,
                  label: 'Discard',
                  color: Colors.white38,
                  onTap: onDiscard,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hikeActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: Colors.grey[800],
    );
  }

  void _openHikeSummary(HikeTrack track, {bool viewOnly = false}) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => HikeSummaryScreen(
              track: track,
              viewOnly: viewOnly,
              onSave: viewOnly
                  ? null
                  : (name) async {
                      await context.read<HikeTrackCubit>().save(name);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Hike saved'),
                            backgroundColor: Colors.teal,
                          ),
                        );
                      }
                    },
              onDiscard: viewOnly
                  ? null
                  : () {
                      context.read<HikeTrackCubit>().discard();
                    },
              onRename: viewOnly
                  ? (name) async {
                      await context.read<HikeTrackCubit>().renameSaved(
                        track.id,
                        name,
                      );
                    }
                  : null,
            ),
          ),
        )
        .then((_) {
          // When returning from the summary, clear the viewed track if in view mode
          if (viewOnly && mounted) {
            context.read<HikeTrackCubit>().clear();
          }
        });
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
                leading: const Icon(Icons.air, color: Colors.blue),
                title: const Text(
                  'Weather Profiles',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () {
                  Navigator.of(
                    ctx,
                    rootNavigator: true,
                  ).popUntil((route) => route is! PopupRoute);
                  _openSavedWeather();
                },
              ),
              ListTile(
                leading: const Icon(Icons.directions_walk, color: Colors.teal),
                title: const Text(
                  'Hike Tracks',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () => _openSavedHikeTracks(ctx),
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
