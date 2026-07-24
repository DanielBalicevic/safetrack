import 'package:flutter/foundation.dart';

import '../services/geocoding_service.dart';

/// Tracks whether an address search is running; results go back to the caller.
class GeocodingProvider extends ChangeNotifier {
  GeocodingProvider({GeocodingService? service})
      : _service = service ?? GeocodingService();

  final GeocodingService _service;

  bool _searching = false;
  bool get searching => _searching;

  Future<GeocodeResponse> search(String query) async {
    _searching = true;
    notifyListeners();
    try {
      return await _service.search(query.trim());
    } finally {
      _searching = false;
      notifyListeners();
    }
  }
}
