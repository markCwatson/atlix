import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../blocs/plant_cubit.dart';
import '../models/plant_result.dart';

/// Full-screen results page showing the photo and ranked species predictions.
class PlantResultScreen extends StatefulWidget {
  final PlantResult result;

  /// If true, the result is already saved — show view-only mode.
  final bool viewOnly;

  const PlantResultScreen({
    super.key,
    required this.result,
    this.viewOnly = false,
  });

  @override
  State<PlantResultScreen> createState() => _PlantResultScreenState();
}

class _PlantResultScreenState extends State<PlantResultScreen> {
  bool _exporting = false;

  Future<void> _exportToGallery() async {
    setState(() => _exporting = true);
    try {
      final file = File(widget.result.imagePath);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final original = frame.image;

      // For classification, export the original image as-is (no bounding boxes)
      final pngBytes = await original.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (pngBytes == null) throw Exception('Failed to encode image');

      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File(
        '${tmpDir.path}/monyx_plant_${widget.result.id}.png',
      );
      await tmpFile.writeAsBytes(pngBytes.buffer.asUint8List());
      await Gal.putImage(tmpFile.path);
      await tmpFile.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image saved to gallery'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save image: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Text('${widget.result.partLabel} ID'),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.ios_share, color: Colors.white),
            tooltip: 'Save image to gallery',
            onPressed: _exporting ? null : _exportToGallery,
          ),
        ],
      ),
      body: Column(
        children: [
          // Photo (no bounding boxes — classification, not detection)
          Expanded(flex: 3, child: _PlantImage(result: widget.result)),

          // Species predictions list
          Expanded(flex: 2, child: _PredictionsList(result: widget.result)),

          // Action bar
          if (!widget.viewOnly)
            SafeArea(top: false, child: _ActionBar(result: widget.result)),
        ],
      ),
    );
  }
}

/// Shows the captured plant image with badges.
class _PlantImage extends StatelessWidget {
  final PlantResult result;
  const _PlantImage({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(result.imagePath), fit: BoxFit.contain),

          // Plant part badge
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(result.partIcon, color: Colors.green, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    result.partLabel,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // Prediction count badge
          if (result.predictions.isNotEmpty)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${result.predictions.length} match${result.predictions.length == 1 ? '' : 'es'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ranked species list sorted by display score.
class _PredictionsList extends StatelessWidget {
  final PlantResult result;
  const _PredictionsList({required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.predictions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: Colors.white38, size: 48),
            SizedBox(height: 8),
            Text(
              'No species identified',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Try a clearer photo or different angle',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final topScore = result.topPrediction?.displayScore ?? 0;

    return Column(
      children: [
        // Low confidence disclaimer
        if (topScore < 0.5)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.amber.withValues(alpha: 0.15),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.amber, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Low confidence — results may be inaccurate',
                    style: TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: result.predictions.length,
            separatorBuilder: (_, _) =>
                const Divider(color: Colors.white12, height: 1),
            itemBuilder: (context, index) {
              final pred = result.predictions[index];
              final displayName = pred.commonName != null
                  ? pred.commonName!
                  : PlantResult.formatSpeciesName(pred.className);
              final scientificName = PlantResult.formatSpeciesName(
                pred.className,
              );
              final hasCommonName = pred.commonName != null;
              final pct = (pred.displayScore * 100).toStringAsFixed(1);
              final color = _colorForConfidence(pred.displayScore);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    // Rank number
                    SizedBox(
                      width: 28,
                      child: Text(
                        '#${index + 1}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),

                    // Species name + confidence bar
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (hasCommonName)
                            Text(
                              scientificName,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pred.displayScore.clamp(0.0, 1.0),
                              backgroundColor: Colors.white12,
                              color: color,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Percentage
                    Text(
                      '$pct%',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _colorForConfidence(double conf) {
    if (conf >= 0.7) return Colors.green;
    if (conf >= 0.4) return Colors.amber;
    return Colors.red;
  }
}

/// Bottom action bar: Retake / Done.
class _ActionBar extends StatelessWidget {
  final PlantResult result;
  const _ActionBar({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey[850],
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Retake'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Navigator.pop(context);
                context.read<PlantCubit>().capture(result.plantPart);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BlocBuilder<PlantCubit, PlantState>(
              builder: (context, state) {
                final isSaving = state is PlantClassifying;
                final isSaved = state is PlantDone && state.saved;
                return ElevatedButton.icon(
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Icon(isSaved ? Icons.check : Icons.save),
                  label: Text(isSaved ? 'Saved' : 'Done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSaved
                        ? Colors.green
                        : Colors.orangeAccent,
                    foregroundColor: isSaved ? Colors.white : Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: isSaved
                      ? () {
                          context.read<PlantCubit>().clear();
                          Navigator.pop(context);
                        }
                      : () async {
                          await context.read<PlantCubit>().saveResult();
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
