import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    home: Scaffold(body: Stack(children: [child])),
  );

  testWidgets('toggles the attribution popup', (tester) async {
    await tester.pumpWidget(app(const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap')])));
    expect(find.text('© OpenStreetMap'), findsNothing);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('© OpenStreetMap'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('© OpenStreetMap'), findsNothing);
  });

  testWidgets('shows the popup for popupInitialDisplayDuration, aligned left', (tester) async {
    await tester.pumpWidget(
      app(
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          popupInitialDisplayDuration: Duration(seconds: 2),
          attributions: [TextSourceAttribution('Tiles', prependCopyright: false)],
        ),
      ),
    );
    expect(find.text('Tiles'), findsOneWidget);
    expect(tester.getBottomLeft(find.byType(Icon)).dx, lessThan(100));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Tiles'), findsNothing);
  });
}
