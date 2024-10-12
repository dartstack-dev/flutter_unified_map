import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map_apple/flutter_unified_map_apple.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

// Kept in its own file: the generated plugin registrant calls registerWith before main(), so the binding must not
// have been initialised by another test in the same isolate.
void main() {
  test('registerWith works before the Flutter binding exists', () {
    UnifiedMapsApple.registerWith();
    expect(UnifiedMapsPlatform.instance, isA<UnifiedMapsApple>());
  });
}
