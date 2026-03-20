import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:monyx/../core/theme/app_theme.dart';
import 'package:monyx/../core/utils/geo_utils.dart';
import 'package:monyx/profiles/providers/profile_provider.dart';
import 'package:monyx/weather/providers/weather_provider.dart';
import 'package:monyx/features/map/models/map_pin.dart';
import 'package:monyx/features/map/providers/map_provider.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  bool _showAddPinSheet = false;
  final _pinLabelCtrl = TextEditingController();

  @override
  void dispose() {
    _pinLabelCtrl.dispose();
    super.dispose();
  }

  void _addPinAtCurrentLocation(PinType type) {
    ref
        .read(mapStateProvider.notifier)
        .dropPinAtCurrentLocation(type: type, label: _pinLabelCtrl.text.trim());
    _pinLabelCtrl.clear();
    setState(() => _showAddPinSheet = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${type.displayName} pin added')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapStateProvider);
    final activeProfile = ref.watch(activeRifleProfileProvider);

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Stack(
        children: [
          // ── Map placeholder ────────────────────────────────────────────────
          const _MapboxPlaceholder(),

          // ── Top HUD ────────────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _TopHud(
              isOffline: mapState.isOffline,
              profileName: activeProfile?.name,
              userLat: mapState.userLatitude,
              userLon: mapState.userLongitude,
            ),
          ),

          // ── Right-side controls ────────────────────────────────────────────
          Positioned(
            right: 12,
            bottom: mapState.selectedPin != null ? 280 : 120,
            child: Column(
              children: [
                _MapIconButton(
                  icon: Icons.layers_outlined,
                  tooltip: 'Land overlay',
                  isActive: mapState.showLandOverlay,
                  onPressed:
                      () =>
                          ref.read(mapStateProvider.notifier).toggleLandOverlay(),
                ),
                const SizedBox(height: 8),
                _MapIconButton(
                  icon: Icons.my_location,
                  tooltip: 'My location',
                  onPressed: () {
                    // In production, animate camera to user location.
                  },
                ),
              ],
            ),
          ),

          // ── Pin list overlay (top-right) ───────────────────────────────────
          if (mapState.pins.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 72,
              right: 12,
              child: _PinCountBadge(count: mapState.pins.length),
            ),

          // ── Selected pin bottom sheet ──────────────────────────────────────
          if (mapState.selectedPin != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _PinDetailSheet(
                pin: mapState.selectedPin!,
                userLat: mapState.userLatitude,
                userLon: mapState.userLongitude,
                userElevation: mapState.userElevationMeters,
                onClose:
                    () => ref.read(mapStateProvider.notifier).selectPin(null),
                onBallistics: () => context.push('/ballistics'),
                onDelete: () {
                  ref
                      .read(mapStateProvider.notifier)
                      .removePin(mapState.selectedPin!.id);
                },
              ),
            ),

          // ── Add pin modal ──────────────────────────────────────────────────
          if (_showAddPinSheet)
            _AddPinSheet(
              labelCtrl: _pinLabelCtrl,
              onAdd: _addPinAtCurrentLocation,
              onCancel: () => setState(() => _showAddPinSheet = false),
            ),
        ],
      ),

      // ── Bottom navigation ──────────────────────────────────────────────────
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 1:
              context.push('/ballistics');
            case 2:
              context.push('/profile');
            case 3:
              context.push('/settings');
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(
            icon: Icon(Icons.adjust),
            label: 'Ballistics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _showAddPinSheet = true),
        tooltip: 'Add pin',
        child: const Icon(Icons.add_location_alt_outlined),
      ),
    );
  }
}

// ── Map placeholder ────────────────────────────────────────────────────────────

