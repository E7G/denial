import 'package:denial_sdk/composition.dart';
import 'package:flutter/widgets.dart';

import 'services.dart';

enum PanelEdge {
  left,
  right,
  top,
  bottom,
  hidden;

  bool get isHorizontal => this == top || this == bottom;
}

/// Fixed placement used for both presentation and native work-area reservation.
class PanelPlacement {
  const PanelPlacement({
    required this.edge,
    required this.thickness,
    this.reserveWindowSpacing = false,
  }) : assert(edge != PanelEdge.hidden),
       assert(thickness > 0);
  final PanelEdge edge;

  /// Painted panel thickness, excluding the reserved window-facing gap.
  final double thickness;

  /// Reserve the host's configured window spacing beside the panel. The host
  /// aligns the painted panel to its output edge inside this larger reservation.
  final bool reserveWindowSpacing;

  double reservedThickness(double windowSpacing) =>
      thickness +
      (reserveWindowSpacing && windowSpacing.isFinite && windowSpacing > 0
          ? windowSpacing
          : 0);
}

/// Builds a panel in an output-local rectangle supplied by the shell.
///
/// Placement, workspace reservation, and secure-session ordering remain the
/// host's responsibility. This contract supplies presentation, not a new layout
/// protocol. Implementations must respect the supplied edge and constraints.
@ExtensionPoint(cardinality: ContributionCardinality.zeroOrMore)
abstract interface class ShellPanel {
  /// Null preserves the host's configured edge and thickness.
  PanelPlacement? get placement;

  Widget build(
    BuildContext context, {
    required int monitorId,
    required PanelEdge edge,
    required ShellServices services,
  });
}
