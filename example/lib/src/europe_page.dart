import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_unified_map_example/src/europe_data.dart';
import 'package:flutter_unified_map_example/src/europe_widgets.dart';
import 'package:flutter_unified_map_example/src/map_widgets.dart';

enum EuropeScene { markers, countries, routes, location, flag }

/// Scene forced at build time (`--dart-define=EUROPE_SCENE=routes`): hides the scene bar, used for the
/// documentation screenshots. Empty in interactive runs.
const _forcedScene = String.fromEnvironment('EUROPE_SCENE');

/// `--dart-define=EUROPE_STEPS=1`: cycle the accuracy circle through fixed steps instead of a smooth
/// pulse, so a sequence of screenshots can be assembled into a GIF.
const _steppedAccuracy = bool.fromEnvironment('EUROPE_STEPS');

EuropeScene? _sceneFromEnvironment() => EuropeScene.values.asNameMap()[_forcedScene];

class EuropePage extends StatefulWidget {
  const EuropePage({super.key});

  @override
  State<EuropePage> createState() => _EuropePageState();
}

class _EuropePageState extends State<EuropePage> {
  EuropeScene _scene = _sceneFromEnvironment() ?? EuropeScene.markers;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: switch (_scene) {
            EuropeScene.markers => const CapitalsScene(),
            EuropeScene.countries => const CountryScene(),
            EuropeScene.routes => const RoutesScene(),
            EuropeScene.location => const LocationScene(),
            EuropeScene.flag => const FlagScene(),
          },
        ),
        if (_sceneFromEnvironment() == null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final value in EuropeScene.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _SceneChip(
                          label: value.name,
                          selected: value == _scene,
                          onTap: () => setState(() => _scene = value),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SceneChip extends StatelessWidget {
  const _SceneChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: scheme.primary,
      labelStyle: TextStyle(color: selected ? scheme.onPrimary : scheme.onSurface, fontWeight: FontWeight.w600),
      backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.95),
      side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
    );
  }
}

abstract final class EuropeColors {
  static const green = Color(0xFF2F9E44);
  static const greenFill = Color(0x142F9E44);
  static const greenFillActive = Color(0x422F9E44);
  static const routeBlue = Color(0xFF1D6FF2);
  static const routeGold = Color(0xFFF59E0B);
  static const routeGreen = Color(0xFF14994F);
  static const locationBlue = Color(0xFF1A73E8);
}

CameraFit _europeFit() => CameraFit.bounds(bounds: europeBounds, padding: const EdgeInsets.fromLTRB(28, 48, 28, 48));

class CapitalsScene extends StatelessWidget {
  const CapitalsScene({super.key});

  @override
  Widget build(BuildContext context) {
    return UnifiedMap(
      options: MapOptions(initialCameraFit: _europeFit()),
      children: [
        MarkerLayer(
          markers: [
            for (final capital in europeCapitals)
              Marker(
                key: ValueKey(capital.city),
                point: capital.point,
                width: 30,
                height: 42,
                alignment: Alignment.topCenter,
                iconKey: capital.eu ? 'capital-eu' : 'capital-other',
                onTap: () => _show(context, capital.city),
                child: CapitalPin(eu: capital.eu),
              ),
          ],
        ),
      ],
    );
  }
}

class CountryScene extends StatefulWidget {
  const CountryScene({super.key});

  @override
  State<CountryScene> createState() => _CountrySceneState();
}

class _CountrySceneState extends State<CountryScene> {
  /// `--dart-define=EUROPE_HIGHLIGHT=POL`: country highlighted on load, for the documentation screenshot
  /// of a scene a tap would otherwise have to select.
  static final _forced = String.fromEnvironment('EUROPE_HIGHLIGHT');

  final _hits = LayerHitNotifier<String>(null);
  late CountryShape? _selected = _forced.isEmpty ? null : europeCountries.where((c) => c.iso == _forced).firstOrNull;

