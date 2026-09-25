import 'package:shared_preferences/shared_preferences.dart';

/// ⭐ APK/mobile persistent storage.
/// v90: in-memory mirror so get() never returns null just because the
/// async prefs write has not flushed yet — critical for lock flags.
SharedPreferences? _prefs;
final Map<String, String> _mem = {};

Future<void> init() async {
  _prefs ??= await SharedPreferences.getInstance();
  // Seed memory from disk once.
  try {
    for (final k in _prefs!.getKeys()) {
      final v = _prefs!.getString(k);
      if (v != null) _mem[k] = v;
    }
  } catch (_) {}
}

String? get(String key) {
  if (_mem.containsKey(key)) return _mem[key];
  return _prefs?.getString(key);
}

void set(String key, String value) {
  _mem[key] = value;
  // Fire-and-forget disk write; memory already has it for this process.
  _prefs?.setString(key, value);
}

void remove(String key) {
  _mem.remove(key);
  _prefs?.remove(key);
}
