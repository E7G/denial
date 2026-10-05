part of 'home_tiles.dart';

class _HomeAppTile extends StatefulWidget {
  const _HomeAppTile({
    required this.identity,
    required this.name,
    required this.iconPath,
    required this.icon,
    required this.colSpan,
    required this.rowSpan,
    required this.onTap,
  });

  final String identity;
  final String name;
  final String? iconPath;
  final IconData? icon;
  final int colSpan;
  final int rowSpan;
  final ValueChanged<Rect>? onTap;

  @override
  State<_HomeAppTile> createState() => _HomeAppTileState();
}

class _HomeAppTileState extends State<_HomeAppTile> {
  final _tileKey = GlobalKey();
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) {
      return;
    }
    setState(() => _pressed = value);
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
    final tileColor = _metroTileColor(widget.identity);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.name,
      child: AnimatedScale(
        scale: _pressed ? 0.965 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
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
              final iconExtent = (shortest * (large ? 0.42 : 0.46))
                  .clamp(44.0, 96.0)
                  .toDouble();
              final labelSize = (shortest * 0.11)
                  .clamp(13.0, large ? 19.0 : 16.0)
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

              return DecoratedBox(
                key: _tileKey,
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
      ),
    );
  }
}
