import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/src/raster/icon_cache.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

bool _isPng(Uint8List bytes) =>
    bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;

void main() {
  testWidgets('renders a widget off-screen to a PNG', (tester) async {
    final bytes = await tester.runAsync(
      () => WidgetRasterizer.render(
        const ColoredBox(color: Color(0xFFFF0000)),
        logicalSize: const Size(20, 10),
        pixelRatio: 2,
      ),
    );
    expect(bytes, isNotNull);
    expect(_isPng(bytes!), isTrue);
    final width = bytes.buffer.asByteData(bytes.offsetInBytes).getUint32(16);
    final height = bytes.buffer.asByteData(bytes.offsetInBytes).getUint32(20);
    expect((width, height), (40, 20));
  });

  testWidgets('captures the theme of the given context', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(iconTheme: const IconThemeData(color: Color(0xFF00FF00))),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final bytes = await tester.runAsync(
      () => WidgetRasterizer.render(
        const Icon(Icons.place),
        logicalSize: const Size(24, 24),
        pixelRatio: 1,
        context: context,
      ),
    );
    expect(_isPng(bytes!), isTrue);
  });

  Future<List<int>> firstPixel(WidgetTester tester, Uint8List png) async => (await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData();
    return data!.buffer.asUint8List().sublist(0, 4);
  }))!;

  testWidgets('a widget that rebuilds after its first frame is captured once it settled', (tester) async {
    final bytes = await tester.runAsync(
      () => WidgetRasterizer.render(const _LateColor(), logicalSize: const Size(4, 4), pixelRatio: 1),
    );
    expect(await firstPixel(tester, bytes!), [0, 0xFF, 0, 0xFF], reason: 'green, the color set after the first frame');
  });

  testWidgets('an image still decoding is waited for', (tester) async {
    final green = await tester.runAsync(
      () => WidgetRasterizer.render(
        const ColoredBox(color: Color(0xFF00FF00)),
        logicalSize: const Size(4, 4),
        pixelRatio: 1,
      ),
    );
    final bytes = await tester.runAsync(
      () => WidgetRasterizer.render(Image.memory(green!), logicalSize: const Size(4, 4), pixelRatio: 1),
    );
    expect(await firstPixel(tester, bytes!), [0, 0xFF, 0, 0xFF]);
  });

  testWidgets('IconCache gives one key per image and reuses it', (tester) async {
    final cache = IconCache(maxEntries: 2);
    const child = ColoredBox(color: Color(0xFF0000FF));
    final icons = await tester.runAsync(() async {
      final a = await cache.resolve(key: 'a', child: child, size: const Size(10, 10), pixelRatio: 1);
      final again = await cache.resolve(key: 'a', child: child, size: const Size(10, 10), pixelRatio: 1);
      final b = await cache.resolve(key: 'b', child: child, size: const Size(10, 10), pixelRatio: 1);
      final c = await cache.resolve(key: 'c', child: child, size: const Size(10, 10), pixelRatio: 1);
      return [a, again, b, c];
    });
    expect(icons![0].key, icons[1].key);
    expect({for (final i in icons) i.key}, hasLength(3));
    expect(cache.length, 2);
    expect(cache.lookup('a', const Size(10, 10), 1), isNull);
    expect(cache.lookup('c', const Size(10, 10), 1), isNotNull);
  });

  testWidgets('IconCache.clear drops renders still in flight', (tester) async {
    final cache = IconCache();
    const child = ColoredBox(color: Color(0xFF0000FF));
    final icons = await tester.runAsync(() async {
      final inFlight = cache.resolve(key: 'a', child: child, size: const Size(10, 10), pixelRatio: 1);
      cache.clear();
      final fresh = cache.resolve(key: 'a', child: child, size: const Size(10, 10), pixelRatio: 1);
      final first = await inFlight;
      final second = await fresh;
      return [first, second];
    });
    expect(icons![0].key, isNot(icons[1].key), reason: 'a render started after clear is not shared with the old one');
    expect(cache.length, 1);
    expect(cache.lookup('a', const Size(10, 10), 1)!.key, icons[1].key);
  });
}

class _LateColor extends StatefulWidget {
  const _LateColor();

  @override
  State<_LateColor> createState() => _LateColorState();
}

class _LateColorState extends State<_LateColor> {
  var _color = const Color(0xFFFF0000);

  @override
  void initState() {
    super.initState();
    Future<void>(() {
      if (mounted) setState(() => _color = const Color(0xFF00FF00));
    });
  }

  @override
  Widget build(BuildContext context) => ColoredBox(color: _color);
}
