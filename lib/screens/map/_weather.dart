part of 'map_screen.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

/// Compass cardinal/intercardinal label for a meteorological bearing.
String _compassLabel(double deg) => WeatherProfile.compassLabel(deg);

/// Wind / weather methods for [_MapScreenState].
extension _MapScreenWeather on _MapScreenState {
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
    final targetLat = useGps ? _effectiveLat : lat;
    final targetLon = useGps ? _effectiveLon : lon;

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

  void _openSavedWeather() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SavedWeatherScreen(onApply: (p) => _applyWindProfile(p)),
      ),
    );
  }
}
