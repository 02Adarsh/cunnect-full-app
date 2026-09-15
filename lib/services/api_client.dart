import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'local_store.dart';

import 'package:http/http.dart' as http;

/// Central API configuration.
///
/// ⭐ PRODUCTION: sab users auto-connect — koi setting/⚙ option nahi.
/// Render service ka naam EXACTLY `cunnect-backend` rakhna taaki URL match ho.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'https://cunnect-backend.onrender.com';

  /// Student / chat / print / UMS ka token.
  static String? studentToken;

  /// Vendor portal ka token (alag login).
  static String? vendorToken;

  /// Delivery portal ka token.
  static String? deliveryToken;

  static String url(String path) => '$baseUrl$path';

  /// Media paths (images/files) ko full URL banao.
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

/// Thin HTTP wrapper around the Django API. Sab responses ka shape:
/// `{ok: true, data: {...}}` ya `{ok: false, error: "..."}`.
class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<Map<String, dynamic>> get(String path, {String? token}) async {
    try {
      final response = await _http
          .get(Uri.parse(ApiConfig.url(path)), headers: _headers(token))
          .timeout(const Duration(seconds: 30));
      return _decode(response);
    } on SocketException {
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
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
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      throw ApiException('Request timed out — the server is not responding.');
    }
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
    required String fileField,
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
      } else {
        request.files
            .add(await http.MultipartFile.fromPath(fileField, filePath!));
      }
      final streamed = await _http.send(request).timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on SocketException {
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      throw ApiException('Upload timed out — the server is not responding.');
    }
  }


  /// Raw JSON GET — {ok,data} unwrap nahi (ping/id-card jaise endpoints).
  Future<Map<String, dynamic>> getRaw(String path, {String? token}) async {
    try {
      final response = await _http
          .get(Uri.parse(ApiConfig.url(path)), headers: _headers(token))
          .timeout(const Duration(seconds: 30));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on SocketException {
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      throw ApiException('Request timed out — the server is not responding.');
    }
  }

  /// Raw JSON POST — {ok,data} unwrap nahi.
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
      throw ApiException('Could not connect to the server. Is the backend running?');
    } on TimeoutException {
      throw ApiException('Request timed out — the server is not responding.');
    }
  }

  /// Raw GET (binary nahi) — status code ke saath, bina decode fail kiye.
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
      throw ApiException('Server ne invalid response diya (HTTP ${response.statusCode}).',
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
