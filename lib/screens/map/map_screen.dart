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
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    hide Size, ImageSource;
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../blocs/hike_track_cubit.dart';
import '../../blocs/profile_cubit.dart';
import '../../blocs/solution_cubit.dart';
import '../../blocs/subscription_cubit.dart';
import '../../blocs/plant_cubit.dart';
import '../../blocs/track_cubit.dart';
import '../../blocs/shotgun_pattern_cubit.dart';
import '../../models/hike_track.dart';
import '../../models/pattern_result.dart';
import '../../models/plant_result.dart';
import '../../models/poi.dart';
import '../../models/rifle_profile.dart';
import '../../models/shotgun_setup.dart';
import '../../models/weapon_profile.dart';
import '../../models/saved_line.dart';
import '../../models/shot_solution.dart';
import '../../models/track_result.dart';
import '../../models/weather_data.dart';
import '../../ballistics/conversions.dart';
import '../../models/weather_profile.dart';
import '../../models/wind_data.dart';
import '../../services/ad_service.dart';
import '../../services/line_service.dart';
import '../../services/poi_service.dart';
import '../../services/profile_service.dart';
import '../../services/weather_profile_service.dart';
import '../../services/weather_service.dart';
import '../../ballistics/shotgun_ballistics.dart';
import '../../widgets/bullet_arc_overlay.dart';
import '../../widgets/compass_overlay.dart';
import '../../widgets/lethal_range_overlay.dart';
import '../../widgets/pattern_card.dart';
import '../../widgets/pellet_spray_overlay.dart';
import '../../widgets/solution_card.dart';
import '../../widgets/spread_cone_overlay.dart';
import '../../widgets/wind_overlay.dart';
import '../plant_result_screen.dart';
import '../pattern_result_screen.dart';
import '../hike_summary_screen.dart';
import '../profile_list_screen.dart';
import '../saved_hike_tracks_screen.dart';
import '../saved_plants_screen.dart';
import '../saved_tracks_screen.dart';
import '../offline_regions_screen.dart';
import '../saved_weather_screen.dart';
import '../track_result_screen.dart';

