import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/hike_track_cubit.dart';
import '../models/hike_track.dart';

/// Shows a list of saved hike tracks.
class SavedHikeTracksScreen extends StatefulWidget {
  const SavedHikeTracksScreen({super.key});

  @override
  State<SavedHikeTracksScreen> createState() => _SavedHikeTracksScreenState();
}

class _SavedHikeTracksScreenState extends State<SavedHikeTracksScreen> {
  List<HikeTrack>? _tracks;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    final tracks = await context.read<HikeTrackCubit>().loadSaved();
    if (mounted) setState(() => _tracks = tracks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Saved Hikes'),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        actions: [
          if (_tracks != null && _tracks!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete All',
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: _tracks == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            )
          : _tracks!.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_walk, color: Colors.white24, size: 64),
                  SizedBox(height: 12),
                  Text(
                    'No saved hikes yet',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Start a hike and tap Save to keep it here',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _tracks!.length,
              itemBuilder: (context, index) => _HikeTile(
                track: _tracks![index],
                onTap: () => _viewTrack(_tracks![index]),
                onDelete: () => _delete(_tracks![index]),
              ),
            ),
    );
  }

  Future<void> _deleteAll() async {
    final count = _tracks?.length ?? 0;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Delete All?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently remove all $count saved hikes.',
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
      for (final t in List<HikeTrack>.from(_tracks!)) {
        await context.read<HikeTrackCubit>().deleteSaved(t.id);
      }
      _load();
    }
  }

  void _viewTrack(HikeTrack track) {
    context.read<HikeTrackCubit>().viewSaved(track);
    Navigator.of(context).pop(); // Return to map — it will render the track
  }

  Future<void> _delete(HikeTrack track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text(
          'Delete Hike?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently remove the saved hike track.',
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
      await context.read<HikeTrackCubit>().deleteSaved(track.id);
      _load();
    }
  }
}

class _HikeTile extends StatelessWidget {
  final HikeTrack track;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HikeTile({
    required this.track,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final distance = track.totalDistanceMiles >= 0.1
        ? '${track.totalDistanceMiles.toStringAsFixed(1)} mi'
        : '${track.totalDistanceMeters.round()} m';
    final elev =
        '↑${track.elevationGainFeet.round()} ft  ↓${track.elevationLossFeet.round()} ft';
    final time = _formatTime(track.startTime);

    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.teal.withAlpha(40),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.directions_walk, color: Colors.teal, size: 24),
      ),
      title: Text(
        track.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$distance  •  ${track.formattedDuration}  •  $elev\n$time',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      isThreeLine: true,
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
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
