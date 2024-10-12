import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' as p;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

import 'support/harness.dart';

/// A flutter_map layer, as flutter_map_marker_cluster's: it needs the map's camera and controller.
class _CameraProbe extends StatelessWidget {
  const _CameraProbe(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final camera = fm.MapCamera.of(context);
    fm.MapController.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Text('$label ${camera.zoom}', textDirection: TextDirection.ltr),
    );
  }
}

class _Born extends StatefulWidget {
  const _Born(this.label, {super.key});

  final String label;

  @override
  State<_Born> createState() => _BornState();
}

class _BornState extends State<_Born> {
  late final String born = widget.label;

  @override
  Widget build(BuildContext context) => Text('${widget.label} born $born', textDirection: TextDirection.ltr);
}

class _LayersFromBuild extends StatelessWidget {
  const _LayersFromBuild(this.platform, this.label);

  final UnifiedMapsFlutterMap platform;
  final String label;

  @override
  Widget build(BuildContext context) {
    platform.setFlutterMapLayers(1, [_CameraProbe(label)]);
    return const SizedBox.shrink();
  }
}

Future<UnifiedMapsFlutterMap> _pumpMap(WidgetTester tester, {UnifiedMapsFlutterMap? platform}) async {
  platform ??= UnifiedMapsFlutterMap();
  await tester.pumpWidget(MaterialApp(home: platform.buildView(viewId: 1, options: noBaseMapOptions)));
  await tester.pump();
  return platform;
}

void main() {
  testWidgets('flutter_map layers render inside the map and see its camera', (tester) async {
    final platform = await _pumpMap(tester);
    expect(platform.supportsFlutterMapLayers, isTrue);

    platform.setFlutterMapLayers(1, const [_CameraProbe('first'), _CameraProbe('second')]);
    await tester.pump();

    expect(find.text('first 10.0'), findsOneWidget);
    expect(find.text('second 10.0'), findsOneWidget);
    expect(find.descendant(of: find.byType(fm.FlutterMap), matching: find.byType(_CameraProbe)), findsNWidgets(2));

    await platform.moveCamera(1, const PlatformCameraUpdate.newCamera(zoom: 12));
    await tester.pump();
    expect(find.text('first 12.0'), findsOneWidget);
  });

  testWidgets('layers are drawn above markers and shapes, in list order', (tester) async {
    final platform = await _pumpMap(tester);
    await platform.updateMarkers(
      1,
      MapObjectUpdates(
        added: [
          PlatformMarker(
            id: 'm',
            position: paris,
            icon: PlatformIcon(key: 'dot', bytes: transparentPng, logicalSize: const Size(20, 20), pixelRatio: 2),
            anchor: const p.Offset(0.5, 0.5),
          ),
        ],
      ),
    );
    platform.setFlutterMapLayers(1, const [_CameraProbe('a'), _CameraProbe('b')]);
    await tester.pump();

    final order = <Widget>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is fm.MarkerLayer || widget is _CameraProbe) order.add(widget);
      element.visitChildren(visit);
    }

    tester.element(find.byType(fm.FlutterMap)).visitChildren(visit);
    expect(order.map((w) => w is _CameraProbe ? w.label : 'markers'), ['markers', 'a', 'b']);
  });

  testWidgets('layers set before the view exists are drawn once it mounts', (tester) async {
    final platform = UnifiedMapsFlutterMap()..setFlutterMapLayers(1, const [_CameraProbe('early')]);
    await _pumpMap(tester, platform: platform);

    expect(find.text('early 10.0'), findsOneWidget);
  });

  testWidgets('a new list replaces the previous one; an empty list removes them', (tester) async {
    final platform = await _pumpMap(tester);
    platform.setFlutterMapLayers(1, const [_CameraProbe('one')]);
    await tester.pump();

    platform.setFlutterMapLayers(1, const [_CameraProbe('two')]);
    await tester.pump();
    expect(find.text('one 10.0'), findsNothing);
    expect(find.text('two 10.0'), findsOneWidget);

    platform.setFlutterMapLayers(1, const []);
    await tester.pump();
    expect(find.byType(_CameraProbe), findsNothing);
  });

  testWidgets('layers set from another widget build are drawn without a build error', (tester) async {
    final platform = UnifiedMapsFlutterMap();
    Widget app(String label) => MaterialApp(
      home: Stack(
        children: [
          platform.buildView(viewId: 1, options: noBaseMapOptions),
          _LayersFromBuild(platform, label),
        ],
      ),
    );
    await tester.pumpWidget(app('built'));
    await tester.pump();
    await tester.pump();
    expect(find.text('built 10.0'), findsOneWidget);

    await tester.pumpWidget(app('rebuilt'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('rebuilt 10.0'), findsOneWidget);
  });

  testWidgets('a disposed view ignores flutter_map layers', (tester) async {
    final platform = await _pumpMap(tester);
    await platform.dispose(1);

    platform.setFlutterMapLayers(1, const [_CameraProbe('late')]);
    await tester.pump();

    expect(find.byType(_CameraProbe), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keyed layers keep their own state when a layer before them is removed', (tester) async {
    final platform = await _pumpMap(tester);
    platform.setFlutterMapLayers(1, const [_Born('A', key: ValueKey('A')), _Born('B', key: ValueKey('B'))]);
    await tester.pump();

    platform.setFlutterMapLayers(1, const [_Born('B', key: ValueKey('B'))]);
    await tester.pump();

    expect(find.text('B born B'), findsOneWidget);
    expect(find.text('A born A'), findsNothing);
  });
}
