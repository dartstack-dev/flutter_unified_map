// Ported from flutter_map 8.3.2 (`RichAttributionWidgetAnimation`), BSD-3-Clause, Copyright (c) 2018 the
// flutter_map authors.
import 'package:flutter/widgets.dart';

import 'rich_attribution_widget.dart';

/// How a [RichAttributionWidget] animates its popup and button. Same API as flutter_map's.
@immutable
abstract interface class RichAttributionWidgetAnimation {
  abstract final Duration buttonDuration;
  abstract final Curve buttonCurve;

  Widget popupAnimationBuilder({
    required BuildContext context,
    required bool isExpanded,
    required RichAttributionWidget config,
    required Widget child,
  });
}

/// The popup scales in from the button's corner.
@immutable
class ScaleRAWA implements RichAttributionWidgetAnimation {
  @override
  final Duration buttonDuration;
  @override
  final Curve buttonCurve;
  final Duration popupDuration;
  final Curve popupCurveIn;
  final Curve popupCurveOut;

  const ScaleRAWA({
    this.popupDuration = const Duration(milliseconds: 200),
    this.popupCurveIn = Curves.easeIn,
    this.popupCurveOut = Curves.easeOut,
    this.buttonDuration = const Duration(milliseconds: 200),
    this.buttonCurve = Curves.easeInOut,
  });

  @override
  Widget popupAnimationBuilder({
    required BuildContext context,
    required bool isExpanded,
    required RichAttributionWidget config,
    required Widget child,
  }) => AnimatedScale(
    scale: isExpanded ? 1 : 0,
    curve: isExpanded ? popupCurveOut : popupCurveIn,
    duration: buttonDuration,
    alignment: config.alignment.real,
    child: child,
  );
}

/// The popup fades in (the default).
@immutable
class FadeRAWA implements RichAttributionWidgetAnimation {
  @override
  final Duration buttonDuration;
  @override
  final Curve buttonCurve;
  final Duration popupDuration;
  final Curve popupCurveIn;
  final Curve popupCurveOut;

  const FadeRAWA({
    this.popupDuration = const Duration(milliseconds: 200),
    this.popupCurveIn = Curves.easeIn,
    this.popupCurveOut = Curves.easeOut,
    this.buttonDuration = const Duration(milliseconds: 200),
    this.buttonCurve = Curves.easeInOut,
  });

  @override
  Widget popupAnimationBuilder({
    required BuildContext context,
    required bool isExpanded,
    required RichAttributionWidget config,
    required Widget child,
  }) => AnimatedOpacity(
    opacity: isExpanded ? 1 : 0,
    curve: isExpanded ? popupCurveOut : popupCurveIn,
    duration: buttonDuration,
    child: IgnorePointer(ignoring: !isExpanded, child: child),
  );
}
