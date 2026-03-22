import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/plant_cubit.dart';
import '../models/plant_result.dart';
import 'plant_result_screen.dart';

/// Shows a list of saved plant identification results.
class SavedPlantsScreen extends StatefulWidget {
  const SavedPlantsScreen({super.key});

  @override
  State<SavedPlantsScreen> createState() => _SavedPlantsScreenState();
}

class _SavedPlantsScreenState extends State<SavedPlantsScreen> {
  List<PlantResult>? _results;
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
    final results = await context.read<PlantCubit>().loadSaved();
    debugPrint('[SavedPlantsScreen] loaded ${results.length} results');
    if (mounted) setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Saved Plants'),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
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
                  Icon(Icons.local_florist, color: Colors.white24, size: 64),
                  SizedBox(height: 12),
                  Text(
                    'No saved plants yet',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Identify a plant and tap Save to keep it here',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _results!.length,
              itemBuilder: (context, index) => _PlantTile(
                result: _results![index],
                onTap: () => _openResult(_results![index]),
                onDelete: () => _delete(_results![index]),
              ),
            ),
    );
  }

  void _openResult(PlantResult result) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<PlantCubit>(),
          child: PlantResultScreen(result: result, viewOnly: true),
        ),
      ),
    );
  }

  Future<void> _delete(PlantResult result) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text(
          'Delete Plant?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently remove the saved plant and image.',
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
      await context.read<PlantCubit>().deleteSaved(result.id);
      _load();
    }
  }
}

class _PlantTile extends StatelessWidget {
  final PlantResult result;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PlantTile({
    required this.result,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final topPred = result.topPrediction;
    final species = topPred != null
        ? topPred.commonName ?? PlantResult.formatSpeciesName(topPred.className)
        : 'No match';
    final conf = topPred != null
        ? '${(topPred.displayScore * 100).toStringAsFixed(0)}%'
        : '';
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
          Icon(result.partIcon, color: Colors.green, size: 18),
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
