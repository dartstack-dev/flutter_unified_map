import 'package:flutter/material.dart';

/// Bottom-right one-line attribution, as flutter_map's. Place it in `UnifiedMap.children`.
class SimpleAttributionWidget extends StatelessWidget {
  final Text source;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Alignment alignment;

  const SimpleAttributionWidget({
    super.key,
    required this.source,
    this.onTap,
    this.backgroundColor,
    this.alignment = Alignment.bottomRight,
  });

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: ColoredBox(
      color: backgroundColor ?? Theme.of(context).colorScheme.surface,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('© '), source]),
        ),
      ),
    ),
  );
}
