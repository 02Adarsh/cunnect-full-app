import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/up_places.dart';
import '../../services/offline_tiles.dart';
import '../../theme/app_colors.dart';

/// ⭐ v66: pick a ride location on an OpenStreetMap map.
///
///  * SEARCH a place by name (OpenStreetMap Nominatim — free, no API
///    key, no billing, works on any server including your own VPS).
///  * TAP anywhere on the map and the address is filled in
///    AUTOMATICALLY (reverse lookup) — no typing needed.
///
/// Nominatim is the free OSM geocoder: requests are debounced and
/// identified with a proper User-Agent, exactly as their usage policy
/// asks. If you ever self-host, change [_searchUrl] / [_reverseUrl].
class RideMapPickerScreen extends StatefulWidget {
  final String title;
  final String hint;

  /// Map starts here, or on an existing pin.
  final LatLng? initial;

  const RideMapPickerScreen({
    super.key,
    required this.title,
    this.hint = '',
    this.initial,
  });

  @override
  State<RideMapPickerScreen> createState() => _RideMapPickerScreenState();
}

/// ⭐ v72: reverse-geocode any point into a short human address.
/// Used by "Use my location" on the ride home screen.
Future<String> reverseGeocodeName(double lat, double lng) async {
  try {
    final uri = Uri.parse(_RideMapPickerScreenState._reverseUrl)
        .replace(queryParameters: {
      'format': 'jsonv2',
      'lat': lat.toString(),
      'lon': lng.toString(),
    });
    final res = await http
        .get(uri, headers: {
          'User-Agent': _RideMapPickerScreenState._userAgent,
          'Accept-Language': 'en',
        })
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final name = '${data['name'] ?? ''}';
      final display = '${data['display_name'] ?? ''}';
      final label = name.isNotEmpty && name != display
          ? '$name, ${_RideMapPickerScreenState._shortName(display)}'
          : _RideMapPickerScreenState._shortName(display);
      if (label.trim().isNotEmpty) return label.trim();
    }
  } catch (_) {}
  return '';
}

class _RideMapPickerScreenState extends State<RideMapPickerScreen> {
  /// ⭐ Campus default — Chandigarh University (Gharuan).
  /// The map opens right on the campus and search results are ranked
  /// around it. Moving campus? Change these two numbers, nothing else.
  // ⭐ v73: the pinned campus — Chandigarh University, Uttar Pradesh
  // (Parsandan / Nawabganj, Unnao district).
  static const double campusLat = kCampusLat;
  static const double campusLng = kCampusLng;
  static const LatLng campusCenter = LatLng(campusLat, campusLng);
  static CachedTileProvider? _tileProvider;

  CachedTileProvider get _tiles =>
      _tileProvider ??= CachedTileProvider();

  // OpenStreetMap Nominatim (free, no key). Self-host later if needed.
  static const String _searchUrl =
      'https://nominatim.openstreetmap.org/search';
  static const String _reverseUrl =
      'https://nominatim.openstreetmap.org/reverse';
  static const String _userAgent = 'CUnnect/1.0 (com.cunnect.cunnect_food)';

  late LatLng _picked;
  final _name = TextEditingController();
  final _search = TextEditingController();
  final _mapController = MapController();
  final _searchFocus = FocusNode();

  Timer? _debounce;
  int _searchSeq = 0;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial ?? campusCenter;
    _search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // --------------------------- searching ---------------------------

  void _onSearchChanged() {
    _debounce?.cancel();
    if (mounted) setState(() {}); // keep the clear (×) button in sync
    final q = _search.text.trim();
    if (q.length < 3) {
      if (mounted) {
        setState(() => _results = const []);
      }
      return;
    }
    // ⭐ debounced — Nominatim asks for at most 1 request per second.
    _debounce = Timer(const Duration(milliseconds: 550), () => _searchPlace(q));
  }

