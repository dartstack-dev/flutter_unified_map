# flutter_unified_map_platform_interface

Common platform interface for [`flutter_unified_map`](../flutter_unified_map). Platform implementations extend `UnifiedMapsPlatform` and set `UnifiedMapsPlatform.instance`.

This package follows the federated plugin pattern. Breaking changes are avoided; new methods get a default implementation that throws `UnimplementedError`.
