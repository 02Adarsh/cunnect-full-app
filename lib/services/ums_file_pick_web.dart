// ignore: deprecated_member_use
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const bool supported = true;

Future<String?> pickImageDataUrlImpl() {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = 'image/*';
  var settled = false;
  input.onChange.listen((_) {
    final file = (input.files ?? const []).isNotEmpty
        ? input.files!.first
        : null;
    if (file == null) {
      if (!settled) {
        settled = true;
        completer.complete(null);
      }
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      if (!settled) {
        settled = true;
        completer.complete(reader.result is String
            ? reader.result as String
            : null);
      }
    });
    reader.onError.listen((_) {
      if (!settled) {
        settled = true;
        completer.complete(null);
      }
    });
    reader.readAsDataUrl(file);
  });
  // The user closed the picker without choosing a file -> null after 60s.
  Timer(const Duration(seconds: 60), () {
    if (!settled) {
      settled = true;
      completer.complete(null);
    }
  });
  input.click();
  return completer.future;
}
