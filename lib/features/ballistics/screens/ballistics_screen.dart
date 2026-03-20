import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monyx/../core/theme/app_theme.dart';
import 'package:monyx/../core/utils/geo_utils.dart';
import 'package:monyx/map/providers/map_provider.dart';
import 'package:monyx/profiles/providers/profile_provider.dart';
import 'package:monyx/weather/providers/weather_provider.dart';
import 'package:monyx/features/ballistics/models/ballistic_input.dart';
import 'package:monyx/features/ballistics/providers/ballistics_provider.dart';
import 'package:monyx/features/ballistics/widgets/solution_card.dart';

class BallisticsScreen extends ConsumerStatefulWidget {
  const BallisticsScreen({super.key});

  @override
  ConsumerState<BallisticsScreen> createState() => _BallisticsScreenState();
}

class _BallisticsScreenState extends ConsumerState<BallisticsScreen> {
  // Manual overrides
  final _windSpeedCtrl = TextEditingController();
  final _windDirCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  final _pressCtrl = TextEditingController();
  bool _showRangeCard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCompute());
  }

  @override
  void dispose() {
    _windSpeedCtrl.dispose();
    _windDirCtrl.dispose();
    _tempCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
  }

  void _autoCompute() {
    ref.read(ballisticsProvider.notifier).compute();
  }

  void _applyOverrides() {
    final notifier = ref.read(ballisticsProvider.notifier);
    notifier.updateWeather(
      windSpeedMph:
          _windSpeedCtrl.text.isNotEmpty
              ? double.tryParse(_windSpeedCtrl.text)
              : null,
      windDirectionDeg:
          _windDirCtrl.text.isNotEmpty
              ? double.tryParse(_windDirCtrl.text)
              : null,
      temperatureF:
          _tempCtrl.text.isNotEmpty ? double.tryParse(_tempCtrl.text) : null,
      pressureInHg:
          _pressCtrl.text.isNotEmpty ? double.tryParse(_pressCtrl.text) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ballisticsState = ref.watch(ballisticsProvider);
    final input = ref.watch(ballisticInputProvider);
    final activeProfile = ref.watch(activeRifleProfileProvider);
    final mapState = ref.watch(mapStateProvider);
    final selectedPin = mapState.selectedPin;

    // Fill weather fields from live data when first rendered
    final weatherAsync =
        mapState.hasLocation
            ? ref.watch(
              weatherProvider(
                LatLon(
                  lat: mapState.userLatitude!,
                  lon: mapState.userLongitude!,
                ),
              ),
            )
            : null;
    if (_windSpeedCtrl.text.isEmpty && weatherAsync?.valueOrNull != null) {
      final w = weatherAsync!.valueOrNull!;
      _windSpeedCtrl.text =
          GeoUtils.msToMph(w.windSpeedMs).toStringAsFixed(1);
      _windDirCtrl.text = w.windDirectionDeg.toStringAsFixed(0);
      _tempCtrl.text =
          GeoUtils.celsiusToFahrenheit(w.temperatureCelsius).toStringAsFixed(1);
      _pressCtrl.text =
          (w.pressureHpa * 0.02952998).toStringAsFixed(2);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ballistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recalculate',
            onPressed: _autoCompute,
          ),
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'Range card',
            onPressed:
                () => setState(() => _showRangeCard = !_showRangeCard),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Target info ──────────────────────────────────────────────────
            if (selectedPin != null)
              _TargetInfoCard(
                pin: selectedPin,
                rangeYards: input?.rangeYards,
                shootingAngle: input?.shootingAngleDegrees,
              )
            else
              _NoTargetBanner(),

            const SizedBox(height: 16),

            // ── Active rifle ─────────────────────────────────────────────────
            if (activeProfile != null)
              _ProfileSummaryCard(profile: activeProfile)
            else
              _NoProfileBanner(),

            const SizedBox(height: 16),

            // ── Environment inputs ───────────────────────────────────────────
            _EnvironmentCard(
              windSpeedCtrl: _windSpeedCtrl,
              windDirCtrl: _windDirCtrl,
              tempCtrl: _tempCtrl,
              pressCtrl: _pressCtrl,
              onApply: _applyOverrides,
              weatherAsync: weatherAsync,
            ),

            const SizedBox(height: 16),

            // ── Solution card ────────────────────────────────────────────────
            if (ballisticsState.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (ballisticsState.hasError)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.errorRed),
                ),
                child: Text(
                  ballisticsState.errorMessage!,
                  style: const TextStyle(color: AppTheme.errorRed),
                ),
              )
            else if (ballisticsState.solution != null)
              SolutionCard(solution: ballisticsState.solution!),

            const SizedBox(height: 16),

            // ── Range card table ─────────────────────────────────────────────
            if (_showRangeCard && ballisticsState.rangeCard.isNotEmpty)
              _RangeCardTable(solutions: ballisticsState.rangeCard),
          ],
        ),
      ),
    );
  }
}

