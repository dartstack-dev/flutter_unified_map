import 'package:flutter/material.dart';

import 'package:flutter_unified_map_example/src/controls_page.dart';
import 'package:flutter_unified_map_example/src/europe_page.dart';
import 'package:flutter_unified_map_example/src/geometry_page.dart';
import 'package:flutter_unified_map_example/src/route_page.dart';
import 'package:flutter_unified_map_example/src/stations_page.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  static const _seed = Color(0xFF0F766E);

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UnifiedMaps',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const DemoShell(),
  );
}

class DemoShell extends StatefulWidget {
  const DemoShell({super.key});

  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  var _index = const String.fromEnvironment('EUROPE_SCENE').isEmpty ? 0 : 4;

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
