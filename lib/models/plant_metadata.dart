import '../models/plant_result.dart';

/// Metadata for a single plant species, used for Phase 2 reranking.
class PlantSpeciesMeta {
  /// Class ID matching the model output index.
  final int classId;

  /// Scientific name (e.g. "Acer saccharum").
  final String scientificName;

  /// Common name (e.g. "Sugar Maple").
  final String commonName;

  /// US state / Canadian province codes where the species is present
  /// (e.g. ["ON", "QC", "NY", "VT"]).
  final List<String> regions;

  /// Months (1–12) when the species is typically visible or flowering.
  final List<int> activeMonths;

  /// Plant parts with the best images for identification.
  final List<PlantPart> commonParts;

  /// Whether the species is known to be toxic.
  final bool toxic;

  const PlantSpeciesMeta({
    required this.classId,
    required this.scientificName,
    required this.commonName,
    required this.regions,
    required this.activeMonths,
    required this.commonParts,
    this.toxic = false,
  });

  factory PlantSpeciesMeta.fromJson(Map<String, dynamic> json) {
    return PlantSpeciesMeta(
      classId: json['class_id'] as int,
      scientificName: json['scientific_name'] as String,
      commonName: json['common_name'] as String,
      regions: (json['regions'] as List).cast<String>(),
      activeMonths: (json['active_months'] as List).cast<int>(),
      commonParts: (json['common_parts'] as List)
          .map((p) => PlantPart.values.byName(p as String))
          .toList(),
      toxic: json['toxic'] as bool? ?? false,
    );
  }
}
