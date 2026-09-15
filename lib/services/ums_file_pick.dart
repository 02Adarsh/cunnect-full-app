/// ID-card image picker — web browser me hidden <input type=file> kholta
/// hai (original dashboard.html wala hi flow); baaki platforms pe
/// unsupported (stub null deta hai).
import 'ums_file_pick_stub.dart'
    if (dart.library.html) 'ums_file_pick_web.dart'
    if (dart.library.io) 'ums_file_pick_mobile.dart' as impl;

bool get idPickSupported => impl.supported;

/// Gallery/file picker kholo -> image ka dataURL wapas (cancel = null).
Future<String?> pickImageDataUrl() => impl.pickImageDataUrlImpl();
