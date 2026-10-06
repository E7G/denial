part of 'home_tiles.dart';

class _HomeAppTile extends StatefulWidget {
  const _HomeAppTile({
    required this.identity,
    required this.name,
    required this.iconPath,
    required this.icon,
    required this.colSpan,
    required this.rowSpan,
    required this.tileColorValue,
    required this.tileOpacity,
    required this.metroEnabled,
    required this.animationStrength,
    required this.onTap,
  });

  final String identity;
  final String name;
  final String? iconPath;
  final IconData? icon;
  final int colSpan;
  final int rowSpan;
  final int? tileColorValue;
  final double tileOpacity;
  final bool metroEnabled;
  final double animationStrength;
  final ValueChanged<Rect>? onTap;

  @override
  State<_HomeAppTile> createState() => _HomeAppTileState();
}

class _HomeAppTileState extends State<_HomeAppTile> {
  final _tileKey = GlobalKey();
  bool _pressed = false;
  Offset? _pressPoint;

  void _setPressed(bool value, [Offset? localPosition]) {
    if (!mounted) {
      return;
    }
    if (_pressed == value &&
        (localPosition == null || localPosition == _pressPoint)) {
      return;
    }
    setState(() {
      _pressed = value;
      _pressPoint = value ? localPosition ?? _pressPoint : null;
    });
  }

  void _launch() {
    _setPressed(false);
    final render = _tileKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) {
      return;
    }
    widget.onTap?.call(
      MatrixUtils.transformRect(
        render.getTransformTo(null),
        Offset.zero & render.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final tileColor = widget.metroEnabled
        ? metroTileColor(
            widget.identity,
            widget.tileColorValue,
          ).withValues(alpha: widget.tileOpacity)
        : const Color(0x33101419);
    final pressScale = 1 - 0.035 * widget.animationStrength.clamp(0.0, 1.5);
    final motionStrength = widget.animationStrength.clamp(0.0, 1.5);
    final pressDuration = Duration(
      milliseconds: ((_pressed ? 58 : 118) * motionStrength).round(),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled
            ? (details) => _setPressed(true, details.localPosition)
            : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTap: enabled ? _launch : null,
        child: LayoutBuilder(
            builder: (context, constraints) {
              final shortest = math.min(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final wide = widget.colSpan > 1 && widget.rowSpan == 1;
              final large = widget.colSpan > 1 && widget.rowSpan > 1;
              final iconExtent = (shortest * (large ? 0.50 : 0.60))
                  .clamp(60.0, 128.0)
                  .toDouble();
              final labelSize = (shortest * 0.12)
                  .clamp(15.0, large ? 21.0 : 18.0)
                  .toDouble();

              final iconWidget = SizedBox.square(
                dimension: iconExtent,
                child: widget.icon == null
                    ? AppIconImage(iconPath: widget.iconPath)
                    : ExcludeSemantics(
                        child: Icon(
                          widget.icon,
                          size: iconExtent * 0.82,
                          color: Colors.white,
                        ),
                      ),
              );

              final local = _pressPoint;
              final nx = local == null || constraints.maxWidth <= 0
                  ? 0.0
                  : (local.dx / constraints.maxWidth - 0.5).clamp(-0.5, 0.5);
              final ny = local == null || constraints.maxHeight <= 0
                  ? 0.0
                  : (local.dy / constraints.maxHeight - 0.5).clamp(-0.5, 0.5);
              final transform = Matrix4.identity()
                ..setEntry(3, 2, 0.0014)
                ..rotateX(_pressed ? -ny * 0.10 * widget.animationStrength : 0)
                ..rotateY(_pressed ? nx * 0.12 * widget.animationStrength : 0)
                ..scaleByDouble(
                  _pressed ? pressScale : 1.0,
                  _pressed ? pressScale : 1.0,
                  1.0,
                  1.0,
                );
              return AnimatedContainer(
                key: _tileKey,
                duration: pressDuration,
                curve: Curves.easeOutCubic,
                transform: transform,
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.055),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (wide)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 12, 24),
                          child: iconWidget,
                        ),
                      )
                    else
                      Align(
                        alignment: large
                            ? const Alignment(0, -0.12)
                            : const Alignment(0, -0.18),
                        child: iconWidget,
                      ),
                    Positioned(
                      left: 12,
                      right: 10,
                      bottom: 10,
                      child: Text(
                        widget.name,
                        maxLines: wide || large ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: labelSize,
                          height: 1.05,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                          shadows: const [
                            Shadow(
                              color: Color(0x55000000),
                              blurRadius: 5,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (large)
                      const Positioned(
                        top: 10,
                        right: 10,
                        child: Icon(
                          Icons.grid_view_rounded,
                          size: 16,
                          color: Color(0xBFFFFFFF),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
  }
}
