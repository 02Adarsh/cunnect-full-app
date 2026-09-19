import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// ⭐ v73: OFFLINE map tiles.
///
/// Every tile the map shows is written to the phone's storage, so the
/// campus area keeps rendering with NO internet once it has been seen
/// (or pre-loaded with [precacheArea]). Tiles already on disk are served
/// straight from the file — no network at all.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers, this.onCacheHit});

  /// Called (best effort) when a tile is served from disk.
  final void Function()? onCacheHit;

  static Directory? _dir;
  static final Set<String> _downloading = {};
  static bool _dirReady = false;

  static Future<Directory> tilesDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/cunnect_tiles');
    if (!_dir!.existsSync()) {
      await _dir!.create(recursive: true);
    }
    _dirReady = true;
    return _dir!;
  }

  static String _file(String name) => '${_dir!.path}/$name.png';

  /// Save (or refresh) one tile in the background.
  static Future<void> _save(String url, String name) async {
    if (_downloading.contains(name)) return;
    _downloading.add(name);
    try {
      final dir = await tilesDir();
      final file = File('${dir.path}/$name.png');
      if (file.existsSync() && file.lengthSync() > 200) return;
      final res = await http
          .get(Uri.parse(url),
              headers: const {'User-Agent': 'CUnnect/1.0 (com.cunnect.cunnect_food)'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(res.bodyBytes, flush: false);
      }
    } catch (_) {
    } finally {
      _downloading.remove(name);
    }
  }

  static String tileName(int z, int x, int y) => '${z}_${x}_$y';

  static String tileUrl(int z, int x, int y) =>
      'https://tile.openstreetmap.org/$z/$x/$y.png';

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    final name = tileName(coordinates.z, coordinates.x, coordinates.y);
    if (_dirReady && _dir != null) {
      final file = File(_file(name));
      if (file.existsSync() && file.lengthSync() > 200) {
        onCacheHit?.call();
        return FileImage(file);
      }
    }
    // not on disk yet — show it from the network and keep a copy
    _save(url, name);
    return NetworkImage(url, headers: headers);
  }
}

/// ⭐ Download the tiles of one area so the map works offline there.
///
/// `radiusTiles` is how many tiles around the centre are fetched at each
/// zoom level (1 = a 3x3 block). Keep it small — every tile is a file.
Future<int> precacheArea({
  required double lat,
  required double lng,
  List<int> zooms = const [13, 14, 15, 16],
  int radiusTiles = 2,
  void Function(int done, int total)? onProgress,
}) async {
  final dir = await CachedTileProvider.tilesDir();
  CachedTileProvider._dirReady = true;
  final jobs = <List<int>>[];
  for (final z in zooms) {
    final c = _tileOf(lat, lng, z);
    for (var dx = -radiusTiles; dx <= radiusTiles; dx++) {
      for (var dy = -radiusTiles; dy <= radiusTiles; dy++) {
        jobs.add([z, c.$1 + dx, c.$2 + dy]);
      }
    }
  }
  var done = 0;
  var saved = 0;
  for (final job in jobs) {
    final name = CachedTileProvider.tileName(job[0], job[1], job[2]);
    final file = File('${dir.path}/$name.png');
    if (file.existsSync() && file.lengthSync() > 200) {
      done++;
      onProgress?.call(done, jobs.length);
      continue;
    }
    try {
      final res = await http
          .get(Uri.parse(CachedTileProvider.tileUrl(job[0], job[1], job[2])),
              headers: const {
                'User-Agent': 'CUnnect/1.0 (com.cunnect.cunnect_food)'
              })
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(res.bodyBytes, flush: false);
        saved++;
      }
    } catch (_) {}
    done++;
    onProgress?.call(done, jobs.length);
  }
  return saved;
}

/// How many tiles are already stored (for the "offline map" badge).
Future<int> cachedTileCount() async {
  try {
    final dir = await CachedTileProvider.tilesDir();
    return dir
        .listSync()
        .where((f) => f.path.endsWith('.png'))
        .length;
  } catch (_) {
    return 0;
  }
}

/// Web-Mercator tile index for a coordinate (standard slippy-map maths).
(int, int) _tileOf(double lat, double lng, int z) {
  final n = 1 << z; // number of tiles across the world at this zoom
  final x = ((lng + 180.0) / 360.0 * n).floor();
  final latRad = lat * math.pi / 180.0;
  final y = ((1.0 -
              math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
          2.0 *
          n)
      .floor();
  final max = n - 1;
  return (x < 0 ? 0 : (x > max ? max : x), y < 0 ? 0 : (y > max ? max : y));
}
