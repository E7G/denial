part of 'home_surface.dart';

/// Home lifecycle and input boundary; paging and drag feedback stay separate.
class _HomeSurfaceView extends StatelessWidget {
  const _HomeSurfaceView({
    required this.owner,
    required this.active,
    required this.interactive,
    required this.contents,
  });

  final _HomeSurfaceState owner;
  final bool active;
  final bool interactive;
  final _HomePageContents contents;

  @override
  Widget build(BuildContext context) {
    final viewSize = MediaQuery.sizeOf(context);
    final tabletMode = viewSize.width >= 700;
    final contentPadding = tabletMode
        ? const EdgeInsets.fromLTRB(0, 104, 0, 8)
        : _HomeSurfaceState._contentPadding;
    final appItems =
        contents.slots
            ?.whereType<HomeGridItem>()
            .where((item) => item.type == HomeGridItemType.app)
            .toList(growable: false) ??
        const <HomeGridItem>[];

    final content = Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: contentPadding,
          child: _HomePager(owner: owner, contents: contents),
        ),
        if (tabletMode)
          Positioned(
            left: _HomeSurfaceState._pageHorizontalPadding,
            right: _HomeSurfaceState._pageHorizontalPadding,
            top: ShellMetrics.statusBarHeight + 8,
            child: _MetroStartHeader(onAllApps: owner._openAppDrawer),
          ),
        _HomeDragOverlay(owner: owner),
        if (owner._appDrawerOpen)
          Positioned.fill(
            child: _MetroAppDrawer(
              items: appItems,
              onClose: owner._closeAppDrawer,
              onLaunch: owner._launchFromAppDrawer,
            ),
          ),
      ],
    );
    final opacity = owner.widget.contentOpacity;
    return Offstage(
      offstage: !active,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !interactive,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: owner._handlePointerDown,
            onPointerMove: owner._handlePointerMove,
            onPointerUp: owner._handlePointerUp,
            onPointerCancel: owner._handlePointerUp,
            child: Stack(
              key: owner._homeStackKey,
              fit: StackFit.expand,
              children: [
                const CustomPaint(painter: HomeBackdropPainter()),
                if (opacity == null)
                  content
                else
                  FadeTransition(opacity: opacity, child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetroStartHeader extends StatelessWidget {
  const _MetroStartHeader({required this.onAllApps});

  final VoidCallback onAllApps;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'Start',
          style: TextStyle(
            color: Colors.white,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.7,
            shadows: [
              Shadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            'DENIAL TABLET',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.7,
            ),
          ),
        ),
        const Spacer(),
        _MetroHeaderAction(
          icon: Icons.apps_rounded,
          label: 'All apps',
          onTap: onAllApps,
        ),
        const SizedBox(width: 18),
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.swipe_down_alt_rounded,
                size: 17,
                color: Colors.white.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 6),
              Text(
                'Quick settings',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetroHeaderAction extends StatefulWidget {
  const _MetroHeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MetroHeaderAction> createState() => _MetroHeaderActionState();
}

class _MetroHeaderActionState extends State<_MetroHeaderAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.62 : 1,
          duration: const Duration(milliseconds: 80),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 20, color: Colors.white),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetroAppDrawer extends StatefulWidget {
  const _MetroAppDrawer({
    required this.items,
    required this.onClose,
    required this.onLaunch,
  });

  final List<HomeGridItem> items;
  final VoidCallback onClose;
  final void Function(HomeGridItem item, Rect sourceRect) onLaunch;

  @override
  State<_MetroAppDrawer> createState() => _MetroAppDrawerState();
}

class _MetroAppDrawerState extends State<_MetroAppDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _titleFor(BuildContext context, HomeGridItem item) {
    return item.localApp?.titleFor(context) ?? item.app?.name ?? item.id;
  }

  HomeGridItem _visualItem(HomeGridItem item) {
    final desktopApp = item.app;
    if (desktopApp != null) {
      return HomeGridItem.app(desktopApp);
    }
    return HomeGridItem.localApp(item.localApp!);
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _query.trim().toLowerCase();
    final items =
        widget.items
            .where((item) {
              if (normalized.isEmpty) {
                return true;
              }
              final title = _titleFor(context, item).toLowerCase();
              final desktopText = item.app?.searchableText ?? '';
              return title.contains(normalized) ||
                  desktopText.contains(normalized);
            })
            .toList(growable: false)
          ..sort(
            (a, b) => _titleFor(
              context,
              a,
            ).toLowerCase().compareTo(_titleFor(context, b).toLowerCase()),
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 760) {
          widget.onClose();
        }
      },
      child: ColoredBox(
        color: const Color(0xF2181D23),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            30,
            ShellMetrics.statusBarHeight + 14,
            30,
            22,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Back to Start',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'All apps',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 300,
                    height: 42,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: 'Search apps',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.50),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.white.withValues(alpha: 0.70),
                          size: 20,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.09),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                          borderSide: const BorderSide(
                            color: Colors.white,
                            width: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          normalized.isEmpty
                              ? 'No applications'
                              : 'No matching applications',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 16,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 150,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return HomeGridItemCard(
                            item: _visualItem(item),
                            onLaunch: (_, sourceRect) =>
                                widget.onLaunch(item, sourceRect),
                          );
                        },
                      ),
              ),
              Center(
                child: Text(
                  'Swipe down or tap Back to return to Start',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
