import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// ⭐ APK/mobile: image from the gallery/file picker -> dataURL (same as web).
const bool supported = true;

Future<String?> pickImageDataUrlImpl() async {
  try {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final ext = (f.extension ?? 'png').toLowerCase();
    final mime = ext == 'jpg' || ext == 'jpeg'
        ? 'image/jpeg'
        : ext == 'gif'
            ? 'image/gif'
            : ext == 'webp'
                ? 'image/webp'
                : 'image/png';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}
