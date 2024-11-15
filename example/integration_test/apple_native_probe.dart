import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart' show setUpAll, tearDownAll;

/// Reads the native state of the app through the Objective-C runtime, for checks that neither the plugin's API nor
/// a screenshot can make: what the MKMapView really holds, the opacity of its annotation views, and on macOS the
/// test window itself. Flutter runs Dart on the platform thread (merged threads), so AppKit and UIKit may be called
/// from here; [AppleNativeProbe] refuses to work otherwise.
class AppleNativeProbe {
  AppleNativeProbe._();

  static final AppleNativeProbe instance = AppleNativeProbe._();

  /// The Objective-C runtime exists only on iOS and macOS: elsewhere the native checks are skipped.
  static bool get isAvailable => Platform.isIOS || Platform.isMacOS;

  /// On macOS, keeps the test window in front for every test of the file: `flutter test` often fails to foreground
  /// the app ("Failed to foreground app"), and Flutter draws no frame while its window is off screen (app hidden,
  /// window on another Space), so every `pump` would block until it shows again.
  static void holdTestWindowInFront() {
    if (!Platform.isMacOS) return;
    setUpAll(() {
      debugPrint('[probe] test window visible before activation: ${instance.windowVisible}');
      instance.keepWindowInFront();
    });
    tearDownAll(instance.restoreWindowLevel);
  }

  final _lib = DynamicLibrary.process();
  late final _getClass = _lib
      .lookupFunction<Pointer<Void> Function(Pointer<Uint8>), Pointer<Void> Function(Pointer<Uint8>)>('objc_getClass');
  late final _registerName = _lib
      .lookupFunction<Pointer<Void> Function(Pointer<Uint8>), Pointer<Void> Function(Pointer<Uint8>)>(
        'sel_registerName',
      );
  late final _malloc = _lib.lookupFunction<Pointer<Uint8> Function(Size), Pointer<Uint8> Function(int)>('malloc');
  late final _free = _lib.lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>('free');
  late final _isMainThread = _lib.lookupFunction<Int32 Function(), int Function()>('pthread_main_np');

