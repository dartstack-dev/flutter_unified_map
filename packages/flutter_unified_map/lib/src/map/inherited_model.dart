import 'package:flutter/widgets.dart';

import 'camera/map_camera.dart';
import 'controller/map_controller.dart';
import 'options/map_options.dart';

enum UnifiedMapAspect { camera, controller, options }

/// Exposes the live camera, controller and options to descendants of a `UnifiedMap`, by aspect so that a
/// widget reading only the controller does not rebuild on every camera change.
class UnifiedMapInheritedModel extends InheritedModel<UnifiedMapAspect> {
  final MapCamera camera;
  final MapController controller;
  final MapOptions options;

  const UnifiedMapInheritedModel({
    super.key,
    required this.camera,
    required this.controller,
    required this.options,
    required super.child,
  });

  static MapCamera? maybeCameraOf(BuildContext context) =>
      InheritedModel.inheritFrom<UnifiedMapInheritedModel>(context, aspect: UnifiedMapAspect.camera)?.camera;

  static MapController? maybeControllerOf(BuildContext context) =>
      InheritedModel.inheritFrom<UnifiedMapInheritedModel>(context, aspect: UnifiedMapAspect.controller)?.controller;

  static MapOptions? maybeOptionsOf(BuildContext context) =>
      InheritedModel.inheritFrom<UnifiedMapInheritedModel>(context, aspect: UnifiedMapAspect.options)?.options;

  @override
  bool updateShouldNotify(UnifiedMapInheritedModel oldWidget) =>
      camera != oldWidget.camera || controller != oldWidget.controller || options != oldWidget.options;

  @override
  bool updateShouldNotifyDependent(UnifiedMapInheritedModel oldWidget, Set<UnifiedMapAspect> dependencies) =>
      (dependencies.contains(UnifiedMapAspect.camera) && camera != oldWidget.camera) ||
      (dependencies.contains(UnifiedMapAspect.controller) && controller != oldWidget.controller) ||
      (dependencies.contains(UnifiedMapAspect.options) && options != oldWidget.options);
}
