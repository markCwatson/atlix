part of 'map_screen.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

/// Plant identification methods for [_MapScreenState].
extension _MapScreenPlantId on _MapScreenState {
  Widget _plantIdButton({
    required bool isPro,
    required bool isClassifying,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: 'plant_id',
        mini: true,
        backgroundColor: isPro ? Colors.black87 : Colors.grey[800],
        onPressed: isClassifying ? null : onTap,
        child: isClassifying
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.green,
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.local_florist,
                    color: isPro ? Colors.green : Colors.white38,
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

  void _showPlantPartPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Identify Plant',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.eco,
                  label: 'Leaf',
                  plantPart: PlantPart.leaf,
                ),
                const SizedBox(height: 8),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.local_florist,
                  label: 'Flower',
                  plantPart: PlantPart.flower,
                ),
                const SizedBox(height: 8),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.park,
                  label: 'Bark',
                  plantPart: PlantPart.bark,
                ),
                const SizedBox(height: 8),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.apple,
                  label: 'Fruit',
                  plantPart: PlantPart.fruit,
                ),
                const SizedBox(height: 8),
                _plantPartOption(
                  context: ctx,
                  icon: Icons.grass,
                  label: 'Whole Plant',
                  plantPart: PlantPart.wholePlant,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => _openSavedPlants(ctx),
                  child: const Text(
                    'View Saved Plants',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startPlantCapture(
    BuildContext sheetContext,
    PlantPart plantPart,
    ImageSource source,
  ) {
    Navigator.pop(sheetContext);
    context.read<PlantCubit>().capture(
      plantPart,
      source: source,
      latitude: _effectiveLat,
      longitude: _effectiveLon,
    );
  }

  Widget _plantPartOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required PlantPart plantPart,
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
          Icon(icon, color: Colors.green, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () =>
                _startPlantCapture(context, plantPart, ImageSource.camera),
            icon: const Icon(Icons.camera_alt, color: Colors.green),
            tooltip: 'Camera',
          ),
          IconButton(
            onPressed: () =>
                _startPlantCapture(context, plantPart, ImageSource.gallery),
            icon: const Icon(Icons.photo_library, color: Colors.green),
            tooltip: 'Photos',
          ),
        ],
      ),
    );
  }

  void _openSavedPlants(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route is! PopupRoute);
    Navigator.of(this.context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: this.context.read<PlantCubit>(),
          child: const SavedPlantsScreen(),
        ),
      ),
    );
  }
}
