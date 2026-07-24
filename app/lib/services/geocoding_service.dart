import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/secrets.dart';

enum GeocodeStatus {
  ok,
  zeroResults,
  network, // no connection or timeout
  requestDenied, // invalid key or Geocoding API disabled
  error,
}

class GeocodeResult {
  final String formattedAddress;
  final double lat;
  final double lng;

  const GeocodeResult({
    required this.formattedAddress,
    required this.lat,
    required this.lng,
  });
}

class GeocodeResponse {
  final GeocodeStatus status;
  final List<GeocodeResult> results;

  const GeocodeResponse(this.status, [this.results = const []]);
}

/// Address search through the Google Geocoding REST API. The only place that
/// uses [Secrets.geocodingApiKey].
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// `region=pt` biases results towards Portugal without excluding others.
  Future<GeocodeResponse> search(String query) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': query,
      'region': 'pt',
      'key': Secrets.geocodingApiKey,
    });

    http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      return const GeocodeResponse(GeocodeStatus.network);
    } on SocketException {
      return const GeocodeResponse(GeocodeStatus.network);
    } on http.ClientException {
      return const GeocodeResponse(GeocodeStatus.network);
    }

    if (res.statusCode != 200) {
      debugPrint('Geocoding HTTP ${res.statusCode}: ${res.body}');
      return const GeocodeResponse(GeocodeStatus.error);
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      debugPrint('Geocoding: non-JSON response: ${res.body}');
      return const GeocodeResponse(GeocodeStatus.error);
    }

    final status = body['status'] as String?;
    switch (status) {
      case 'OK':
        final raw = (body['results'] as List?) ?? const [];
        final results = <GeocodeResult?>[
          for (final e in raw)
            if (e is Map<String, dynamic>) _parseResult(e),
        ].whereType<GeocodeResult>().toList();
        return results.isEmpty
            ? const GeocodeResponse(GeocodeStatus.zeroResults)
            : GeocodeResponse(GeocodeStatus.ok, results);
      case 'ZERO_RESULTS':
        return const GeocodeResponse(GeocodeStatus.zeroResults);
      case 'REQUEST_DENIED':
        debugPrint('Geocoding REQUEST_DENIED: ${body['error_message']}');
        return const GeocodeResponse(GeocodeStatus.requestDenied);
      default:
        // OVER_QUERY_LIMIT, INVALID_REQUEST, UNKNOWN_ERROR, etc.
        debugPrint('Geocoding status=$status: ${body['error_message']}');
        return const GeocodeResponse(GeocodeStatus.error);
    }
  }

  GeocodeResult? _parseResult(Map<String, dynamic> e) {
    final loc = (e['geometry'] as Map?)?['location'] as Map?;
    final lat = (loc?['lat'] as num?)?.toDouble();
    final lng = (loc?['lng'] as num?)?.toDouble();
    final addr = e['formatted_address'] as String?;
    if (lat == null || lng == null || addr == null) return null;
    return GeocodeResult(formattedAddress: addr, lat: lat, lng: lng);
  }
}
