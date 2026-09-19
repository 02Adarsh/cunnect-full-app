/// Dependency-free external URL opener.
/// Web: new browser tab; Mobile/desktop: external browser (url_launcher);
/// fallback: copy the link.
export 'open_url_stub.dart'
    if (dart.library.html) 'open_url_web.dart'
    if (dart.library.io) 'open_url_mobile.dart';
