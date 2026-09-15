// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> init() async {}

String? get(String key) => html.window.localStorage[key];

void set(String key, String value) => html.window.localStorage[key] = value;

void remove(String key) => html.window.localStorage.remove(key);