// ── Target info card ──────────────────────────────────────────────────────────

class _TargetInfoCard extends StatelessWidget {
  const _TargetInfoCard({
    required this.pin,
    required this.rangeYards,
    required this.shootingAngle,
  });

  final dynamic pin;
  final double? rangeYards;
  final double? shootingAngle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TARGET',
              style: TextStyle(
                color: AppTheme.primaryOrange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  pin.label ?? pin.type.displayName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  pin.type.icon,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _InfoChip(
                  label: 'Range',
                  value:
                      rangeYards != null
                          ? '${rangeYards!.toStringAsFixed(0)} yds'
                          : '—',
                ),
                const SizedBox(width: 8),
                _InfoChip(
                  label: 'Angle',
                  value:
                      shootingAngle != null
                          ? '${shootingAngle!.toStringAsFixed(1)}°'
                          : '—',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoTargetBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.textSecondary),
          SizedBox(width: 12),
          Text(
            'No target selected. Drop a pin on the map first.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Profile summary ───────────────────────────────────────────────────────────

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({required this.profile});
  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RIFLE',
              style: TextStyle(
                color: AppTheme.primaryOrange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              profile.name,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${profile.caliber}  •  '
              '${profile.bulletProfile.bulletWeightGrains.toStringAsFixed(0)} gr  •  '
              '${profile.bulletProfile.muzzleVelocityFps.toStringAsFixed(0)} fps  •  '
              'Zero ${profile.zeroDistanceYards.toStringAsFixed(0)} yds',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoProfileBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.errorRed),
      ),
      child: const Text(
        'No rifle profile active. Go to Profile to set one.',
        style: TextStyle(color: AppTheme.errorRed),
      ),
    );
  }
}

// ── Environment card ──────────────────────────────────────────────────────────

class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({
    required this.windSpeedCtrl,
    required this.windDirCtrl,
    required this.tempCtrl,
    required this.pressCtrl,
    required this.onApply,
    this.weatherAsync,
  });

  final TextEditingController windSpeedCtrl;
  final TextEditingController windDirCtrl;
  final TextEditingController tempCtrl;
  final TextEditingController pressCtrl;
  final VoidCallback onApply;
  final dynamic weatherAsync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'ENVIRONMENT',
                  style: TextStyle(
                    color: AppTheme.primaryOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                if (weatherAsync?.valueOrNull != null)
                  const Chip(
                    label: Text('Live', style: TextStyle(fontSize: 10)),
                    avatar: Icon(Icons.cloud_done, size: 12),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _compactField(
                    windSpeedCtrl,
                    'Wind (mph)',
                    'e.g. 10',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactField(
                    windDirCtrl,
                    'Wind Dir (°)',
                    '0=head 90=rt',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _compactField(tempCtrl, 'Temp (°F)', 'e.g. 59'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactField(pressCtrl, 'Press (inHg)', 'e.g. 29.92'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onApply,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                ),
                child: const Text('Apply & Calculate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactField(
    TextEditingController ctrl,
    String label,
    String hint,
  ) => TextField(
    controller: ctrl,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
  );
}

// ── Range card table ──────────────────────────────────────────────────────────

class _RangeCardTable extends StatelessWidget {
  const _RangeCardTable({required this.solutions});
  final List<dynamic> solutions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RANGE CARD',
              style: TextStyle(
                color: AppTheme.primaryOrange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 32,
                dataRowMinHeight: 28,
                dataRowMaxHeight: 28,
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('Yds', style: TextStyle(fontSize: 11))),
                  DataColumn(label: Text('Drop"', style: TextStyle(fontSize: 11))),
                  DataColumn(label: Text('Elev MOA', style: TextStyle(fontSize: 11))),
                  DataColumn(label: Text('Elev Clicks', style: TextStyle(fontSize: 11))),
                  DataColumn(label: Text('Wind MOA', style: TextStyle(fontSize: 11))),
                  DataColumn(label: Text('Vel fps', style: TextStyle(fontSize: 11))),
                  DataColumn(label: Text('ToF s', style: TextStyle(fontSize: 11))),
                ],
                rows: solutions.map<DataRow>((s) {
                  return DataRow(
                    cells: [
                      DataCell(Text('${s.rangeYards.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11))),
                      DataCell(Text('${s.dropInches.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11))),
                      DataCell(Text('${s.elevationCorrectionMoa.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: AppTheme.primaryOrange))),
                      DataCell(Text('${s.elevationClicksUp}', style: const TextStyle(fontSize: 11))),
                      DataCell(Text('${s.windCorrectionMoa.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11))),
                      DataCell(Text('${s.remainingVelocityFps.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11))),
                      DataCell(Text('${s.timeOfFlightSeconds.toStringAsFixed(3)}', style: const TextStyle(fontSize: 11))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
