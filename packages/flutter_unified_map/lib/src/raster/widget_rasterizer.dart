import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Renders a widget off-screen to PNG bytes at a device pixel ratio.
///
/// The widget is mounted under a private [BuildOwner] / [PipelineOwner] tree, so nothing appears on screen.
/// A widget that paints at once is captured once. A widget still waiting for something (an image not decoded yet,
/// or a state that rebuilds after the first frame, as SVG and network images do) is captured again once it rebuilt,
/// polling every [settleDelay] for at most [maxSettleTime]. What it shows then is the icon, and it stays in the
/// icon cache under its key: for deterministic icons, pass a pre-rendered image (`Image.memory`) and a stable
/// `iconKey`.
abstract class WidgetRasterizer {
  static const settleDelay = Duration(milliseconds: 16);
  static const maxSettleTime = Duration(milliseconds: 500);

  static Future<Uint8List> render(
    Widget widget, {
    required Size logicalSize,
    required double pixelRatio,
    BuildContext? context,
  }) async {
    // Read without depending on them: the map tracks the appearance itself and clears its icons when it changes.
    final view =
        (context != null ? View.maybeOf(context) : null) ??
        WidgetsBinding.instance.platformDispatcher.implicitView ??
        WidgetsBinding.instance.platformDispatcher.views.first;
    final mediaQuery = context?.getInheritedWidgetOfExactType<MediaQuery>()?.data ?? MediaQueryData.fromView(view);
    final themes = context != null ? InheritedTheme.capture(from: context, to: null) : null;
    final textDirection = context?.getInheritedWidgetOfExactType<Directionality>()?.textDirection ?? TextDirection.ltr;

    Widget tree = SizedBox.fromSize(size: logicalSize, child: widget);
    if (themes != null) tree = themes.wrap(tree);
    tree = MediaQuery(
      data: mediaQuery.copyWith(size: logicalSize, devicePixelRatio: pixelRatio, padding: EdgeInsets.zero),
      child: Directionality(textDirection: textDirection, child: tree),
    );

    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(logicalSize),
        physicalConstraints: BoxConstraints.tight(logicalSize * pixelRatio),
        devicePixelRatio: pixelRatio,
      ),
      child: RenderPositionedBox(alignment: Alignment.center, child: boundary),
    );
    final pipelineOwner = PipelineOwner();
    final focusManager = FocusManager();
    var rebuildScheduled = false;
    final buildOwner = BuildOwner(focusManager: focusManager, onBuildScheduled: () => rebuildScheduled = true);
    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: tree,
    ).attachToRenderTree(buildOwner);

    Future<ui.Image> capture() {
      rebuildScheduled = false;
      buildOwner.buildScope(rootElement);
      buildOwner.finalizeTree();
      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();
      return boundary.toImage(pixelRatio: pixelRatio);
    }

    ui.Image? image;
    try {
      var captured = image = await capture();
      await Future<void>.delayed(Duration.zero);
      final deadline = DateTime.now().add(maxSettleTime);
      while ((rebuildScheduled || _waitsForImage(boundary)) && DateTime.now().isBefore(deadline)) {
        if (!rebuildScheduled) {
          await Future<void>.delayed(settleDelay);
          continue;
        }
        captured.dispose();
        image = null;
        captured = image = await capture();
      }
      final data = await captured.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image?.dispose();
      RenderObjectToWidgetAdapter<RenderBox>(container: boundary).attachToRenderTree(buildOwner, rootElement);
      buildOwner.buildScope(rootElement);
      buildOwner.finalizeTree();
      pipelineOwner.rootNode = null;
      renderView.dispose();
      pipelineOwner.dispose();
      focusManager.dispose();
    }
  }

  static bool _waitsForImage(RenderObject root) {
    var waiting = false;
    void visit(RenderObject object) {
      if (waiting) return;
      if (object is RenderImage && object.image == null) {
        waiting = true;
        return;
      }
      object.visitChildren(visit);
    }

    visit(root);
    return waiting;
  }
}
