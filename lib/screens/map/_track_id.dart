part of 'map_screen.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

/// Animal track identification methods for [_MapScreenState].
extension _MapScreenTrackId on _MapScreenState {
  Widget _trackIdButton({
    required bool isPro,
    required bool isDetecting,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: 'track_id',
        mini: true,
        backgroundColor: isPro ? Colors.black87 : Colors.grey[800],
        onPressed: isDetecting ? null : onTap,
        child: isDetecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.orangeAccent,
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.pets,
                    color: isPro ? Colors.orangeAccent : Colors.white38,
                    size: 20,
                  ),
                  if (!isPro)
                    const Positioned(
                      right: -2,
                      bottom: -2,
                      child: Icon(Icons.lock, color: Colors.white54, size: 10),
                    ),
                ],
              ),
      ),
    );
  }

  void _showTraceTypePicker(BuildContext context) {
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
                'Identify Animal Track',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _traceOption(
                context: ctx,
                icon: Icons.pets,
                label: 'Footprint',
                subtitle: '117 species',
                traceType: TraceType.footprint,
              ),
              const SizedBox(height: 8),
              _traceOption(
                context: ctx,
                icon: Icons.blur_circular,
                label: 'Scat / Feces',
                subtitle: '101 species',
                traceType: TraceType.feces,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _openSavedTracks(ctx),
                child: const Text(
                  'View Saved Tracks',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startCapture(
    BuildContext sheetContext,
    TraceType traceType,
    ImageSource source,
  ) {
    Navigator.pop(sheetContext);
    context.read<TrackCubit>().capture(
      traceType,
      source: source,
      latitude: _effectiveLat,
      longitude: _effectiveLon,
    );
  }

  Widget _traceOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required TraceType traceType,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.orangeAccent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () =>
                _startCapture(context, traceType, ImageSource.camera),
            icon: const Icon(Icons.camera_alt, color: Colors.orangeAccent),
            tooltip: 'Camera',
          ),
          IconButton(
            onPressed: () =>
                _startCapture(context, traceType, ImageSource.gallery),
            icon: const Icon(Icons.photo_library, color: Colors.orangeAccent),
            tooltip: 'Photos',
          ),
        ],
      ),
    );
  }

  void _openSavedTracks(BuildContext context) {
    // Dismiss any open bottom sheet first
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route is! PopupRoute);
    Navigator.of(this.context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: this.context.read<TrackCubit>(),
          child: const SavedTracksScreen(),
        ),
      ),
    );
  }
}
