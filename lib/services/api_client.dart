import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'local_store.dart';

import 'package:http/http.dart' as http;

/// Central API configuration.
///
/// ⭐ PRODUCTION: all users auto-connect — no setting/⚙ option.
/// Keep the Render service name EXACTLY `cunnect-backend` so the URL matches.
class ApiConfig {
  ApiConfig._();

  // ⭐ v63.1: the app talks to the clean OWN domain first (the shared
  // onrender.com host tripped Google Safe Browsing). If the domain is
  // ever unreachable, the client fails over to the Render URL
  // automatically — the app keeps working either way.
  static const String primaryUrl = 'https://cunnect.online';
  static const String fallbackUrl = 'https://cunnect-backend.onrender.com';

  /// Current base — flips to [fallbackUrl] if the domain stops answering.
  static String baseUrl = primaryUrl;

  /// Student / chat / print / UMS ka token.
  static String? studentToken;

  /// Vendor portal ka token (alag login).
  static String? vendorToken;

  /// Delivery portal ka token.
  static String? deliveryToken;

  /// Admin panel token (staff/superuser login).
  static String? adminToken;

  static String url(String path) => '$baseUrl$path';

  /// Turn media paths (images/files) into full URLs.
  static String media(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl${path.startsWith('/') ? '' : '/'}$path';
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, {this.statusCode = 0});

  @override
  String toString() => message;
}

/// Thin HTTP wrapper around the Django API. Every response has the shape
/// `{ok: true, data: {...}}` or `{ok: false, error: "..."}`.
class ApiClient {
  // ⭐ v62: ONE shared HTTP client for the whole app — the TLS connection
  // to the server stays alive and is reused, so every tap after the first
  // skips the costly handshake (hundreds of ms saved per request).
  static final http.Client _shared = http.Client();

  ApiClient({http.Client? httpClient}) : _http = httpClient ?? _shared;

  final http.Client _http;

  /// ⭐ v63.1: the domain didn't answer — switch to the Render URL for
  /// the rest of the session. Returns true if a retry makes sense.
  static bool _failover() {
    if (ApiConfig.baseUrl == ApiConfig.primaryUrl) {
      ApiConfig.baseUrl = ApiConfig.fallbackUrl;
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> get(String path, {String? token}) async {
    try {
      final response = await _http
          .get(Uri.parse(ApiConfig.url(path)), headers: _headers(token))
          .timeout(const Duration(seconds: 30));
      return _decode(response);
    } on SocketException {
      if (_failover()) return get(path, token: token);
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      if (_failover()) return get(path, token: token);
      throw ApiException('Request timed out — the server is not responding.');
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    try {
      final response = await _http
          .post(Uri.parse(ApiConfig.url(path)),
              headers: _headers(token),
              body: body == null ? null : jsonEncode(body))
          .timeout(const Duration(seconds: 60));
      return _decode(response);
    } on SocketException {
      if (_failover()) return post(path, body: body, token: token);
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      if (_failover()) return post(path, body: body, token: token);
      throw ApiException('Request timed out — the server is not responding.');
    }
  }

  Future<Map<String, dynamic>> delete(String path, {String? token}) async {
    try {
      final response = await _http
          .delete(Uri.parse(ApiConfig.url(path)), headers: _headers(token))
          .timeout(const Duration(seconds: 30));
      return _decode(response);
    } on SocketException {
      if (_failover()) return delete(path, token: token);
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      if (_failover()) return delete(path, token: token);
      throw ApiException('Request timed out — the server is not responding.');
    }
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
    String fileField = 'file',
    String? token,
  }) async {
    try {
      final request = http.MultipartRequest(
          'POST', Uri.parse(ApiConfig.url(path)))
        ..headers.addAll(_headers(token))
        ..fields.addAll(fields);
      if (fileBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(fileField, fileBytes,
            filename: fileName ?? 'document'));
      } else if (filePath != null) {
        request.files
            .add(await http.MultipartFile.fromPath(fileField, filePath));
      }
      final streamed = await _http.send(request).timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on SocketException {
      if (_failover()) {
        return postMultipart(path,
            fields: fields,
            filePath: filePath,
            fileBytes: fileBytes,
            fileName: fileName,
            fileField: fileField,
            token: token);
      }
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      throw ApiException('Upload timed out — the server is not responding.');
    }
  }


  /// Raw JSON GET — no {ok,data} unwrap (endpoints like ping/id-card).
  Future<Map<String, dynamic>> getRaw(String path, {String? token}) async {
    try {
      final response = await _http
          .get(Uri.parse(ApiConfig.url(path)), headers: _headers(token))
          .timeout(const Duration(seconds: 30));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on SocketException {
      if (_failover()) return getRaw(path, token: token);
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      if (_failover()) return getRaw(path, token: token);
      throw ApiException('Request timed out — the server is not responding.');
    }
  }

  /// Raw JSON POST — no {ok,data} unwrap.
  Future<Map<String, dynamic>> postRaw(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    try {
      final response = await _http
          .post(Uri.parse(ApiConfig.url(path)),
              headers: _headers(token),
              body: body == null ? null : jsonEncode(body))
          .timeout(const Duration(seconds: 60));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on SocketException {
      if (_failover()) return postRaw(path, body: body, token: token);
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      if (_failover()) return postRaw(path, body: body, token: token);
      throw ApiException('Request timed out — the server is not responding.');
    }
  }

  /// Raw GET (not binary) — with the status code, without failing to decode.
  Map<String, String> _headers(String? token) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Token $token';
    }
    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('The server returned an invalid response (HTTP ${response.statusCode}).',
          statusCode: response.statusCode);
    }
    final ok = payload['ok'] == true;
    if (!ok) {
      final message = (payload['error'] ?? 'Something went wrong').toString();
      throw ApiException(message, statusCode: response.statusCode);
    }
    return payload;
  }

  /// `{ok, data}` envelope se `data` nikalo.
  Map<String, dynamic> dataOf(Map<String, dynamic> response) =>
      (response['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
}
