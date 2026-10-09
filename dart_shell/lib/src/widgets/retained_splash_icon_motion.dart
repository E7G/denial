import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Moves the *already laid out* splash icon from the tapped tile's centre to
/// the centre of the output while the background grows. The child keeps its
/// full-screen layout; only its transform/paint changes each frame.
///
/// Without this, a large icon sits at screen centre even when the expanding
/// clip is still at its source tile, so the splash seems blank until late.
class RetainedSplashIconMotion extends SingleChildRenderObjectWidget {
  const RetainedSplashIconMotion({
    super.key,
    required this.progress,
    required this.begin,
    this.beginIsGlobal = false,
    required this.end,
    required this.iconSize,
    this.curve = Curves.linear,
    super.child,
  });

  final Animation<double> progress;
  final Rect begin;
  final bool beginIsGlobal;
  final Rect end;
  final double iconSize;
  final Curve curve;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSplashIconMotion(
        progress,
        begin,
        beginIsGlobal,
        end,
        iconSize,
        curve,
      );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSplashIconMotion).update(
      progress,
      begin,
      beginIsGlobal,
      end,
      iconSize,
      curve,
    );
  }
}

class _RenderSplashIconMotion extends RenderProxyBox {
  _RenderSplashIconMotion(
    this._progress,
    this.begin,
    this.beginIsGlobal,
    this.end,
    this.iconSize,
    this.curve,
  );

  Animation<double> _progress;
  Rect begin;
  bool beginIsGlobal;
  Rect end;
  double iconSize;
  Curve curve;
  final LayerHandle<TransformLayer> _transformLayer =
      LayerHandle<TransformLayer>();

  @override
  bool get isRepaintBoundary => true;

  void update(
    Animation<double> nextProgress,
    Rect nextBegin,
    bool nextBeginIsGlobal,
    Rect nextEnd,
    double nextIconSize,
    Curve nextCurve,
  ) {
    if (identical(_progress, nextProgress) &&
        begin == nextBegin &&
        beginIsGlobal == nextBeginIsGlobal &&
        end == nextEnd &&
        iconSize == nextIconSize &&
        curve == nextCurve) {
      return;
    }
    if (!identical(_progress, nextProgress)) {
      if (attached) _progress.removeListener(_invalidate);
      _progress = nextProgress;
      if (attached) _progress.addListener(_invalidate);
    }
    begin = nextBegin;
    beginIsGlobal = nextBeginIsGlobal;
    end = nextEnd;
    iconSize = nextIconSize;
    curve = nextCurve;
    _invalidate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_invalidate);
  }

  @override
  void detach() {
    _progress.removeListener(_invalidate);
    super.detach();
  }

  @override
  void dispose() {
    _transformLayer.layer = null;
    super.dispose();
  }

  void _invalidate() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  Matrix4 _iconTransform() {
    final source = beginIsGlobal
        ? Rect.fromPoints(
            globalToLocal(begin.topLeft),
            globalToLocal(begin.bottomRight),
          )
        : begin;
    final eased = curve.transform(_progress.value.clamp(0.0, 1.0));
    final finish = end.center;
    final centre = Offset.lerp(source.center, finish, eased)!;

    // The initial icon fits inside the tile; by the time the output expands,
    // it reaches the large, viewport-relative splash size.
    final initialScale = math.min(
      1.0,
      source.shortestSide * 0.68 / math.max(1.0, iconSize),
    );
    final scale = initialScale + (1.0 - initialScale) * eased;
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      centre.dx - scale * finish.dx,
      centre.dy - scale * finish.dy,
      0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) return;
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _iconTransform(),
      (context, offset) => context.paintChild(child!, offset),
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_iconTransform());
  }
}
