import 'package:shared_preferences/shared_preferences.dart';

/// ⭐ APK/mobile persistent storage — shared_preferences cache ke saath
/// sync get/set (AppStore sync API rehta hai).
SharedPreferences? _prefs;

Future<void> init() async {
  _prefs ??= await SharedPreferences.getInstance();
}

String? get(String key) => _prefs?.getString(key);

void set(String key, String value) {
  _prefs?.setString(key, value);
}

void remove(String key) {
  _prefs?.remove(key);
}