  @override
  void dispose() {
    _hits.dispose();
    super.dispose();
  }

  void _onTap(TapPosition tapPosition, LatLng point) {
    final hit = _hits.value?.hitValues.firstOrNull;
    final country = hit == null ? null : europeCountries.where((c) => c.iso == hit).firstOrNull;
    setState(() => _selected = country);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return UnifiedMap(
      options: MapOptions(initialCameraFit: _europeFit(), onTap: _onTap),
      children: [
        PolygonLayer<String>(
          hitNotifier: _hits,
          polygons: [
            for (final country in europeCountries)
              for (final ring in country.rings)
                Polygon(
                  points: ring,
                  color: country == _selected ? EuropeColors.greenFillActive : EuropeColors.greenFill,
                  borderColor: EuropeColors.green,
                  borderStrokeWidth: country == _selected ? 3 : 1.5,
                  label: country == _selected ? country.name : null,
                  labelStyle: text.titleSmall!.copyWith(color: const Color(0xFF14532D), fontWeight: FontWeight.w700),
                  hitValue: country.iso,
                ),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: MapCard(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _selected == null ? 'Tap a country to highlight it' : _selected!.name,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RoutesScene extends StatelessWidget {
  const RoutesScene({super.key});

  static final _fit = CameraFit.bounds(
    bounds: LatLngBounds.fromPoints([...commissionToParliament, ...commissionToCourt, ...commissionToEcb]),
    padding: const EdgeInsets.fromLTRB(30, 60, 30, 40),
  );

  @override
  Widget build(BuildContext context) {
    return UnifiedMap(
      options: MapOptions(initialCameraFit: _fit),
      children: [
        const PolylineLayer(
          polylines: [
            Polyline(
              points: commissionToParliament,
              strokeWidth: 5,
              color: EuropeColors.routeBlue,
              borderStrokeWidth: 2.5,
              borderColor: Color(0xFFFFFFFF),
            ),
            Polyline(
              points: commissionToCourt,
              strokeWidth: 5,
              color: EuropeColors.routeGold,
              borderStrokeWidth: 2.5,
              borderColor: Color(0xFFFFFFFF),
            ),
            Polyline(
              points: commissionToEcb,
              strokeWidth: 5,
              color: EuropeColors.routeGreen,
              borderStrokeWidth: 2.5,
              borderColor: Color(0xFFFFFFFF),
            ),
          ],
        ),
        const CircleLayer(
          circles: [
            CircleMarker(
              point: EuInstitutions.commission,
              radius: 7,
              color: Color(0xFFFFFFFF),
              borderStrokeWidth: 3,
              borderColor: EuropeColors.routeBlue,
            ),
            CircleMarker(
              point: EuInstitutions.parliament,
              radius: 7,
              color: Color(0xFFFFFFFF),
              borderStrokeWidth: 3,
              borderColor: EuropeColors.routeBlue,
            ),
            CircleMarker(
              point: EuInstitutions.court,
              radius: 7,
              color: Color(0xFFFFFFFF),
              borderStrokeWidth: 3,
              borderColor: EuropeColors.routeGold,
            ),
            CircleMarker(
              point: EuInstitutions.ecb,
              radius: 7,
              color: Color(0xFFFFFFFF),
              borderStrokeWidth: 3,
              borderColor: EuropeColors.routeGreen,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            _institution(EuInstitutions.commission, 'Commission', EuropeColors.routeBlue),
            _institution(EuInstitutions.parliament, 'Parliament', EuropeColors.routeBlue),
            _institution(EuInstitutions.court, 'Court of Justice', EuropeColors.routeGold),
            _institution(EuInstitutions.ecb, 'ECB', EuropeColors.routeGreen),
          ],
        ),
      ],
    );
  }
}

Marker _institution(LatLng point, String label, Color color) => Marker(
  key: ValueKey(label),
  point: point,
  width: 30 + label.length * 6.4,
  height: 30,
  alignment: Alignment.topCenter,
  iconKey: label,
  child: InstitutionBadge(label: label, color: color),
);

class InstitutionBadge extends StatelessWidget {
  const InstitutionBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: text.labelSmall!.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF111111)),
          ),
        ],
      ),
    );
  }
}

class LocationScene extends StatefulWidget {
  const LocationScene({super.key});

