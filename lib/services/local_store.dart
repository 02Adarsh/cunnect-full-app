/// ⭐ Chhoti si persistent storage — web: localStorage, mobile/desktop:
/// shared_preferences. Await LocalStore.init() in main().
import 'local_store_stub.dart'
    if (dart.library.html) 'local_store_web.dart'
    if (dart.library.io) 'local_store_mobile.dart' as impl;

class LocalStore {
  LocalStore._();

  static Future<void> init() => impl.init();

  static String? get(String key) => impl.get(key);
  static void set(String key, String value) => impl.set(key, value);
  static void remove(String key) => impl.remove(key);
}
