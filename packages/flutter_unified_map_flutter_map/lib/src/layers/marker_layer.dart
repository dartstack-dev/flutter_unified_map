import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_unified_map_flutter_map/src/marker_store.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

/// Key of the subtree drawing the marker [id], in every world copy.
Key markerKey(String id) => ValueKey(('marker', id));

/// The markers of [frames] in a flutter_map `MarkerLayer`. Each marker is keyed by its id so that its state follows
/// it when the list changes, except while the view is about as wide as the world: flutter_map then draws a marker
/// once per visible world copy, all with the marker's key, and duplicate keys are an error.
class MarkerFramesLayer extends StatefulWidget {
  const MarkerFramesLayer({super.key, required this.frames, required this.exclusions, required this.onTap});

  final List<MarkerFrame> frames;
  final SnapshotExclusions exclusions;
  final void Function(String markerId) onTap;

  @override
  State<MarkerFramesLayer> createState() => _MarkerFramesLayerState();
}

class _MarkerFramesLayerState extends State<MarkerFramesLayer> {
  List<MarkerFrame>? _frames;
  double _maxExtent = 0;
  bool? _keyed;
  late MarkerLayer _layer;

  @override
  Widget build(BuildContext context) {
    final frames = widget.frames;
    if (!identical(frames, _frames)) {
      _maxExtent = frames.fold(0.0, (m, f) => math.max(m, f.marker.icon.logicalSize.longestSide));
    }
    final camera = MapCamera.of(context);
    final keyed = camera.pixelBounds.width + 2 * _maxExtent < camera.getWorldWidthAtZoom();
    // Returning the same widget lets a camera move skip MarkerLayer's update, which re-projects every marker.
    if (!identical(frames, _frames) || keyed != _keyed) {
      _frames = frames;
      _keyed = keyed;
      _layer = _markerLayer(frames, keyed: keyed);
    }
    return _layer;
  }

  MarkerLayer _markerLayer(List<MarkerFrame> frames, {required bool keyed}) => MarkerLayer(
    markers: [
      for (final MarkerFrame(:marker, :position, :opacity, :disappearing) in frames)
        Marker(
          key: keyed ? ValueKey('marker:${marker.id}') : null,
          point: position,
          width: marker.icon.logicalSize.width,
          height: marker.icon.logicalSize.height,
          alignment: Alignment(1 - 2 * marker.anchor.dx, 1 - 2 * marker.anchor.dy),
          rotate: !marker.flat,
          child: KeyedSubtree(
            key: markerKey(marker.id),
            child: IgnorePointer(
              ignoring: disappearing,
              child: MarkerOpacity(
                opacity: opacity.clamp(0, 1),
                exclusions: widget.exclusions,
                excludedFromSnapshots: disappearing,
                child: MarkerIcon(marker: marker, onTap: marker.tappable ? () => widget.onTap(marker.id) : null),
              ),
            ),
          ),
        ),
    ],
  );
}

/// Disappearing markers are left out of snapshots without touching the screen: their opacity layers are made
/// transparent only while [capture] builds the snapshot scene, which `RenderRepaintBoundary.toImage` does
/// synchronously, and restored before any frame can show them.
class SnapshotExclusions {
  final _excluded = <RenderMarkerOpacity>{};

  T capture<T>(T Function() capture) {
    final hidden = [
      for (final render in _excluded)
        if (render.compositedLayer case final OpacityLayer layer?) (layer, layer.alpha ?? 255),
    ];
    for (final (layer, _) in hidden) {
      layer.alpha = 0;
    }
    try {
      return capture();
    } finally {
      for (final (layer, alpha) in hidden) {
        layer.alpha = alpha;
      }
    }
  }
}

class MarkerOpacity extends SingleChildRenderObjectWidget {
  const MarkerOpacity({
    super.key,
    required this.opacity,
    required this.exclusions,
    required this.excludedFromSnapshots,
    super.child,
  });

  final double opacity;
  final SnapshotExclusions exclusions;
  final bool excludedFromSnapshots;

  @override
  RenderMarkerOpacity createRenderObject(BuildContext context) =>
      RenderMarkerOpacity(opacity: opacity, exclusions: exclusions, excluded: excludedFromSnapshots);

  @override
  void updateRenderObject(BuildContext context, RenderMarkerOpacity renderObject) {
    renderObject
      ..opacity = opacity
      ..exclusions = exclusions
      ..excluded = excludedFromSnapshots;
  }
}

/// Unlike `RenderOpacity`, an opaque marker paints into its parent's layer: hundreds of static markers would
/// otherwise each be an `OpacityLayer` to composite on every camera frame. Markers excluded from snapshots keep
/// their layer, which the snapshot hides.
class RenderMarkerOpacity extends RenderOpacity {
  RenderMarkerOpacity({super.opacity, required this._exclusions, required this._excluded});

  SnapshotExclusions _exclusions;
  bool _excluded;

  @override
  bool get alwaysNeedsCompositing {
    final alpha = Color.getAlphaFromOpacity(opacity);
    return child != null && alpha > 0 && (alpha < 255 || _excluded);
  }

  set exclusions(SnapshotExclusions value) {
    if (identical(value, _exclusions)) return;
    _exclusions._excluded.remove(this);
    _exclusions = value;
    _register();
  }

  set excluded(bool value) {
    if (value == _excluded) return;
    final didNeedCompositing = alwaysNeedsCompositing;
    _excluded = value;
    if (didNeedCompositing != alwaysNeedsCompositing) markNeedsCompositingBitsUpdate();
    _register();
  }

  OpacityLayer? get compositedLayer => isRepaintBoundary ? layer as OpacityLayer? : null;

  void _register() {
    if (attached && _excluded) {
      _exclusions._excluded.add(this);
    } else {
      _exclusions._excluded.remove(this);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _register();
  }

  @override
  void detach() {
    _exclusions._excluded.remove(this);
    super.detach();
  }
}

class MarkerIcon extends StatelessWidget {
  const MarkerIcon({super.key, required this.marker, this.onTap});

  final PlatformMarker marker;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = marker.icon;
    Widget child = Image.memory(
      icon.bytes,
      width: icon.logicalSize.width,
      height: icon.logicalSize.height,
      scale: icon.pixelRatio,
      fit: BoxFit.fill,
      gaplessPlayback: true,
    );
    if (marker.rotation != 0) {
      child = Transform.rotate(
        angle: marker.rotation * math.pi / 180,
        alignment: Alignment(2 * marker.anchor.dx - 1, 2 * marker.anchor.dy - 1),
        child: child,
      );
    }
    if (onTap == null) return child;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child);
  }
}