  late final _sendId = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
      >('objc_msgSend');
  late final _sendIdIndex = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, UnsignedLong),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int)
      >('objc_msgSend');
  late final _sendIdId = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('objc_msgSend');
  late final _sendUnsigned = _lib
      .lookupFunction<UnsignedLong Function(Pointer<Void>, Pointer<Void>), int Function(Pointer<Void>, Pointer<Void>)>(
        'objc_msgSend',
      );
  late final _sendDouble = _lib
      .lookupFunction<Double Function(Pointer<Void>, Pointer<Void>), double Function(Pointer<Void>, Pointer<Void>)>(
        'objc_msgSend',
      );
  late final _sendBoolId = _lib
      .lookupFunction<
        Bool Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
        bool Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('objc_msgSend');
  late final _sendVoid = _lib
      .lookupFunction<Void Function(Pointer<Void>, Pointer<Void>), void Function(Pointer<Void>, Pointer<Void>)>(
        'objc_msgSend',
      );
  late final _sendVoidBool = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Void>, Bool),
        void Function(Pointer<Void>, Pointer<Void>, bool)
      >('objc_msgSend');
  late final _sendVoidLong = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Void>, Long),
        void Function(Pointer<Void>, Pointer<Void>, int)
      >('objc_msgSend');
  // x86_64 returns structs this large through a hidden pointer argument (objc_msgSend_stret); arm64 does not.
  static final _stret = Abi.current() == Abi.macosX64 || Abi.current() == Abi.iosX64;

  late final _sendRectArm = _lib
      .lookupFunction<_CGRect Function(Pointer<Void>, Pointer<Void>), _CGRect Function(Pointer<Void>, Pointer<Void>)>(
        'objc_msgSend',
      );
  late final _sendRectRectArm = _lib
      .lookupFunction<
        _CGRect Function(Pointer<Void>, Pointer<Void>, _CGRect),
        _CGRect Function(Pointer<Void>, Pointer<Void>, _CGRect)
      >('objc_msgSend');
  late final _sendRectStret = _lib
      .lookupFunction<
        Void Function(Pointer<_CGRect>, Pointer<Void>, Pointer<Void>),
        void Function(Pointer<_CGRect>, Pointer<Void>, Pointer<Void>)
      >('objc_msgSend_stret');
  late final _sendRectRectStret = _lib
      .lookupFunction<
        Void Function(Pointer<_CGRect>, Pointer<Void>, Pointer<Void>, _CGRect),
        void Function(Pointer<_CGRect>, Pointer<Void>, Pointer<Void>, _CGRect)
      >('objc_msgSend_stret');

  _CGRect _viaStret(void Function(Pointer<_CGRect> out) send) {
    final out = _malloc(sizeOf<_CGRect>()).cast<_CGRect>();
    try {
      send(out);
      final rect = out.ref;
      return Struct.create<_CGRect>()
        ..x = rect.x
        ..y = rect.y
        ..width = rect.width
        ..height = rect.height;
    } finally {
      _free(out.cast());
    }
  }

  _CGRect _sendRect(Pointer<Void> receiver, Pointer<Void> selector) =>
      _stret ? _viaStret((out) => _sendRectStret(out, receiver, selector)) : _sendRectArm(receiver, selector);

  _CGRect _sendRectRect(Pointer<Void> receiver, Pointer<Void> selector, _CGRect rect) => _stret
      ? _viaStret((out) => _sendRectRectStret(out, receiver, selector, rect))
      : _sendRectRectArm(receiver, selector, rect);
  late final _sendVoidRectBool = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Void>, _CGRect, Bool),
        void Function(Pointer<Void>, Pointer<Void>, _CGRect, bool)
      >('objc_msgSend');

  final _selectors = <String, Pointer<Void>>{};

  Pointer<Void> _cString(String value, Pointer<Void> Function(Pointer<Uint8>) body) {
    final bytes = value.codeUnits;
    final buffer = _malloc(bytes.length + 1);
    for (var i = 0; i < bytes.length; i++) {
      buffer[i] = bytes[i];
    }
    buffer[bytes.length] = 0;
    try {
      return body(buffer);
    } finally {
      _free(buffer);
    }
  }

  Pointer<Void> _sel(String name) => _selectors.putIfAbsent(name, () => _cString(name, _registerName));

  Pointer<Void> _class(String name) => _cString(name, _getClass);

  void _checkThread() {
    if (_isMainThread() != 1) throw StateError('Dart does not run on the platform thread: AppKit/UIKit unsafe here');
  }

  List<Pointer<Void>> _array(Pointer<Void> array) {
    if (array == nullptr) return const [];
    final count = _sendUnsigned(array, _sel('count'));
    return [for (var i = 0; i < count; i++) _sendIdIndex(array, _sel('objectAtIndex:'), i)];
  }

  bool _isKind(Pointer<Void> object, Pointer<Void> cls) =>
      cls != nullptr && _sendBoolId(object, _sel('isKindOfClass:'), cls);

  Pointer<Void> get _app => Platform.isMacOS
      ? _sendId(_class('NSApplication'), _sel('sharedApplication'))
      : _sendId(_class('UIApplication'), _sel('sharedApplication'));

  List<Pointer<Void>> get _windows => _array(_sendId(_app, _sel('windows')));

  List<Pointer<Void>> _mapViews() {
    final mapClass = _class('MKMapView');
    final found = <Pointer<Void>>[];
    void visit(Pointer<Void> view) {
      if (view == nullptr) return;
      if (_isKind(view, mapClass)) {
        found.add(view);
        return;
      }
      _array(_sendId(view, _sel('subviews'))).forEach(visit);
    }

    for (final window in _windows) {
      visit(Platform.isMacOS ? _sendId(window, _sel('contentView')) : window);
    }
    return found;
  }

  /// One entry per MKMapView in the app's windows: the opacity of the view of each of its annotations other than
  /// the user location, `null` for an annotation that has no view (off-screen).
  List<List<double?>> annotationOpacities() {
    _checkThread();
    final userLocation = _class('MKUserLocation');
    final alpha = _sel(Platform.isMacOS ? 'alphaValue' : 'alpha');
    return [
      for (final map in _mapViews())
        [
          for (final annotation in _array(_sendId(map, _sel('annotations'))))
            if (!_isKind(annotation, userLocation))
              switch (_sendIdId(map, _sel('viewForAnnotation:'), annotation)) {
                final view when view == nullptr => null,
                final view => _sendDouble(view, alpha),
              },
        ],
    ];
  }

  Pointer<Void> get _flutterWindow {
    final windows = _windows.where((w) => _sendId(w, _sel('contentViewController')) != nullptr).toList();
    if (windows.isEmpty) throw StateError('no window with a content view controller');
    return windows.first;
  }

  /// macOS: whether any part of the test window is visible on screen (`NSWindowOcclusionStateVisible`).
  bool get windowVisible {
    _checkThread();
    return _sendUnsigned(_flutterWindow, _sel('occlusionState')) & 2 != 0;
  }

  /// macOS: unhides and activates the app, shows its window on the current Space (also over a full-screen app) and
  /// above the windows of other apps (floating level).
  void keepWindowInFront() {
    _checkThread();
    _sendIdId(_app, _sel('unhide:'), nullptr);
    _sendVoidBool(_app, _sel('activateIgnoringOtherApps:'), true);
    final window = _flutterWindow;
    const canJoinAllSpaces = 1 << 0;
    const fullScreenAuxiliary = 1 << 8;
    _sendVoidLong(window, _sel('setCollectionBehavior:'), canJoinAllSpaces | fullScreenAuxiliary);
    _sendVoidLong(window, _sel('setLevel:'), 3);
    _sendIdId(window, _sel('makeKeyAndOrderFront:'), nullptr);
    _sendVoid(window, _sel('orderFrontRegardless'));
  }

  void restoreWindowLevel() {
    _checkThread();
    _sendVoidLong(_flutterWindow, _sel('setLevel:'), 0);
  }

  /// macOS: hides or unhides the whole app (Cmd-H), which takes its window off screen.
  void setAppHidden(bool hidden) {
    _checkThread();
    _sendIdId(_app, _sel(hidden ? 'hide:' : 'unhide:'), nullptr);
  }

  /// macOS: resizes the test window's content area through the window's animator, keeping its top edge: AppKit then
  /// resizes it step by step from the run loop, as a live resize does. A direct `setContentSize:` from Dart would
  /// block for a second: the engine waits for a frame at the new size, which Dart (on the same thread) cannot draw.
  void animateWindowContentSize(double width, double height) {
    _checkThread();
    final window = _flutterWindow;
    final content = _sendRectRect(window, _sel('contentRectForFrameRect:'), _sendRect(window, _sel('frame')));
    final target = Struct.create<_CGRect>()
      ..x = content.x
      ..y = content.y + content.height - height
      ..width = width
      ..height = height;
    final frame = _sendRectRect(window, _sel('frameRectForContentRect:'), target);
    _sendVoidRectBool(_sendId(window, _sel('animator')), _sel('setFrame:display:'), frame, true);
  }
}

final class _CGRect extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;
}
