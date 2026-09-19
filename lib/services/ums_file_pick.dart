/// ID-card image picker — opens a hidden <input type=file> in the web browser
/// (same flow as the original dashboard.html); unsupported on other
/// platforms (the stub returns null).
import 'ums_file_pick_stub.dart'
    if (dart.library.html) 'ums_file_pick_web.dart'
    if (dart.library.io) 'ums_file_pick_mobile.dart' as impl;

bool get idPickSupported => impl.supported;

/// Open the gallery/file picker -> returns the image dataURL (cancel = null).
Future<String?> pickImageDataUrl() => impl.pickImageDataUrlImpl();
