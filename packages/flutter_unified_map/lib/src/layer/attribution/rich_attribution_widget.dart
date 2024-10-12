import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show AttributionAlignment, LogoSourceAttribution, SourceAttribution;

import 'rich_attribution_animation.dart';

/// flutter_map's `RichAttributionWidget`: a button that opens a popup listing the [attributions], with the
/// [LogoSourceAttribution]s always shown next to it. Place it in `UnifiedMap.children`.
///
/// Same fields, defaults and look as flutter_map's. [showFlutterMapAttribution] adds a "Made with
/// 'flutter_unified_map'" line in place of flutter_map's own logo and line. The popup closes on the next map event
/// after it was opened, as in flutter_map. Native maps also draw their mandatory Google or Apple attribution; move it
/// with `NativeParams.padding`.
class RichAttributionWidget extends StatefulWidget {
  final List<SourceAttribution> attributions;
  final AttributionAlignment alignment;
  final Widget Function(BuildContext context, VoidCallback open)? openButton;
  final Widget Function(BuildContext context, VoidCallback close)? closeButton;
  final Color? popupBackgroundColor;
  final BorderRadius? popupBorderRadius;
  final double permanentHeight;
  final bool showFlutterMapAttribution;
  final RichAttributionWidgetAnimation animationConfig;
  final Duration popupInitialDisplayDuration;

  const RichAttributionWidget({
    super.key,
    required this.attributions,
    this.alignment = AttributionAlignment.bottomRight,
    this.openButton,
    this.closeButton,
    this.popupBackgroundColor,
    this.popupBorderRadius,
    this.permanentHeight = 24,
    this.showFlutterMapAttribution = true,
    this.animationConfig = const FadeRAWA(),
    this.popupInitialDisplayDuration = Duration.zero,
  });

  @override
  State<RichAttributionWidget> createState() => _RichAttributionWidgetState();
}

class _RichAttributionWidgetState extends State<RichAttributionWidget> {
  static const _animation = Duration(milliseconds: 200);

  late bool _open = widget.popupInitialDisplayDuration > Duration.zero;
  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    if (_open) {
      _autoClose = Timer(widget.popupInitialDisplayDuration, () {
        if (mounted) setState(() => _open = false);
      });
    }
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  void _toggle() {
    _autoClose?.cancel();
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final right = widget.alignment == AttributionAlignment.bottomRight;
    final theme = Theme.of(context);
    final background = widget.popupBackgroundColor ?? theme.colorScheme.surface;
    return Align(
      alignment: right ? Alignment.bottomRight : Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: _animation,
              alignment: right ? Alignment.bottomRight : Alignment.bottomLeft,
              child: AnimatedSwitcher(
                duration: _animation,
                child: _open
                    ? Padding(
                        key: const ValueKey('popup'),
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: background,
                          elevation: 2,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: DefaultTextStyle.merge(
                              style: theme.textTheme.bodySmall,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 4,
                                children: [
                                  ...widget.attributions,
                                  if (widget.showFlutterMapAttribution)
                                    Text(
                                      "Made with 'flutter_unified_map'",
                                      style: TextStyle(color: theme.hintColor, fontStyle: FontStyle.italic),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('closed')),
              ),
            ),
            Material(
              color: background,
              elevation: 2,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Semantics(
                button: true,
                label: _open ? 'Hide attributions' : 'Show attributions',
                child: InkWell(
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(_open ? Icons.close : Icons.info_outline, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