/// Shown until the Mapbox SDK is wired up after `flutter pub get`.
class _MapboxPlaceholder extends StatelessWidget {
  const _MapboxPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A2030),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 64, color: Color(0xFF3A4060)),
            SizedBox(height: 16),
            Text(
              'Map loading…',
              style: TextStyle(color: Color(0xFF5A6080), fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Run flutter pub get to activate Mapbox',
              style: TextStyle(color: Color(0xFF3A4060), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top HUD ────────────────────────────────────────────────────────────────────

class _TopHud extends ConsumerWidget {
  const _TopHud({
    required this.isOffline,
    required this.profileName,
    required this.userLat,
    required this.userLon,
  });

  final bool isOffline;
  final String? profileName;
  final double? userLat;
  final double? userLon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync =
        (userLat != null && userLon != null)
            ? ref.watch(
              weatherProvider(LatLon(lat: userLat!, lon: userLon!)),
            )
            : null;

    return Row(
      children: [
        if (isOffline)
          _HudChip(
            icon: Icons.wifi_off,
            label: 'Offline',
            color: AppTheme.errorRed,
          ),
        if (weatherAsync != null) ...[
          const SizedBox(width: 6),
          weatherAsync.when(
            data:
                (w) => _HudChip(
                  icon: Icons.thermostat,
                  label:
                      '${w.temperatureCelsius.toStringAsFixed(0)}°C  '
                      '${w.windSpeedMs.toStringAsFixed(1)}m/s',
                  color: AppTheme.surfaceCard,
                ),
            loading:
                () => const _HudChip(
                  icon: Icons.cloud_outlined,
                  label: '…',
                  color: AppTheme.surfaceCard,
                ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
        const Spacer(),
        if (profileName != null)
          _HudChip(
            icon: Icons.adjust,
            label: profileName!,
            color: AppTheme.surfaceCard,
          ),
      ],
    );
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(230),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textPrimary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Icon button ────────────────────────────────────────────────────────────────

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip = '',
    this.isActive = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color:
            isActive
                ? AppTheme.primaryOrange
                : AppTheme.surfaceCard.withAlpha(230),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              color: isActive ? Colors.black : AppTheme.textPrimary,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pin count badge ────────────────────────────────────────────────────────────

class _PinCountBadge extends StatelessWidget {
  const _PinCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryOrange,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place, size: 14, color: Colors.black),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pin detail sheet ───────────────────────────────────────────────────────────

class _PinDetailSheet extends StatelessWidget {
  const _PinDetailSheet({
    required this.pin,
    required this.onClose,
    required this.onBallistics,
    required this.onDelete,
    this.userLat,
    this.userLon,
    this.userElevation,
  });

  final MapPin pin;
  final VoidCallback onClose;
  final VoidCallback onBallistics;
  final VoidCallback onDelete;
  final double? userLat;
  final double? userLon;
  final double? userElevation;

  String _rangeText() {
    if (userLat == null || userLon == null) return '—';
    final m = GeoUtils.haversineDistance(
      userLat!,
      userLon!,
      pin.latitude,
      pin.longitude,
    );
    final yds = GeoUtils.metersToYards(m);
    if (yds < 1000) {
      return '${yds.toStringAsFixed(0)} yds';
    }
    return '${(yds / 1000).toStringAsFixed(2)} kyd';
  }

  String _elevDiffText() {
    if (userElevation == null || pin.elevationMeters == null) return '—';
    final diff = pin.elevationMeters! - userElevation!;
    final ft = GeoUtils.metersToFeet(diff);
    return '${ft >= 0 ? '+' : ''}${ft.toStringAsFixed(0)} ft';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 12)],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(pin.type.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pin.label ?? pin.type.displayName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Stats row
          Row(
            children: [
              _StatChip(label: 'Range', value: _rangeText()),
              const SizedBox(width: 8),
              _StatChip(label: 'Elev Δ', value: _elevDiffText()),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Lat',
                value: pin.latitude.toStringAsFixed(5),
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Lon',
                value: pin.longitude.toStringAsFixed(5),
              ),
            ],
          ),
          if (pin.notes != null && pin.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              pin.notes!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onBallistics,
                  icon: const Icon(Icons.adjust, size: 18),
                  label: const Text('Ballistics'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed),
                tooltip: 'Delete pin',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Add pin sheet ─────────────────────────────────────────────────────────────

class _AddPinSheet extends StatefulWidget {
  const _AddPinSheet({
    required this.labelCtrl,
    required this.onAdd,
    required this.onCancel,
  });

  final TextEditingController labelCtrl;
  final void Function(PinType) onAdd;
  final VoidCallback onCancel;

  @override
  State<_AddPinSheet> createState() => _AddPinSheetState();
}

class _AddPinSheetState extends State<_AddPinSheet> {
  PinType _selectedType = PinType.waypoint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onCancel,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Pin',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: widget.labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Label (optional)',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Type',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children:
                        PinType.values.map((type) {
                          final selected = _selectedType == type;
                          return ChoiceChip(
                            label: Text('${type.icon} ${type.displayName}'),
                            selected: selected,
                            onSelected: (_) => setState(() => _selectedType = type),
                            selectedColor: AppTheme.primaryOrange,
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onCancel,
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => widget.onAdd(_selectedType),
                          child: const Text('Drop Pin'),
                        ),
                      ),
                    ],
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
