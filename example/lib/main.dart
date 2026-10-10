import 'package:flutter/material.dart';

import 'package:flutter_unified_map_example/src/controls_page.dart';
import 'package:flutter_unified_map_example/src/europe_page.dart';
import 'package:flutter_unified_map_example/src/geometry_page.dart';
import 'package:flutter_unified_map_example/src/route_page.dart';
import 'package:flutter_unified_map_example/src/stations_page.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  // dartstack.dev accents: green-400 in light mode, green-300 in dark mode
  static const _seedLight = Color(0xFF409C3D);
  static const _seedDark = Color(0xFF8EEA88);

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: brightness == Brightness.light ? _seedLight : _seedDark,
      brightness: brightness,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UnifiedMaps',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    // ?brightness= is set by the site embedding the app, so it matches the page theme
    themeMode: switch (Uri.base.queryParameters['brightness']) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    },
    home: const DemoShell(),
  );
}

class DemoShell extends StatefulWidget {
  const DemoShell({super.key});

  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  var _index = const String.fromEnvironment('EUROPE_SCENE').isNotEmpty
      ? 4
      : const String.fromEnvironment('GEOMETRY_SCENE').isNotEmpty
      ? 2
      : 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: switch (_index) {
      0 => const StationsPage(),
      1 => const RoutePage(),
      2 => const GeometryPage(),
      3 => const ControlsPage(),
      _ => const EuropePage(),
    },
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.local_gas_station_outlined),
          selectedIcon: Icon(Icons.local_gas_station),
          label: 'Stations',
        ),
        NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Route'),
        NavigationDestination(icon: Icon(Icons.place_outlined), selectedIcon: Icon(Icons.place), label: 'Geometry'),
        NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Controls'),
        NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: 'Europe'),
      ],
    ),
  );
}
