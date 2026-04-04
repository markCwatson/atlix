import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/track_cubit.dart';
import '../models/track_result.dart';
import 'track_result_screen.dart';

/// Shows a list of saved track identification results.
class SavedTracksScreen extends StatefulWidget {
  const SavedTracksScreen({super.key});

  @override
  State<SavedTracksScreen> createState() => _SavedTracksScreenState();
}

class _SavedTracksScreenState extends State<SavedTracksScreen> {
  List<TrackResult>? _results;
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
    final results = await context.read<TrackCubit>().loadSaved();
    debugPrint('[SavedTracksScreen] loaded ${results.length} results');
    if (mounted) setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Saved Tracks'),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        actions: [
          if (_results != null && _results!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete All',
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: _results == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            )
          : _results!.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pets, color: Colors.white24, size: 64),
                  SizedBox(height: 12),
                  Text(
                    'No saved tracks yet',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Identify a track and tap Save to keep it here',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _results!.length,
              itemBuilder: (context, index) => _TrackTile(
                result: _results![index],
                onTap: () => _openResult(_results![index]),
                onDelete: () => _delete(_results![index]),
              ),
            ),
    );
  }

  Future<void> _deleteAll() async {
    final count = _results?.length ?? 0;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Delete All?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently remove all $count saved tracks and images.',
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
      for (final r in List<TrackResult>.from(_results!)) {
        await context.read<TrackCubit>().deleteSaved(r.id);
      }
      _load();
    }
  }

  void _openResult(TrackResult result) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<TrackCubit>(),
          child: TrackResultScreen(result: result, viewOnly: true),
        ),
      ),
    );
  }

  Future<void> _delete(TrackResult result) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text(
          'Delete Track?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently remove the saved track and image.',
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
      await context.read<TrackCubit>().deleteSaved(result.id);
      _load();
    }
  }
}

class _TrackTile extends StatelessWidget {
  final TrackResult result;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TrackTile({
    required this.result,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final topDet = result.topDetection;
    final species = topDet != null
        ? TrackResult.formatSpeciesName(topDet.className)
        : 'No detection';
    final conf = topDet != null
        ? '${(topDet.confidence * 100).toStringAsFixed(0)}%'
        : '';
    final traceIcon = result.traceType == TraceType.footprint
        ? Icons.pets
        : Icons.blur_circular;
    final time = _formatTime(result.timestamp);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: File(result.imagePath).existsSync()
              ? Image.file(File(result.imagePath), fit: BoxFit.cover)
              : Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.broken_image, color: Colors.white38),
                ),
        ),
      ),
      title: Row(
        children: [
          Icon(traceIcon, color: Colors.orangeAccent, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              species,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        '$conf  •  $time',
        style: const TextStyle(color: Colors.white54),
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
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
