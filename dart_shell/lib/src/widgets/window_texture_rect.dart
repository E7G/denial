import 'package:flutter/widgets.dart';

import '../models/denial_window.dart';
import 'shell_backdrop_blur.dart';
import 'window_surface_tree.dart';

class WindowTextureRect extends StatelessWidget {
  const WindowTextureRect({
    super.key,
    required this.window,
    this.borderRadius = BorderRadius.zero,
    this.applyBackdrop = true,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.allowPopupOverflow = false,
    this.cropToContentBounds = false,
    this.sourceCropTop = 0.0,
  });

  final DenialWindow window;
  final BorderRadius borderRadius;
  final bool applyBackdrop;
  final BoxFit fit;
  final Alignment alignment;
  final bool allowPopupOverflow;
  final bool cropToContentBounds;
  final double sourceCropTop;

  @override
  Widget build(BuildContext context) {
    assert(
      !window.isLocalFlutter,
      'Local Flutter windows must be rendered through WindowContentRect.',
    );
    return ShellBackdropBlur(
      blur: applyBackdrop && !window.isOpaque,
      borderRadius: borderRadius,
      child: FittedBox(
        fit: fit,
        alignment: alignment,
        child: SizedBox(
          width: _presentationWidth(window, cropToContentBounds),
          height: _presentationHeight(
            window,
            cropToContentBounds,
            sourceCropTop,
          ),
          child: WindowSurfaceTree(
            window: window,
            includePopups: true,
            clipToBounds: !allowPopupOverflow,
            sourceCropTop: sourceCropTop,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    );
  }
}

double _presentationWidth(DenialWindow window, bool cropToContentBounds) {
  if (!cropToContentBounds) {
    return window.width.toDouble();
  }
  final scale = window.scale120 > 0 ? window.scale120 / 120.0 : 1.0;
  final width = window.presentationCoordinateRect.width * scale;
  return width > 0.0 ? width : window.width.toDouble();
}

double _presentationHeight(
  DenialWindow window,
  bool cropToContentBounds,
  double sourceCropTop,
) {
  if (!cropToContentBounds && sourceCropTop <= 0.0) {
    return window.height.toDouble();
  }
  final scale = window.scale120 > 0 ? window.scale120 / 120.0 : 1.0;
  final sourceHeight = window.presentationCoordinateRect.height;
  final visibleHeight = (sourceHeight - sourceCropTop).clamp(
    1.0,
    double.infinity,
  );
  final height = visibleHeight * scale;
  return height > 0.0 ? height : window.height.toDouble();
}
