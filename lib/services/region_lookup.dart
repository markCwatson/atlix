/// Offline GPS → US state / Canadian province lookup using bounding boxes.
///
/// Approximate but fast — no network required. Suitable for determining
/// which region a user is in for plant species reranking.
class RegionLookup {
  /// Returns the state/province code for the given coordinates, or null
  /// if outside US/Canada.
  static String? lookup(double lat, double lon) {
    for (final r in _regions) {
      if (lat >= r.minLat &&
          lat <= r.maxLat &&
          lon >= r.minLon &&
          lon <= r.maxLon) {
        return r.code;
      }
    }
    return null;
  }

  static const _regions = <_Region>[
    // ── Canadian Provinces ──────────────────────────────────────────
    _Region('AB', 49.0, 60.0, -120.0, -110.0),
    _Region('BC', 48.3, 60.0, -139.1, -114.0),
    _Region('MB', 49.0, 60.0, -102.0, -88.9),
    _Region('NB', 44.6, 48.1, -69.1, -63.8),
    _Region('NL', 46.6, 60.4, -67.8, -52.6),
    _Region('NS', 43.4, 47.0, -66.4, -59.7),
    _Region('NT', 60.0, 78.8, -136.5, -102.0),
    _Region('NU', 51.7, 83.1, -120.4, -61.2),
    _Region('ON', 41.7, 56.9, -95.2, -74.3),
    _Region('PE', 45.9, 47.1, -64.4, -62.0),
    _Region('QC', 45.0, 62.6, -79.8, -57.1),
    _Region('SK', 49.0, 60.0, -110.0, -101.4),
    _Region('YT', 60.0, 69.6, -141.0, -124.0),

    // ── US States ──────────────────────────────────────────────────
    _Region('AL', 30.2, 35.0, -88.5, -84.9),
    _Region('AK', 51.2, 71.4, -179.1, -130.0),
    _Region('AZ', 31.3, 37.0, -114.8, -109.0),
    _Region('AR', 33.0, 36.5, -94.6, -89.6),
    _Region('CA', 32.5, 42.0, -124.4, -114.1),
    _Region('CO', 37.0, 41.0, -109.1, -102.0),
    _Region('CT', 41.0, 42.1, -73.7, -71.8),
    _Region('DE', 38.5, 39.8, -75.8, -75.0),
    _Region('FL', 24.5, 31.0, -87.6, -80.0),
    _Region('GA', 30.4, 35.0, -85.6, -80.8),
    _Region('HI', 18.9, 22.2, -160.2, -154.8),
    _Region('ID', 42.0, 49.0, -117.2, -111.0),
    _Region('IL', 37.0, 42.5, -91.5, -87.5),
    _Region('IN', 37.8, 41.8, -88.1, -84.8),
    _Region('IA', 40.4, 43.5, -96.6, -90.1),
    _Region('KS', 37.0, 40.0, -102.1, -94.6),
    _Region('KY', 36.5, 39.1, -89.6, -81.9),
    _Region('LA', 29.0, 33.0, -94.0, -89.0),
    _Region('ME', 43.1, 47.5, -71.1, -66.9),
    _Region('MD', 37.9, 39.7, -79.5, -75.0),
    _Region('MA', 41.2, 42.9, -73.5, -69.9),
    _Region('MI', 41.7, 48.3, -90.4, -82.4),
    _Region('MN', 43.5, 49.4, -97.2, -89.5),
    _Region('MS', 30.2, 35.0, -91.7, -88.1),
    _Region('MO', 36.0, 40.6, -95.8, -89.1),
    _Region('MT', 44.4, 49.0, -116.1, -104.0),
    _Region('NE', 40.0, 43.0, -104.1, -95.3),
    _Region('NV', 35.0, 42.0, -120.0, -114.0),
    _Region('NH', 42.7, 45.3, -72.6, -70.7),
    _Region('NJ', 38.9, 41.4, -75.6, -73.9),
    _Region('NM', 31.3, 37.0, -109.1, -103.0),
    _Region('NY', 40.5, 45.0, -79.8, -71.9),
    _Region('NC', 33.8, 36.6, -84.3, -75.5),
    _Region('ND', 45.9, 49.0, -104.1, -96.6),
    _Region('OH', 38.4, 42.0, -84.8, -80.5),
    _Region('OK', 33.6, 37.0, -103.0, -94.4),
    _Region('OR', 42.0, 46.3, -124.6, -116.5),
    _Region('PA', 39.7, 42.3, -80.5, -74.7),
    _Region('RI', 41.1, 42.0, -71.9, -71.1),
    _Region('SC', 32.0, 35.2, -83.4, -78.5),
    _Region('SD', 42.5, 46.0, -104.1, -96.4),
    _Region('TN', 35.0, 36.7, -90.3, -81.6),
    _Region('TX', 25.8, 36.5, -106.6, -93.5),
    _Region('UT', 37.0, 42.0, -114.1, -109.0),
    _Region('VT', 42.7, 45.0, -73.4, -71.5),
    _Region('VA', 36.5, 39.5, -83.7, -75.2),
    _Region('WA', 45.5, 49.0, -124.8, -116.9),
    _Region('WV', 37.2, 40.6, -82.6, -77.7),
    _Region('WI', 42.5, 47.1, -92.9, -86.8),
    _Region('WY', 41.0, 45.0, -111.1, -104.1),
  ];
}

class _Region {
  final String code;
  final double minLat, maxLat, minLon, maxLon;
  const _Region(this.code, this.minLat, this.maxLat, this.minLon, this.maxLon);
}
