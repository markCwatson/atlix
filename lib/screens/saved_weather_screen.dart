import 'package:flutter/material.dart';

import '../models/weather_profile.dart';
import '../services/weather_profile_service.dart';

/// Shows a list of saved weather profiles for offline wind animation.
class SavedWeatherScreen extends StatefulWidget {
  /// Optional callback invoked when the user taps a profile to apply it.
  final void Function(WeatherProfile profile)? onApply;

  const SavedWeatherScreen({super.key, this.onApply});

  @override
  State<SavedWeatherScreen> createState() => _SavedWeatherScreenState();
}

class _SavedWeatherScreenState extends State<SavedWeatherScreen> {
  final WeatherProfileService _service = WeatherProfileService();
  List<WeatherProfile>? _profiles;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await _service.loadAll();
    if (mounted) setState(() => _profiles = profiles);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Saved Weather'),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        actions: [
          if (_profiles != null && _profiles!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete All',
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: _profiles == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            )
          : _profiles!.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.air, color: Colors.white24, size: 64),
                  SizedBox(height: 12),
                  Text(
                    'No saved weather profiles yet',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Use the wind overlay to save profiles',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _profiles!.length,
              itemBuilder: (context, index) => _WeatherTile(
                profile: _profiles![index],
                onTap: widget.onApply != null
                    ? () {
                        widget.onApply!(_profiles![index]);
                        Navigator.pop(context);
                      }
                    : null,
                onDelete: () => _delete(_profiles![index]),
              ),
            ),
    );
  }

  Future<void> _deleteAll() async {
    final count = _profiles?.length ?? 0;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Delete All?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently remove all $count saved weather profiles.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete All',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      for (final p in List<WeatherProfile>.from(_profiles!)) {
        await _service.delete(p.id);
      }
      _load();
    }
  }

  Future<void> _delete(WeatherProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text(
          'Delete Profile?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently remove the saved weather profile.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _service.delete(profile.id);
      _load();
    }
  }
}

class _WeatherTile extends StatelessWidget {
  final WeatherProfile profile;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _WeatherTile({
    required this.profile,
    this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dir = WeatherProfile.compassLabel(profile.windDirectionDeg);
    final speed = '${profile.windSpeedMph.round()} mph $dir';
    final time = _formatTime(profile.targetTime);
    final coords =
        '${profile.latitude.toStringAsFixed(3)}, ${profile.longitude.toStringAsFixed(3)}';

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.air, color: Colors.orangeAccent, size: 24),
      ),
      title: Text(
        speed,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '$time  •  $coords',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.white38),
        onPressed: onDelete,
      ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1 && diff.inMinutes > -60) return 'Just now';
    if (diff.inHours < 1 && diff.inMinutes >= 0) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1 && diff.inHours >= 0) return '${diff.inHours}h ago';
    if (diff.inDays < 7 && diff.inDays >= 0) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
