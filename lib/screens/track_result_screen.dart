import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../blocs/track_cubit.dart';
import '../models/track_result.dart';
import '../widgets/detection_image_painter.dart';

/// Full-screen results page showing the annotated image and ranked species.
class TrackResultScreen extends StatefulWidget {
  final TrackResult result;

  /// If true, the result is already saved — show Delete instead of Save.
  final bool viewOnly;

  const TrackResultScreen({
    super.key,
    required this.result,
    this.viewOnly = false,
  });

  @override
  State<TrackResultScreen> createState() => _TrackResultScreenState();
}

class _TrackResultScreenState extends State<TrackResultScreen> {
  bool _exporting = false;

  Future<void> _exportToGallery() async {
    setState(() => _exporting = true);
    try {
      // Load the original image
      final file = File(widget.result.imagePath);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final original = frame.image;

      // Create a picture recorder and draw image + boxes
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = Size(original.width.toDouble(), original.height.toDouble());

      // Draw the original photo
      canvas.drawImage(original, Offset.zero, Paint());

      // Draw the bounding boxes on top (at full image resolution)
      final painter = DetectionImagePainter(
        detections: widget.result.detections,
        imageWidth: widget.result.imageWidth,
        imageHeight: widget.result.imageHeight,
      );
      painter.paint(canvas, size);

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(original.width, original.height);
      final pngBytes = await rendered.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (pngBytes == null) throw Exception('Failed to encode image');

      // Write to temp file and save to gallery
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File(
        '${tmpDir.path}/monyx_track_${widget.result.id}.png',
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
        title: Text('${widget.result.traceLabel} ID'),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        actions: [
          if (!widget.viewOnly)
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
          if (widget.viewOnly)
            IconButton(
              icon: const Icon(Icons.ios_share, color: Colors.white),
              tooltip: 'Save image to gallery',
              onPressed: _exporting ? null : _exportToGallery,
            ),
        ],
      ),
      body: Column(
        children: [
          // Annotated image
          Expanded(flex: 3, child: _AnnotatedImage(result: widget.result)),

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

/// Shows the captured image with bounding box overlays.
class _AnnotatedImage extends StatelessWidget {
  final TrackResult result;
  const _AnnotatedImage({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(result.imagePath), fit: BoxFit.contain),
          if (result.detections.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: DetectionImagePainter(
                  detections: result.detections,
                  imageWidth: result.imageWidth,
                  imageHeight: result.imageHeight,
                ),
              ),
            ),

          // Trace type badge
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
                  Icon(
                    result.traceType == TraceType.footprint
                        ? Icons.pets
                        : Icons.blur_circular,
                    color: Colors.orangeAccent,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    result.traceLabel,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // Detection count badge
          if (result.detections.isNotEmpty)
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
                  '${result.detections.length} detection${result.detections.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ranked species list sorted by confidence.
class _PredictionsList extends StatelessWidget {
  final TrackResult result;
  const _PredictionsList({required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.detections.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: Colors.white38, size: 48),
            SizedBox(height: 8),
            Text(
              'No tracks detected',
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

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: result.detections.length,
      separatorBuilder: (_, _) =>
          const Divider(color: Colors.white12, height: 1),
      itemBuilder: (context, index) {
        final det = result.detections[index];
        final name = TrackResult.formatSpeciesName(det.className);
        final pct = (det.confidence * 100).toStringAsFixed(1);
        final color = _colorForConfidence(det.confidence);

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
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: det.confidence,
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
  final TrackResult result;
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
                context.read<TrackCubit>().capture(result.traceType);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BlocBuilder<TrackCubit, TrackState>(
              builder: (context, state) {
                final isSaving = state is TrackDetecting;
                final isSaved = state is TrackDone && state.saved;
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
                          context.read<TrackCubit>().clear();
                          Navigator.pop(context);
                        }
                      : () async {
                          await context.read<TrackCubit>().saveResult();
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