  @override
  State<LocationScene> createState() => _LocationSceneState();
}

class _LocationSceneState extends State<LocationScene> with SingleTickerProviderStateMixin {
  static const _steps = [350.0, 250.0, 150.0, 90.0, 50.0, 25.0, 50.0, 90.0, 150.0, 250.0];

  /// `--dart-define=EUROPE_SNAPSHOT=1` (with `EUROPE_STEPS=1`): the platform's own snapshot of each accuracy
  /// step is written to the app's documents folder, so the frames of the documentation GIF are captured even
  /// when the headless simulator does not composite its framebuffer.
  static const _snapshot = bool.fromEnvironment('EUROPE_SNAPSHOT');

  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 4))
    ..repeat(reverse: true);
  late final Animation<double> _radius = Tween(
    begin: 25.0,
    end: 350.0,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  final _controller = MapController();
  final _ready = Completer<void>();
  Timer? _stepTimer;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    if (_steppedAccuracy && !_snapshot) {
      _stepTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
        setState(() => _step = (_step + 1) % _steps.length);
      });
    } else if (_steppedAccuracy && _snapshot) {
      _captureSteps();
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _controller.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _captureSteps() async {
    await _ready.future;
    await Future<void>.delayed(const Duration(seconds: 4));
    final directory = await getApplicationDocumentsDirectory();
    for (final (index, radius) in _steps.indexed) {
      setState(() => _step = index);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final image = await _controller.takeSnapshot();
      if (image != null) {
        await File('${directory.path}/europe-location-$index.png').writeAsBytes(image);
        debugPrint('location snapshot $index (${radius.round()} m)');
      }
    }
    debugPrint('location snapshots done in ${directory.path}');
  }

  double get _accuracy => _steppedAccuracy ? _steps[_step] : _radius.value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget map() => UnifiedMap(
      mapController: _controller,
      options: MapOptions(initialCenter: someoneAtStrasbourg, initialZoom: 14.3, onMapReady: () => _ready.complete()),
      children: [
        CircleLayer(
          circles: [
            CircleMarker(
              point: someoneAtStrasbourg,
              radius: _accuracy,
              useRadiusInMeter: true,
              color: const Color(0x331A73E8),
              borderStrokeWidth: 1.5,
              borderColor: const Color(0x801A73E8),
            ),
          ],
        ),
        const MarkerLayer(
          markers: [
            Marker(
              key: ValueKey('location-dot'),
              point: someoneAtStrasbourg,
              width: 26,
              height: 26,
              iconKey: 'location-dot',
              child: LocationDot(),
            ),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: MapCard(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.my_location, size: 18, color: EuropeColors.locationBlue),
                  const SizedBox(width: 8),
                  Text('GPS accuracy: ±${_accuracy.round()} m', style: text.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    if (_steppedAccuracy) {
      return map();
    }
    return AnimatedBuilder(animation: _pulse, builder: (context, _) => map());
  }
}

class FlagScene extends StatelessWidget {
  const FlagScene({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return UnifiedMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: euBounds, padding: const EdgeInsets.all(24)),
      ),
      children: [
        PolygonLayer(
          polygons: [
            for (final country in euCountries)
              for (final ring in country.rings)
                Polygon(
                  points: ring,
                  color: const Color(0x0D2F9E44),
                  borderColor: const Color(0xFF2F9E44),
                  borderStrokeWidth: 1,
                ),
          ],
        ),
        const Positioned.fill(child: EuFlagOverlay()),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: MapCard(
              child: Text(
                'The European flag over the EU member states: aspect kept, covering the whole union, cut at the borders',
                style: text.bodyMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void _show(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 1)));