  /// ⭐ v73: high-accuracy GPS -> exact pin + real address.
  Future<void> _useCurrentLocation() async {
    if (!mounted) return;
    setState(() => _locating = true);
    try {
      final on = await Geolocator.isLocationServiceEnabled();
      if (!on) {
        _toast('Turn on location services.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Location permission is needed.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation);
      final point = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _picked = point);
      _mapController.move(point, 17.5);
      final name = await reverseGeocodeName(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _name.text = name.isNotEmpty
            ? name
            : 'My location (${pos.latitude.toStringAsFixed(5)}, '
                '${pos.longitude.toStringAsFixed(5)})';
      });
    } catch (_) {
      _toast('Could not read your location.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// ⭐ v73: keep the map working here without internet.
  Future<void> _downloadOfflineArea() async {
    if (_offlineBusy) return;
    setState(() => _offlineBusy = true);
    try {
      final saved = await precacheArea(
        lat: _picked.latitude,
        lng: _picked.longitude,
        zooms: const [13, 14, 15, 16],
        radiusTiles: 2,
      );
      if (!mounted) return;
      _toast(saved > 0
          ? 'Offline map saved ($saved tiles)'
          : 'This area is already saved offline');
    } catch (_) {
      _toast('Could not download the map.');
    } finally {
      if (mounted) setState(() => _offlineBusy = false);
    }
  }

  bool _offlineBusy = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1E1E1E)));
  }

  /// One Nominatim query. [bias] adds the campus viewbox + India filter.
  Future<List<Map<String, dynamic>>> _query(String q,
      {required bool bias}) async {
    final params = <String, String>{
      'format': 'jsonv2',
      'q': q,
      'limit': '6',
      'addressdetails': '0',
    };
    if (bias) {
      // ⭐ results are biased towards the campus so the nearest match
      // floats to the top, but nothing is blocked ('bounded=0').
      const d = 0.6;
      params['viewbox'] =
          '${campusLng - d},${campusLat + d},${campusLng + d},${campusLat - d}';
      params['bounded'] = '0';
      params['countrycodes'] = 'in';
    }
    final uri = Uri.parse(_searchUrl).replace(queryParameters: params);
    final res = await http
        .get(uri,
            headers: {'User-Agent': _userAgent, 'Accept-Language': 'en'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return const [];
    final list = jsonDecode(res.body);
    if (list is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      final lat = double.tryParse('${item['lat']}');
      final lon = double.tryParse('${item['lon']}');
      if (lat == null || lon == null) continue;
      out.add({
        'title': _shortName('${item['display_name'] ?? ''}'),
        'full': '${item['display_name'] ?? ''}',
        'lat': lat,
        'lng': lon,
      });
    }
    return out;
  }

  /// ⭐ FORGIVING search: Nominatim returns nothing the moment you add
  /// an extra word ("chandigarh university nawabganj uttar pradesh"),
  /// so we retry by dropping trailing words, and finally search
  /// world-wide without the India/campus bias.
  Future<void> _searchPlace(String query) async {
    final seq = ++_searchSeq;
    if (!mounted) return;
    // ⭐ v73: the built-in UP list answers instantly (and offline).
    final local = searchUpPlaces(query).map((p) => <String, dynamic>{
          'title': p.$1,
          'full': '${p.$1} (${p.$2})',
          'lat': p.$3,
          'lng': p.$4,
          'local': true,
        }).toList();
    if (local.isNotEmpty && mounted) {
      setState(() => _results = local);
    }
    setState(() => _searching = true);
    try {
      var out = await _query(query, bias: true);
      if (seq != _searchSeq) return; // a newer keystroke won
      final words =
          query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      for (var n = words.length - 1; n >= 1 && out.isEmpty; n--) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (seq != _searchSeq) return;
        out = await _query(words.take(n).join(' '), bias: true);
        if (seq != _searchSeq) return;
      }
      if (out.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (seq != _searchSeq) return;
        out = await _query(query, bias: false);
        if (seq != _searchSeq) return;
      }
      if (!mounted) return;
      // local hits stay on top; online ones fill in the rest
      final seen = <String>{
        for (final r in local) '${r['title']}'.toLowerCase()
      };
      setState(() => _results = <Map<String, dynamic>>[
        ...local,
        ...out.where((r) => seen.add('${r['title']}'.toLowerCase())),
      ]);
    } catch (_) {
      // offline / blocked — the built-in list and tapping still work.
    } finally {
      if (seq == _searchSeq && mounted) setState(() => _searching = false);
    }
  }

  /// "A, B, C, India" -> "A, B"
  static String _shortName(String display) {
    final parts = display
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return display.trim();
    return parts.take(parts.length >= 2 ? 2 : 1).join(', ');
  }

  Future<void> _pickResult(Map<String, dynamic> r) async {
    final point = LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble());
    setState(() {
      _picked = point;
      _name.text = '${r['title']}';
      _results = const [];
    });
    _search.clear();
    _searchFocus.unfocus();
    _mapController.move(point, 16.5);
  }

  // ---------------------------- map tap ----------------------------

  void _onTap(TapPosition _, LatLng point) {
    setState(() => _picked = point);
    _reverseGeocode(point);
  }

  /// ⭐ tap anywhere -> the address fills itself in.
  Future<void> _reverseGeocode(LatLng point) async {
    if (!mounted) return;
    setState(() => _locating = true);
    try {
      final uri = Uri.parse(_reverseUrl).replace(queryParameters: {
        'format': 'jsonv2',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
      });
      final res = await http
          .get(uri, headers: {
            'User-Agent': _RideMapPickerScreenState._userAgent,
            'Accept-Language': 'en',
          })
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final name = '${data['name'] ?? ''}';
        final display = '${data['display_name'] ?? ''}';
        final label = name.isNotEmpty && name != display
            ? '$name, ${_RideMapPickerScreenState._shortName(display)}'
            : _RideMapPickerScreenState._shortName(display);
        if (label.trim().isNotEmpty && mounted) {
          setState(() => _name.text = label);
        }
      }
    } catch (_) {
      // keep whatever the user typed — no network, no problem.
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tap a point on the map or search for a place first.'),
      ));
      return;
    }
    Navigator.of(context).pop({
      'text': name,
      'lat': _picked.latitude,
      'lng': _picked.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.page,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title.toUpperCase(),
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _picked,
                    initialZoom: 15,
                    onTap: _onTap,
                  ),
                  children: [
                    TileLayer(
                      // ⭐ v73: tiles are cached on the phone, so the
                      // campus keeps loading with no internet.
                      tileProvider: _tiles,
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.cunnect.cunnect_food',
                      maxZoom: 19,
                    ),
                    MarkerLayer(markers: [
                      // ⭐ the university is ALWAYS visible on the map
                      Marker(
                        point: campusCenter,
                        width: 120,
                        height: 34,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xE6141414),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AppColors.red),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.school_rounded,
                                  size: 13, color: Color(0xFFFF9CA5)),
                              SizedBox(width: 5),
                              Flexible(
                                child: Text('Chandigarh University UP',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Marker(
                        point: _picked,
                        width: 46,
                        height: 46,
                        child: const Icon(Icons.location_pin,
                            color: AppColors.red, size: 46),
                      ),
                    ]),
                  ],
                ),
                // ⭐ search bar floating on top of the map
                Positioned(
                  left: 12,
                  right: 12,
                  top: 10,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xF2141414),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText: 'Search a place…',
                            hintStyle: const TextStyle(
                                color: Color(0xFF8A8A8A), fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: Color(0xFF9E9E9E), size: 19),
                            suffixIcon: _searching
                                ? const Padding(
                                    padding: EdgeInsets.all(13),
                                    child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            color: AppColors.red,
                                            strokeWidth: 2)),
                                  )
                                : (_search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close_rounded,
                                            size: 17,
                                            color: Color(0xFF9E9E9E)),
                                        onPressed: () {
                                          _search.clear();
                                          setState(() => _results = const []);
                                        },
                                      )),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_results.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xF7141414),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x26FFFFFF)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _results.length,
                              separatorBuilder: (_, __) => const Divider(
                                  color: Color(0x1AFFFFFF), height: 1),
                              itemBuilder: (_, i) {
                                final r = _results[i];
                                return InkWell(
                                  onTap: () => _pickResult(r),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        13, 11, 13, 11),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.place_outlined,
                                            size: 17,
                                            color: Color(0xFFF5F5F5)),
                                        const SizedBox(width: 11),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text('${r['title']}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                              if ('${r['full']}'.isNotEmpty)
                                                Text('${r['full']}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        color: Color(
                                                            0xFF8A8A8A),
                                                        fontSize: 10.5)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 16,
                  child: Column(
                    children: [
                      // ⭐ v73: precise CURRENT LOCATION (GPS, ~5 m)
                      _roundBtn(Icons.my_location_rounded, _useCurrentLocation,
                          highlight: true),
                      const SizedBox(height: 10),
                      // ⭐ v73: save this area for offline use
                      _roundBtn(Icons.download_for_offline_rounded,
                          _downloadOfflineArea),
                      const SizedBox(height: 10),
                      _roundBtn(Icons.add, () {
                        final z = _mapController.camera.zoom + 1;
                        _mapController.move(_picked, z > 19 ? 19 : z);
                      }),
                      const SizedBox(height: 10),
                      _roundBtn(Icons.remove, () {
                        final z = _mapController.camera.zoom - 1;
                        _mapController.move(_picked, z < 3 ? 3 : z);
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D),
              border: Border(top: BorderSide(color: Color(0xFF242424))),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_pin,
                          color: AppColors.red, size: 15),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _locating
                              ? 'Reading the address…'
                              : '${_picked.latitude.toStringAsFixed(5)}, '
                                  '${_picked.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              color: Color(0xFF9E9E9E),
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _name,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Location name',
                      hintStyle: const TextStyle(
                          color: Color(0xFF6E6E6E), fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF111111),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide:
                            const BorderSide(color: Color(0xFF303030)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(color: AppColors.red),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.hint.isEmpty
                        ? 'Tap the map or search a place — the name fills in '
                            'by itself. You can still edit it.'
                        : widget.hint,
                    style: const TextStyle(
                        color: Color(0xFF6A6A6A), fontSize: 11, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('CONFIRM LOCATION',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap,
          {bool highlight = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: highlight
                ? AppColors.red.withOpacity(.92)
                : const Color(0xE6141414),
            shape: BoxShape.circle,
            border: Border.all(
                color: highlight ? AppColors.red : const Color(0x33FFFFFF)),
          ),
          child: Icon(icon,
              color: highlight ? Colors.white : Colors.white, size: 20),
        ),
      );
}