part '_weather.dart';
part '_hiking.dart';
part '_track_id.dart';
part '_plant_id.dart';
part '_poi.dart';
part '_land_overlay.dart';
part '_setback_overlay.dart';
part '_terrain.dart';

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
  final Map<String, ({PatternResult result, ShotgunSetup setup})>
  _linePatterns = {};
  final Map<String, _AnnotationGroup> _annotationGroups = {};
  final Map<String, String> _labelToLine = {}; // label annot ID → line annot ID
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
  final LineService _lineService = LineService();
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

  // ── 3D terrain state ──────────────────────────────────────────────
  bool _is3DEnabled = false;
  double _elevationExaggeration = 1.5;

  // ── Land overlay state ────────────────────────────────────────────
  bool _landOverlayEnabled = false;
  Set<String> _landOverlayFilters = _MapScreenLandOverlay
      .allManagerCategories
      .keys
      .toSet();

  // ── Setback overlay state ─────────────────────────────────────────
  bool _setbackOverlayEnabled = false;

  // ── Manual location override ──────────────────────────────────────
  bool _locationOverride = false;
  bool _locationPickMode = false;
  double? _overrideLat;
  double? _overrideLon;
  PointAnnotation? _overridePin;

  double? get _effectiveLat => _locationOverride ? _overrideLat : _userLat;
  double? get _effectiveLon => _locationOverride ? _overrideLon : _userLon;

  // ── Hike tracking state ───────────────────────────────────────────
  bool _hikeTrackLayerReady = false; // true once GeoJSON source + layers exist
  StreamSubscription<HikeTrackState>? _hikeTrackSub;
  StreamSubscription<ProfileState>? _profileSub;
  StreamSubscription<ShotgunPatternState>? _patternSub;

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
          // First position from stream → mark ready & fly
          if (!_locationReady) {
            setState(() => _locationReady = true);
            _flyToUser();
          }
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
    // Adjust zoom when profile loads/changes (shotgun → closer)
    // Also swap visible lines to match the new profile.
    String? lastProfileId;
    _profileSub = context.read<ProfileCubit>().stream.listen((state) {
      if (!mounted || _mapboxMap == null) return;
      if (state is ProfileLoaded) {
        _adjustZoomForProfile(state.profile);
        // Only clear & reload lines when switching to a different profile.
        if (state.profile.id != lastProfileId) {
          lastProfileId = state.profile.id;
          _clearAllLines();
          _loadSavedLines(profileId: state.profile.id);
        }
      }
    });
    // Keep _linePatterns in sync when pattern result screen re-predicts.
    _patternSub = context.read<ShotgunPatternCubit>().stream.listen((state) {
      if (!mounted) return;
      if (state is PatternReady &&
          state.lineId != null &&
          _linePatterns.containsKey(state.lineId)) {
        _linePatterns[state.lineId!] = (
          result: state.result,
          setup: state.setup,
        );
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
    _patternSub?.cancel();
    _profileSub?.cancel();
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
          if (mounted) setState(() {});
        },
        onAdFailedToLoad: (ad, error) {
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

    // getCurrentPosition can be slow (10+ s on iOS waiting for GPS lock).
    // The position stream already triggers the initial fly on the first
    // emission, so we only use this as a fallback for a more accurate fix.
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );
      if (mounted) {
        _userLat = pos.latitude;
        _userLon = pos.longitude;
        if (!_locationReady) {
          setState(() => _locationReady = true);
          _flyToUser();
        }
      }
    } catch (_) {
      // Stream-based fallback handles the initial fly.
    }
  }

  Future<void> _flyToUser() async {
    final lat = _effectiveLat;
    final lon = _effectiveLon;
    if (_mapboxMap == null || lat == null || lon == null) return;
    final ps = context.read<ProfileCubit>().state;
    final isShotgun = ps is ProfileLoaded && ps.profile is ShotgunSetup;
    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(lon, lat)),
        zoom: isShotgun ? 17.0 : 15.0,
        bearing: _compassEnabled && _heading != null ? _heading! : null,
      ),
      MapAnimationOptions(duration: 1500),
    );
  }

  /// Adjust zoom when the active profile changes (shotgun needs closer view).
  Future<void> _adjustZoomForProfile(WeaponProfile profile) async {
    if (_mapboxMap == null || !_locationReady) return;
    final cam = await _mapboxMap!.getCameraState();
    if (profile.weaponType == WeaponType.shotgun && cam.zoom < 16) {
      await _mapboxMap!.flyTo(
        CameraOptions(zoom: 17.0),
        MapAnimationOptions(duration: 600),
      );
    } else if (profile.weaponType == WeaponType.rifle && cam.zoom >= 16.5) {
      await _mapboxMap!.flyTo(
        CameraOptions(zoom: 15.0),
        MapAnimationOptions(duration: 600),
      );
    }
  }

  void _handleMyLocationTap() {
    if (_locationOverride) {
      if (_overridePin != null) {
        _annotationManager?.delete(_overridePin!);
        _overridePin = null;
      }
      setState(() {
        _locationOverride = false;
        _overrideLat = null;
        _overrideLon = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS location restored'),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 2),
        ),
      );
      _flyToUser();
    } else {
      _flyToUser();
    }
  }

  void _handleMyLocationLongPress() {
    setState(() => _locationPickMode = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tap a location on the map to set your position'),
        backgroundColor: Colors.orangeAccent,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _handleLocationOverridePick(double lat, double lon) async {
    // Remove previous override pin if any
    if (_overridePin != null) {
      _annotationManager?.delete(_overridePin!);
      _overridePin = null;
    }
    setState(() {
      _locationPickMode = false;
      _locationOverride = true;
      _overrideLat = lat;
      _overrideLon = lon;
    });
    // Drop a pin at the override location
    _overridePin = await _annotationManager?.create(
      PointAnnotationOptions(
        geometry: Point(coordinates: Position(lon, lat)),
        iconImage: 'override-location',
        iconSize: 0.8,
        iconAnchor: IconAnchor.CENTER,
      ),
    );
    _flyToUser();
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
          return;
        }
        final pattern = _linePatterns[annotation.id];
        final ep = _lineEndpoints[annotation.id];
        if (pattern != null && ep != null) {
          context.read<ShotgunPatternCubit>().show(
            pattern.result,
            setup: pattern.setup,
            shooterLat: ep.sLat,
            shooterLon: ep.sLon,
            targetLat: ep.tLat,
            targetLon: ep.tLon,
            lineId: annotation.id,
          );
        }
      },
    );
    _labelManager?.tapEvents(
      onTap: (annotation) {
        if (!mounted) return;
        final lineId = _labelToLine[annotation.id];
        if (lineId == null) return;
        _lineTapped = true;
        final solution = _lineSolutions[lineId];
        if (solution != null) {
          context.read<SolutionCubit>().show(solution, lineId: lineId);
          return;
        }
        final pattern = _linePatterns[lineId];
        final ep = _lineEndpoints[lineId];
        if (pattern != null && ep != null) {
          context.read<ShotgunPatternCubit>().show(
            pattern.result,
            setup: pattern.setup,
            shooterLat: ep.sLat,
            shooterLon: ep.sLon,
            targetLat: ep.tLat,
            targetLon: ep.tLon,
            lineId: lineId,
          );
        }
      },
    );

    // If location already arrived before map was created, fly now
    if (_locationReady) _flyToUser();

    // Register custom POI pin images
    await _registerPoiIcons();

    // Register custom override-location pin
    await _registerOverrideLocationIcon();

    // Load saved POIs
    await _loadSavedPois();

    // Load saved lines for the active profile
    if (!mounted) return;
    final ps = context.read<ProfileCubit>().state;
    if (ps is ProfileLoaded) {
      await _loadSavedLines(profileId: ps.profile.id);
    }
  }

  Future<void> _registerOverrideLocationIcon() async {
    const double s = 96;
    const int size = 96;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, s, s));
    const double cx = s / 2;
    const double cy = s / 2;
    const double radius = 40;

    // Outer circle fill
    canvas.drawCircle(
      const Offset(cx, cy),
      radius,
      Paint()..color = Colors.orangeAccent,
    );

    // Outer circle stroke
    canvas.drawCircle(
      const Offset(cx, cy),
      radius,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Crosshair icon inside circle
    const icon = Icons.my_location;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 40,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    await _mapboxMap!.style.addStyleImage(
      'override-location',
      2.0,
      MbxImage(width: size, height: size, data: byteData!.buffer.asUint8List()),
      false,
      [],
      [],
      null,
    );
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
          content: Text('Create a profile first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Shotgun profiles → compute pattern, drop pin & line like rifle
    if (profileState.profile is ShotgunSetup) {
      final shooterLat = _effectiveLat;
      final shooterLon = _effectiveLon;
      if (shooterLat == null || shooterLon == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Waiting for GPS location...'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final setup = profileState.profile as ShotgunSetup;
      final distYds = haversineYards(shooterLat, shooterLon, lat, lon);
      final cubit = context.read<ShotgunPatternCubit>();

      // Drop pin at target
      final pin = await _annotationManager?.create(
        PointAnnotationOptions(
          geometry: point,
          iconSize: 1.5,
          iconImage: 'marker-15',
        ),
      );

      // Draw orange line from shooter to target
      final line = await _lineManager?.create(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: [Position(shooterLon, shooterLat), Position(lon, lat)],
          ),
          lineColor: Colors.orangeAccent.toARGB32(),
          lineWidth: 4.0,
        ),
      );

      // Compute pattern
      cubit.predict(
        setup: setup,
        distanceYards: distYds,
        shooterLat: shooterLat,
        shooterLon: shooterLon,
        targetLat: lat,
        targetLon: lon,
        lineId: line?.id,
      );

      // Store results when ready
      if (line != null) {
        final midLat = (shooterLat + lat) / 2;
        final midLon = (shooterLon + lon) / 2;
        late final StreamSubscription<ShotgunPatternState> sub;
        sub = cubit.stream.listen((state) {
          if (state is PatternReady) {
            _linePatterns[line.id] = (result: state.result, setup: setup);
            final r = state.result;
            final label =
                '${r.distanceYards.round()} yd / ${r.spreadDiameterInches.toStringAsFixed(0)}" spread';
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
                  _labelToLine[labelAnnotation.id] = line.id;
                  _lineEndpoints[line.id] = (
                    sLat: shooterLat,
                    sLon: shooterLon,
                    tLat: lat,
                    tLon: lon,
                  );
                });
            _lineService.save(
              SavedLine(
                id: line.id,
                type: SavedLineType.shotgun,
                profileId: setup.id,
                shooterLat: shooterLat,
                shooterLon: shooterLon,
                targetLat: lat,
                targetLon: lon,
                pattern: state.result,
              ),
            );
            sub.cancel();
          } else if (state is PatternError) {
            sub.cancel();
          }
        });
      }
      return;
    }

    // Check we have user location
    final shooterLat = _effectiveLat;
    final shooterLon = _effectiveLon;
    if (shooterLat == null || shooterLon == null) {
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
          coordinates: [Position(shooterLon, shooterLat), Position(lon, lat)],
        ),
        lineColor: Colors.red.toARGB32(),
        lineWidth: 6.0,
      ),
    );

    // Compute solution
    if (!mounted) return;
    final isPro = context.read<SubscriptionCubit>().isPro;
    final hasManualWeather =
        _manualTempF != null ||
        _manualPressureInHg != null ||
        _manualHumidity != null;
    cubit.compute(
      profile: profileState.profile as RifleProfile,
      shooterLat: shooterLat,
      shooterLon: shooterLon,
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
      final midLat = (shooterLat + lat) / 2;
      final midLon = (shooterLon + lon) / 2;
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
                _labelToLine[labelAnnotation.id] = line.id;
                _lineEndpoints[line.id] = (
                  sLat: shooterLat,
                  sLon: shooterLon,
                  tLat: lat,
                  tLon: lon,
                );
              });
          _lineService.save(
            SavedLine(
              id: line.id,
              type: SavedLineType.rifle,
              profileId: profileState.profile.id,
              shooterLat: shooterLat,
              shooterLon: shooterLon,
              targetLat: lat,
              targetLon: lon,
              solution: state.solution,
            ),
          );
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

    // Intercept tap for manual location override picking
    if (_locationPickMode) {
      _handleLocationOverridePick(lat, lon);
      return;
    }

    // Intercept tap for wind location picking
    if (_windPickLocation) {
      _handleWindLocationPick(lat, lon);
      return;
    }

    _showPoiTypePicker(lat, lon);
  }

  void _deleteEntry(String lineId) {
    final group = _annotationGroups.remove(lineId);
    if (group != null) {
      _lineManager?.delete(group.line);
      if (group.pin != null) _annotationManager?.delete(group.pin!);
      _labelToLine.remove(group.label.id);
      _labelManager?.delete(group.label);
    }
    _lineSolutions.remove(lineId);
    _linePatterns.remove(lineId);
    _lineEndpoints.remove(lineId);
    _lineService.delete(lineId);
    context.read<SolutionCubit>().clear();
    context.read<ShotgunPatternCubit>().clear();
  }

  void _clearAllLines() {
    for (final group in _annotationGroups.values) {
      _lineManager?.delete(group.line);
      if (group.pin != null) _annotationManager?.delete(group.pin!);
      _labelToLine.remove(group.label.id);
      _labelManager?.delete(group.label);
    }
    _annotationGroups.clear();
    _labelToLine.clear();
    _lineSolutions.clear();
    _linePatterns.clear();
    _lineEndpoints.clear();
    context.read<SolutionCubit>().clear();
    context.read<ShotgunPatternCubit>().clear();
  }

  Future<void> _loadSavedLines({required String profileId}) async {
    final allLines = await _lineService.loadAll();
    final lines = allLines.where((l) => l.profileId == profileId).toList();
    // Load all profiles so we can look up shotgun setups by ID
    final allProfiles = await ProfileService().loadProfiles();
    final setupById = <String, ShotgunSetup>{};
    for (final p in allProfiles) {
      if (p is ShotgunSetup) setupById[p.id] = p;
    }
    for (final saved in lines) {
      // Draw pin at target
      final pin = await _annotationManager?.create(
        PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(saved.targetLon, saved.targetLat),
          ),
          iconSize: 1.5,
          iconImage: 'marker-15',
        ),
      );

      // Draw line from shooter to target
      final isShotgun = saved.type == SavedLineType.shotgun;
      final line = await _lineManager?.create(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: [
              Position(saved.shooterLon, saved.shooterLat),
              Position(saved.targetLon, saved.targetLat),
            ],
          ),
          lineColor: isShotgun
              ? Colors.orangeAccent.toARGB32()
              : Colors.red.toARGB32(),
          lineWidth: isShotgun ? 4.0 : 6.0,
        ),
      );
      if (line == null) continue;

      // Build label text
      final String label;
      if (isShotgun && saved.pattern != null) {
        final r = saved.pattern!;
        label =
            '${r.distanceYards.round()} yd / ${r.spreadDiameterInches.toStringAsFixed(0)}" spread';
      } else if (saved.solution != null) {
        final s = saved.solution!;
        label =
            '${s.rangeYards.round()} / ${s.dropMoa.abs().toStringAsFixed(1)} / ${s.windDriftMoa.abs().toStringAsFixed(1)}';
      } else {
        continue;
      }

      final midLat = (saved.shooterLat + saved.targetLat) / 2;
      final midLon = (saved.shooterLon + saved.targetLon) / 2;
      final labelAnnotation = await _labelManager?.create(
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
      );
      if (labelAnnotation == null) continue;

      _annotationGroups[line.id] = _AnnotationGroup(
        line: line,
        pin: pin,
        label: labelAnnotation,
      );
      _labelToLine[labelAnnotation.id] = line.id;
      _lineEndpoints[line.id] = (
        sLat: saved.shooterLat,
        sLon: saved.shooterLon,
        tLat: saved.targetLat,
        tLon: saved.targetLon,
      );

      if (saved.solution != null) {
        _lineSolutions[line.id] = saved.solution!;
      }
      if (saved.pattern != null) {
        final setup = setupById[saved.profileId];
        if (setup != null) {
          _linePatterns[line.id] = (result: saved.pattern!, setup: setup);
        }
      }

      // Remap the Hive-persisted ID → the new Mapbox annotation ID
      if (saved.id != line.id) {
        await _lineService.delete(saved.id);
        await _lineService.save(
          SavedLine(
            id: line.id,
            type: saved.type,
            profileId: saved.profileId,
            shooterLat: saved.shooterLat,
            shooterLon: saved.shooterLon,
            targetLat: saved.targetLat,
            targetLon: saved.targetLon,
            solution: saved.solution,
            pattern: saved.pattern,
            createdAt: saved.createdAt,
          ),
        );
      }
    }
  }

  void _openProfileScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: context.read<ProfileCubit>()),
              BlocProvider.value(value: context.read<SubscriptionCubit>()),
              BlocProvider.value(value: context.read<ShotgunPatternCubit>()),
            ],
            child: const ProfileListScreen(),
          );
        },
      ),
    );
    if (!mounted || _mapboxMap == null) return;
    final ps = context.read<ProfileCubit>().state;
    if (ps is ProfileLoaded && ps.profile is ShotgunSetup) {
      final cam = await _mapboxMap!.getCameraState();
      if (cam.zoom < 16) {
        await _mapboxMap!.flyTo(
          CameraOptions(zoom: 17.0),
          MapAnimationOptions(duration: 600),
        );
      }
    }
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

  Widget _myLocationButton() {
    return SizedBox(
      width: 44,
      height: 44,
      child: GestureDetector(
        onLongPress: _handleMyLocationLongPress,
        child: FloatingActionButton(
          heroTag: 'my_location',
          mini: true,
          backgroundColor: _locationOverride
              ? Colors.orangeAccent
              : Colors.black87,
          onPressed: _handleMyLocationTap,
          child: Icon(
            _locationOverride ? Icons.edit_location_alt : Icons.my_location,
            color: _locationOverride ? Colors.black : Colors.white,
            size: 20,
          ),
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
                'Upgrade to Atlix Pro',
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
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.download, color: Colors.white70),
                title: const Text(
                  'Offline Maps',
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
                  _openOfflineRegions();
                },
              ),
            ],
          ),
        ),
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
                    center: Point(coordinates: Position(-98.5795, 39.8283)),
                    zoom: 4.0,
                  ),
                  styleUri: MapboxStyles.SATELLITE_STREETS,
                  onMapCreated: _onMapCreated,
                  onTapListener: _onMapTap,
                  onLongTapListener: _onMapLongTap,
                  onCameraChangeListener: (_windEnabled || _is3DEnabled)
                      ? (_) => _syncCamera()
                      : null,
                ),

                // Profile indicator (top left) — tappable when profiles exist
                Positioned(
                  top: MediaQuery.of(context).padding.top + 32,
                  left: 12,
                  child: BlocBuilder<ProfileCubit, ProfileState>(
                    builder: (context, state) {
                      final hasProfile = state is ProfileLoaded;
                      final maxW = MediaQuery.sizeOf(context).width * 0.42;
                      return GestureDetector(
                        onTap: _openProfileScreen,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxW),
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
                                Flexible(
                                  child: Text(
                                    hasProfile
                                        ? state.profile.name
                                        : 'Create Profile',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
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
                        ),
                      );
                    },
                  ),
                ),

                // ID buttons + history (left side)
                Positioned(
                  left: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 5,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Land overlay
                      Builder(
                        builder: (context) {
                          final isPro = context
                              .watch<SubscriptionCubit>()
                              .isPro;
                          return _landOverlayButton(isPro: isPro);
                        },
                      ),
                      const SizedBox(height: 8),
                      // Setback (no-hunt zone) overlay
                      Builder(
                        builder: (context) {
                          final isPro = context
                              .watch<SubscriptionCubit>()
                              .isPro;
                          return _setbackOverlayButton(isPro: isPro);
                        },
                      ),
                      const SizedBox(height: 8),
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

                // Shotgun lethal range circle (always visible with shotgun profile)
                BlocBuilder<ProfileCubit, ProfileState>(
                  builder: (context, profileState) {
                    if (profileState is ProfileLoaded &&
                        profileState.profile is ShotgunSetup &&
                        _effectiveLat != null &&
                        _mapboxMap != null) {
                      final sg = profileState.profile as ShotgunSetup;
                      return LethalRangeOverlay(
                        mapboxMap: _mapboxMap!,
                        centerLat: _effectiveLat!,
                        centerLon: _effectiveLon!,
                        rangeYards: ShotgunBallistics.effectiveRangeYards(sg),
                        gameLabel: sg.gameTarget.label,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Shotgun spread cone overlay + pellet spray
                BlocBuilder<ShotgunPatternCubit, ShotgunPatternState>(
                  builder: (context, state) {
                    if (state is PatternReady &&
                        state.shooterLat != null &&
                        _mapboxMap != null) {
                      return Stack(
                        children: [
                          // Spread cone (colour zones)
                          SpreadConeOverlay(
                            mapboxMap: _mapboxMap!,
                            shooterLat: state.shooterLat!,
                            shooterLon: state.shooterLon!,
                            targetLat: state.targetLat!,
                            targetLon: state.targetLon!,
                            result: state.result,
                          ),
                          // Animated pellet spray
                          PelletSprayOverlay(
                            key: ValueKey(
                              'spray_${state.result.distanceYards}',
                            ),
                            mapboxMap: _mapboxMap!,
                            shooterLat: state.shooterLat!,
                            shooterLon: state.shooterLon!,
                            targetLat: state.targetLat!,
                            targetLon: state.targetLon!,
                            pelletCount: state.setup.pelletCount,
                            spreadDiameterInches:
                                state.result.spreadDiameterInches,
                            distanceYards: state.result.distanceYards,
                          ),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Location override pick-mode banner
                if (_locationPickMode)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 82,
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
                              Icons.edit_location_alt,
                              color: Colors.black87,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Tap to set your location',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _locationPickMode = false),
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

                // Wind location-pick mode banner
                if (_windPickLocation)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 82,
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

                // Badge queue (top-right, stacking)
                BlocBuilder<HikeTrackCubit, HikeTrackState>(
                  builder: (context, hikeState) {
                    final hikeActive =
                        hikeState is HikeTrackRecording ||
                        hikeState is HikeTrackPaused;
                    return Positioned(
                      top: MediaQuery.of(context).padding.top + 0,
                      right: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Wind badge
                          if (_windEnabled) ...[
                            Container(
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
                                        ((_windBearingDeg + 180) % 360) *
                                            pi /
                                            180 -
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
                            const SizedBox(height: 6),
                          ],
                          // Hike tracking badge
                          if (hikeActive) ...[
                            Builder(
                              builder: (context) {
                                final isRecording =
                                    hikeState is HikeTrackRecording;
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
                                return GestureDetector(
                                  onTap: () =>
                                      _handleHikeButtonTap(context, hikeState),
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
                                );
                              },
                            ),
                            const SizedBox(height: 6),
                          ],
                          // Manual location badge
                          if (_locationOverride && !_locationPickMode)
                            GestureDetector(
                              onTap: _handleMyLocationTap,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.edit_location_alt,
                                      color: Colors.black87,
                                      size: 14,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Manual location',
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),

                Positioned(
                  right: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 5,
                  child: Column(
                    children: [
                      _terrainButton(),
                      const SizedBox(height: 8),
                      _compassButton(),
                      const SizedBox(height: 8),
                      _myLocationButton(),
                      const SizedBox(height: 8),
                      _mapButton(Icons.add, _zoomIn),
                      const SizedBox(height: 8),
                      _mapButton(Icons.remove, _zoomOut),
                    ],
                  ),
                ),

                // Elevation exaggeration slider (3D mode only)
                if (_is3DEnabled)
                  Positioned(
                    right: 12,
                    bottom:
                        MediaQuery.of(context).padding.bottom +
                        5 +
                        // offset above the right sidebar buttons:
                        // 5 buttons × 44px + 4 gaps × 8px = 252px
                        252 +
                        12,
                    child: _exaggerationSlider(),
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

                // Shotgun pattern card (bottom sheet)
                BlocBuilder<ShotgunPatternCubit, ShotgunPatternState>(
                  builder: (context, state) {
                    if (state is PatternReady) {
                      return Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _DismissiblePatternCard(
                          result: state.result,
                          setup: state.setup,
                          onDismiss: () =>
                              context.read<ShotgunPatternCubit>().clear(),
                          onDelete: state.lineId != null
                              ? () => _deleteEntry(state.lineId!)
                              : null,
                        ),
                      );
                    }
                    if (state is PatternError) {
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

/// Wraps the pattern card with swipe-to-dismiss and an expand-to-full-view button.
class _DismissiblePatternCard extends StatefulWidget {
  final PatternResult result;
  final ShotgunSetup setup;
  final VoidCallback onDismiss;
  final VoidCallback? onDelete;

  const _DismissiblePatternCard({
    required this.result,
    required this.setup,
    required this.onDismiss,
    this.onDelete,
  });

  @override
  State<_DismissiblePatternCard> createState() =>
      _DismissiblePatternCardState();
}

class _DismissiblePatternCardState extends State<_DismissiblePatternCard> {
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
        child: PatternCard(
          result: widget.result,
          onDismiss: widget.onDismiss,
          onDelete: widget.onDelete,
          onExpand: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MultiBlocProvider(
                  providers: [
                    BlocProvider.value(
                      value: context.read<ShotgunPatternCubit>(),
                    ),
                    BlocProvider.value(
                      value: context.read<SubscriptionCubit>(),
                    ),
                  ],
                  child: PatternResultScreen(
                    initialResult: widget.result,
                    setup: widget.setup,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
