import 'package:flutter/foundation.dart';

/// Reports a platform failure that no caller can handle (a fire-and-forget platform call).
void reportMapError(Object error, StackTrace stack, String context) => FlutterError.reportError(
  FlutterErrorDetails(
    exception: error,
    stack: stack,
    library: 'flutter_unified_map',
    context: ErrorDescription(context),
  ),
);
