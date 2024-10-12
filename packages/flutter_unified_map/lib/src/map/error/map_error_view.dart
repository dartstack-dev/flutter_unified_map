import 'package:flutter/material.dart';

import 'map_error.dart';

/// Default overlay shown by `UnifiedMap` when the platform reports a [MapError]. Replace it with
/// `UnifiedMap.errorBuilder`.
///
/// [compact] is used for a load error on a map that already loaded once: the tiles already on screen stay usable,
/// so a banner replaces the full-screen panel.
class MapErrorView extends StatelessWidget {
  final MapError error;
  final bool compact;

  const MapErrorView({super.key, required this.error, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (compact) {
      return SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              color: scheme.errorContainer,
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 20, color: scheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        error.title,
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return ColoredBox(
      color: scheme.surface.withValues(alpha: 0.92),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  error.code == MapErrorCode.apiKeyMissing ? Icons.key_off_outlined : Icons.map_outlined,
                  size: 40,
                  color: scheme.error,
                ),
                const SizedBox(height: 12),
                Text(error.title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                if (error.message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    error.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (error.hint.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(error.hint, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
