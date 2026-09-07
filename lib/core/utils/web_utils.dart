/// Platform-aware web utilities.
/// On Web: provides actual DOM manipulation (pointer-events, etc.)
/// On mobile: stubs that do nothing.
export 'web_utils_stub.dart'
    if (dart.library.html) 'web_utils_web.dart';
