part of 'home_surface.dart';

/// Home lifecycle and input boundary; paging and drag feedback stay separate.
class _HomeSurfaceView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final viewSize = MediaQuery.sizeOf(context);
    final tabletSettings = ref.watch(
      shellSettingsProvider.select((settings) => settings.tablet),
    );
    final portrait = viewSize.height > viewSize.width;
    final tabletMode = tabletSettings.enabled && viewSize.width >= 700;
    final compactPortrait =
        tabletMode &&
        tabletSettings.portraitCompact &&
        viewSize.height > viewSize.width;
    final showHeader =
        tabletMode && tabletSettings.showStartHeader && !compactPortrait;
    final contentPadding = showHeader
        ? const EdgeInsets.fromLTRB(0, 104, 0, 8)
        : _HomeSurfaceState._contentPadding;
    final allItems = contents.allItems ?? const <HomeGridItem>[];
    final appItems = allItems
        .where((item) => item.isApplication)
        .toList(growable: false);
    final systemItems = tabletSettings.showSystemTiles
        ? allItems.where((item) => item.isSystemTile).toList(growable: false)
        : const <HomeGridItem>[];
    final pinnedIds = <String>{
      for (final item in contents.slots ?? const <HomeGridItem?>[])
        if (item != null) item.id,
    };

    final content = Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: contentPadding,
          child: _HomePager(owner: owner, contents: contents),
        ),
        if (showHeader)
          Positioned(
            left: _HomeSurfaceState._pageHorizontalPadding,
            right: _HomeSurfaceState._pageHorizontalPadding,
            top: ShellMetrics.statusBarHeight + 8,
            child: _MetroStartHeader(
              onAllApps: owner._openAppDrawer,
              onSemanticZoom: owner._openSemanticZoom,
              showSemanticZoom: !portrait && owner._currentPageCount > 1,
              showQuickSettingsHint: tabletSettings.showQuickSettingsHint,
            ),
          )
        else
          Positioned(
            right: _HomeSurfaceState._pageHorizontalPadding,
            top: ShellMetrics.statusBarHeight + 6,
            child: _MetroHeaderAction(
              icon: Icons.apps_rounded,
              label: context.l10n.tabletAppsShort,
              onTap: owner._openAppDrawer,
            ),
          ),
        _HomeDragOverlay(owner: owner),
        if (owner._appDrawerOpen)
          Positioned.fill(
            child: _MetroAppDrawer(
              focusSearch: owner._appDrawerFocusSearch,
              items: appItems,
              systemItems: systemItems,
              pinnedIds: pinnedIds,
              onClose: owner._closeAppDrawer,
              onLaunch: owner._launchFromAppDrawer,
              onTogglePin: owner._togglePinFromAppDrawer,
              onCreateFolder: owner._createFolderFromDrawer,
            ),
          ),
        if (owner._openFolder case final folder?)
          Positioned.fill(
            child: _MetroFolderOverlay(
              folder: folder,
              onClose: owner._closeFolder,
              onLaunch: owner._launchFromFolder,
              onRename: owner._renameOpenFolder,
            ),
          ),
        if (owner._semanticZoomOpen)
          Positioned.fill(
            child: _MetroSemanticZoomOverlay(
              slots: contents.slots ?? const <HomeGridItem?>[],
              pageSize: owner._currentPageSize,
              pageCount: owner._currentPageCount,
              activePage:
                  ref.read(homeGridControllerProvider).asData?.value.page ?? 0,
              groupNames:
                  ref.read(homeGridControllerProvider).asData?.value.groupNames ??
                  const <int, String>{},
              onClose: owner._closeSemanticZoom,
              onSelectPage: owner._jumpToStartGroup,
              onRenamePage: owner._renameStartGroup,
            ),
          ),
        if (owner._charmsOpen)
          Positioned.fill(
            child: _MetroCharmsRail(
              onClose: owner._closeCharms,
              onSearch: () => owner._openAppDrawer(focusSearch: true),
              onStart: owner._closeCharms,
              onDevices: owner._openBluetoothFromCharms,
              onSettings: owner._openSettingsFromCharms,
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
  const _MetroStartHeader({
    required this.onAllApps,
    required this.onSemanticZoom,
    required this.showSemanticZoom,
    required this.showQuickSettingsHint,
  });

  final VoidCallback onAllApps;
  final VoidCallback onSemanticZoom;
  final bool showSemanticZoom;
  final bool showQuickSettingsHint;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          context.l10n.tabletStartTitle,
          style: const TextStyle(
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
          label: context.l10n.tabletAllApps,
          onTap: onAllApps,
        ),
        if (showSemanticZoom) ...[
          const SizedBox(width: 12),
          _MetroHeaderAction(
            icon: Icons.zoom_out_map_rounded,
            label: 'Groups',
            onTap: onSemanticZoom,
          ),
        ],
        if (showQuickSettingsHint) ...[
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
                  context.l10n.tabletQuickSettings,
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
    required this.focusSearch,
    required this.items,
    required this.systemItems,
    required this.pinnedIds,
    required this.onClose,
    required this.onLaunch,
    required this.onTogglePin,
    required this.onCreateFolder,
  });

  final bool focusSearch;
  final List<HomeGridItem> items;
  final List<HomeGridItem> systemItems;
  final Set<String> pinnedIds;
  final VoidCallback onClose;
  final void Function(HomeGridItem item, Rect sourceRect) onLaunch;
  final ValueChanged<HomeGridItem> onTogglePin;
  final void Function(String name, Iterable<HomeGridItem> items) onCreateFolder;

  @override
  State<_MetroAppDrawer> createState() => _MetroAppDrawerState();
}

class _MetroAppDrawerState extends State<_MetroAppDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _folderNameController = TextEditingController();
  final ScrollController _appListController = ScrollController();
  final Map<String, GlobalKey> _letterKeys = <String, GlobalKey>{};
  final Set<String> _folderSelection = <String>{};
  String _query = '';
  bool _folderMode = false;

  @override
  void dispose() {
    _searchController.dispose();
    _folderNameController.dispose();
    _appListController.dispose();
    super.dispose();
  }

  String _titleFor(BuildContext context, HomeGridItem item) {
    return item.localApp?.titleFor(context) ?? item.app?.name ?? item.id;
  }

  String _letterFor(BuildContext context, HomeGridItem item) {
    final title = _titleFor(context, item).trim();
    if (title.isEmpty) {
      return '#';
    }
    final letter = title.substring(0, 1).toUpperCase();
    final unit = letter.codeUnitAt(0);
    return unit >= 65 && unit <= 90 ? letter : '#';
  }

  Future<void> _showAlphabetJump(
    BuildContext context,
    Set<String> availableLetters,
  ) async {
    final selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => _MetroAlphabetJumpDialog(
        availableLetters: availableLetters,
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    final keyContext = _letterKeys[selected]?.currentContext;
    if (keyContext != null) {
      await Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
  }

  void _beginFolderMode() {
    setState(() {
      _folderMode = true;
      _folderSelection.clear();
      _query = '';
      _searchController.clear();
      _folderNameController.clear();
    });
  }

  void _cancelFolderMode() {
    setState(() {
      _folderMode = false;
      _folderSelection.clear();
    });
  }

  void _toggleFolderSelection(HomeGridItem item) {
    setState(() {
      if (!_folderSelection.add(item.id)) {
        _folderSelection.remove(item.id);
      }
    });
  }

  void _createFolder() {
    if (_folderSelection.length < 2) {
      return;
    }
    widget.onCreateFolder(
      _folderNameController.text.trim().isEmpty
          ? context.l10n.tabletFolder
          : _folderNameController.text,
      widget.items.where((item) => _folderSelection.contains(item.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _folderMode ? '' : _query.trim().toLowerCase();
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
    final groupedItems = <String, List<HomeGridItem>>{};
    for (final item in items) {
      groupedItems
          .putIfAbsent(_letterFor(context, item), () => <HomeGridItem>[])
          .add(item);
    }
    final availableLetters = groupedItems.keys.toSet();
    for (final letter in availableLetters) {
      _letterKeys.putIfAbsent(letter, GlobalKey.new);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: _folderMode
          ? null
          : (details) {
              if ((details.primaryVelocity ?? 0) > 720) {
                widget.onClose();
              }
            },
      onVerticalDragEnd: _folderMode
          ? null
          : (details) {
              if ((details.primaryVelocity ?? 0) > 760) {
                widget.onClose();
              }
            },
      child: _MetroSlideIn(
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
                    label: _folderMode
                        ? context.l10n.actionCancel
                        : context.l10n.tabletStartTitle,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _folderMode ? _cancelFolderMode : widget.onClose,
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
                  Text(
                    _folderMode
                        ? context.l10n.tabletNewFolder
                        : context.l10n.tabletAllApps,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  if (_folderMode) ...[
                    SizedBox(
                      width: 220,
                      height: 42,
                      child: TextField(
                        controller: _folderNameController,
                        maxLength: 40,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        cursorColor: Colors.white,
                        decoration: _metroTextFieldDecoration(
                          context.l10n.tabletFolderName,
                          Icons.folder_outlined,
                        ).copyWith(counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      context.l10n.tabletSelectedCount(_folderSelection.length),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _MetroHeaderAction(
                      icon: Icons.check_rounded,
                      label: context.l10n.tabletCreate,
                      onTap: _folderSelection.length >= 2
                          ? _createFolder
                          : () {},
                    ),
                  ] else ...[
                    _MetroHeaderAction(
                      icon: Icons.sort_by_alpha_rounded,
                      label: 'A–Z',
                      onTap: () => _showAlphabetJump(
                        context,
                        availableLetters,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MetroHeaderAction(
                      icon: Icons.create_new_folder_outlined,
                      label: context.l10n.tabletFolder,
                      onTap: _beginFolderMode,
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 300,
                      height: 42,
                      child: TextField(
                        controller: _searchController,
                        autofocus: widget.focusSearch,
                        onChanged: (value) => setState(() => _query = value),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        cursorColor: Colors.white,
                        decoration: _metroTextFieldDecoration(
                          context.l10n.desktopSearchApplications,
                          Icons.search_rounded,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              if (!_folderMode &&
                  normalized.isEmpty &&
                  widget.systemItems.isNotEmpty) ...[
                Text(
                  context.l10n.tabletSystemTiles,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 116,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.systemItems.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final item = widget.systemItems[index];
                      return SizedBox.square(
                        dimension: 108,
                        child: _MetroDrawerTile(
                          item: item,
                          pinned: widget.pinnedIds.contains(item.id),
                          onTogglePin: () => widget.onTogglePin(item),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          normalized.isEmpty
                              ? context.l10n.tabletNoApplications
                              : context.l10n.tabletNoMatchingApplications,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 16,
                          ),
                        ),
                      )
                    : _MetroAlphabeticalApps(
                        controller: _appListController,
                        groups: groupedItems,
                        letterKeys: _letterKeys,
                        titleFor: (item) => _titleFor(context, item),
                        pinnedIds: widget.pinnedIds,
                        selectionMode: _folderMode,
                        selectedIds: _folderSelection,
                        onSelect: _toggleFolderSelection,
                        onTogglePin: widget.onTogglePin,
                        onLaunch: _folderMode ? null : widget.onLaunch,
                      ),
              ),
              Center(
                child: Text(
                  _folderMode
                      ? context.l10n.tabletCreateFolderHint
                      : context.l10n.tabletDrawerHint,
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
      ),
    );
  }
}

InputDecoration _metroTextFieldDecoration(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0x80FFFFFF)),
    prefixIcon: Icon(icon, color: const Color(0xB3FFFFFF), size: 20),
    filled: true,
    fillColor: const Color(0x17FFFFFF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(3),
      borderSide: const BorderSide(color: Color(0x26FFFFFF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(3),
      borderSide: const BorderSide(color: Colors.white, width: 1.3),
    ),
  );
}

class _MetroDrawerTile extends StatelessWidget {
  const _MetroDrawerTile({
    required this.item,
    required this.pinned,
    required this.onTogglePin,
    this.onLaunch,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
  });

  final HomeGridItem item;
  final bool pinned;
  final VoidCallback onTogglePin;
  final ValueChanged<Rect>? onLaunch;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selectionMode ? selected : null,
      label: selectionMode
          ? (selected ? 'Selected for folder' : 'Not selected for folder')
          : (pinned ? 'Pinned to Start' : 'Not pinned to Start'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selectionMode ? onSelect : null,
        onLongPress: selectionMode ? onSelect : onTogglePin,
        child: Stack(
          fit: StackFit.expand,
          children: [
            HomeGridItemCard(
              item: item,
              launchEnabled: !selectionMode && onLaunch != null,
              onLaunch: (_, sourceRect) => onLaunch?.call(sourceRect),
            ),
            Positioned(
              top: 5,
              right: 5,
              child: Semantics(
                button: true,
                label: selectionMode
                    ? (selected ? 'Remove from folder' : 'Add to folder')
                    : (pinned ? 'Unpin from Start' : 'Pin to Start'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: selectionMode ? onSelect : onTogglePin,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xCC101419),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Icon(
                        selectionMode
                            ? (selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined)
                            : (pinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined),
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetroFolderOverlay extends StatefulWidget {
  const _MetroFolderOverlay({
    required this.folder,
    required this.onClose,
    required this.onLaunch,
    required this.onRename,
  });

  final HomeGridItem folder;
  final VoidCallback onClose;
  final void Function(HomeGridItem item, Rect sourceRect) onLaunch;
  final ValueChanged<String> onRename;

  @override
  State<_MetroFolderOverlay> createState() => _MetroFolderOverlayState();
}

class _MetroFolderOverlayState extends State<_MetroFolderOverlay> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.folder.folderName ?? 'Folder',
  );

  @override
  void didUpdateWidget(covariant _MetroFolderOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.folderName != widget.folder.folderName &&
        _nameController.text != widget.folder.folderName) {
      _nameController.text = widget.folder.folderName ?? 'Folder';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _commitName() {
    final value = _nameController.text.trim();
    if (value.isNotEmpty && value != widget.folder.folderName) {
      widget.onRename(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: const ColoredBox(color: Color(0xB8000000)),
        ),
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 650,
                maxHeight: 590,
                minWidth: 360,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xF21A2028),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Semantics(
                            button: true,
                            label: 'Close folder',
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
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              maxLength: 40,
                              onSubmitted: (_) => _commitName(),
                              onEditingComplete: _commitName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w400,
                              ),
                              cursorColor: Colors.white,
                              decoration: const InputDecoration(
                                counterText: '',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          Text(
                            context.l10n.tabletFolderAppCount(
                              widget.folder.folderItems.length,
                            ),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 142,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1,
                              ),
                          itemCount: widget.folder.folderItems.length,
                          itemBuilder: (context, index) {
                            final item = widget.folder.folderItems[index];
                            return HomeGridItemCard(
                              item: item,
                              onLaunch: (_, sourceRect) =>
                                  widget.onLaunch(item, sourceRect),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


class _MetroSemanticZoomOverlay extends StatelessWidget {
  const _MetroSemanticZoomOverlay({
    required this.slots,
    required this.pageSize,
    required this.pageCount,
    required this.activePage,
    required this.groupNames,
    required this.onClose,
    required this.onSelectPage,
    required this.onRenamePage,
  });

  final List<HomeGridItem?> slots;
  final int pageSize;
  final int pageCount;
  final int activePage;
  final Map<int, String> groupNames;
  final VoidCallback onClose;
  final ValueChanged<int> onSelectPage;
  final void Function(int page, String name) onRenamePage;

  String _groupLabel(BuildContext context, int page) {
    final saved = groupNames[page];
    if (saved != null && saved.trim().isNotEmpty) {
      return saved;
    }
    if (page == 0) {
      return context.l10n.tabletStartTitle;
    }
    final start = page * pageSize;
    final end = math.min(start + pageSize, slots.length);
    for (var index = start; index < end; index += 1) {
      final item = slots[index];
      if (item == null) continue;
      if (item.isFolder) return item.folderName ?? 'Group ${page + 1}';
      final title = item.localApp?.titleFor(context) ?? item.app?.name;
      if (title != null && title.trim().isNotEmpty) return title;
    }
    return 'Group ${page + 1}';
  }

  Future<void> _renameGroup(BuildContext context, int page) async {
    final controller = TextEditingController(text: _groupLabel(context, page));
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this Start group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'Group name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      onRenamePage(page, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = math.max(1, pageCount);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: _MetroZoomIn(
        child: ColoredBox(
          color: const Color(0xF20B0F14),
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(34, 28, 34, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Start groups',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const Spacer(),
                  _MetroHeaderAction(
                    icon: Icons.close_rounded,
                    label: 'Close',
                    onTap: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 270,
                        mainAxisSpacing: 22,
                        crossAxisSpacing: 22,
                        childAspectRatio: 1.46,
                      ),
                      itemCount: groups,
                      itemBuilder: (context, page) {
                        final safePageSize = math.max(1, pageSize);
                        final start = page * safePageSize;
                        final end = math.min(start + safePageSize, slots.length);
                        final items = <HomeGridItem>[
                          for (var i = start; i < end; i += 1)
                            if (slots[i] case final item?) item,
                        ];
                        final active = page == activePage;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelectPage(page),
                          onLongPress: () => _renameGroup(context, page),
                          child: AnimatedScale(
                            scale: active ? 1.0 : 0.96,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFF151B22),
                                border: Border.all(
                                  color: active
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.12),
                                  width: active ? 2 : 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: GridView.count(
                                        physics: const NeverScrollableScrollPhysics(),
                                        crossAxisCount: 4,
                                        mainAxisSpacing: 5,
                                        crossAxisSpacing: 5,
                                        padding: EdgeInsets.zero,
                                        children: [
                                          for (final item in items.take(12))
                                            DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: metroTileColor(
                                                  item.id,
                                                  item.tileColorValue,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _groupLabel(context, page),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: active ? 1 : 0.86,
                                              ),
                                              fontSize: 16,
                                              fontWeight: active
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _renameGroup(context, page),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.edit_rounded,
                                              size: 16,
                                              color: Colors.white.withValues(
                                                alpha: 0.66,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
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

class _MetroCharmsRail extends StatelessWidget {
  const _MetroCharmsRail({
    required this.onClose,
    required this.onSearch,
    required this.onStart,
    required this.onDevices,
    required this.onSettings,
  });

  final VoidCallback onClose;
  final VoidCallback onSearch;
  final VoidCallback onStart;
  final VoidCallback onDevices;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: const ColoredBox(color: Color(0x52000000)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 1, end: 0),
            builder: (context, value, child) => Transform.translate(
              offset: Offset(170 * value, 0),
              child: child,
            ),
            child: SizedBox(
              width: 150,
              height: double.infinity,
              child: ColoredBox(
                color: const Color(0xF40B0D10),
                child: SafeArea(
                  minimum: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _MetroCharmButton(
                        icon: Icons.search_rounded,
                        label: 'Search',
                        onTap: onSearch,
                      ),
                      _MetroCharmButton(
                        icon: Icons.window_rounded,
                        label: 'Start',
                        onTap: onStart,
                      ),
                      _MetroCharmButton(
                        icon: Icons.devices_other_rounded,
                        label: 'Devices',
                        onTap: onDevices,
                      ),
                      _MetroCharmButton(
                        icon: Icons.settings_rounded,
                        label: 'Settings',
                        onTap: onSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetroCharmButton extends StatefulWidget {
  const _MetroCharmButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MetroCharmButton> createState() => _MetroCharmButtonState();
}

class _MetroCharmButtonState extends State<_MetroCharmButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: const EdgeInsets.symmetric(vertical: 10),
        width: 112,
        padding: const EdgeInsets.symmetric(vertical: 12),
        color: _pressed ? const Color(0xFF0078D7) : Colors.transparent,
        child: Column(
          children: [
            Icon(widget.icon, color: Colors.white, size: 34),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _MetroAlphabeticalApps extends StatelessWidget {
  const _MetroAlphabeticalApps({
    required this.controller,
    required this.groups,
    required this.letterKeys,
    required this.titleFor,
    required this.pinnedIds,
    required this.selectionMode,
    required this.selectedIds,
    required this.onSelect,
    required this.onTogglePin,
    required this.onLaunch,
  });

  final ScrollController controller;
  final Map<String, List<HomeGridItem>> groups;
  final Map<String, GlobalKey> letterKeys;
  final String Function(HomeGridItem item) titleFor;
  final Set<String> pinnedIds;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<HomeGridItem> onSelect;
  final ValueChanged<HomeGridItem> onTogglePin;
  final void Function(HomeGridItem item, Rect sourceRect)? onLaunch;

  List<String> get _letters {
    final result = groups.keys.toList(growable: false)
      ..sort((a, b) {
        if (a == '#') return -1;
        if (b == '#') return 1;
        return a.compareTo(b);
      });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.sizeOf(context).height >
        MediaQuery.sizeOf(context).width;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        for (final letter in _letters) ...[
          Padding(
            key: letterKeys[letter],
            padding: EdgeInsets.fromLTRB(
              portrait ? 4 : 2,
              10,
              0,
              portrait ? 6 : 10,
            ),
            child: Row(
              children: [
                Container(
                  width: portrait ? 42 : 50,
                  height: portrait ? 42 : 50,
                  alignment: Alignment.center,
                  color: const Color(0xFF0078D7),
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: portrait ? 20 : 23,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (!portrait) ...[
                  const SizedBox(width: 12),
                  Text(
                    letter == '#' ? 'Other' : letter,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (portrait)
            for (final item in groups[letter]!)
              _MetroPhoneAppRow(
                item: item,
                title: titleFor(item),
                pinned: pinnedIds.contains(item.id),
                selectionMode: selectionMode,
                selected: selectedIds.contains(item.id),
                onSelect: () => onSelect(item),
                onTogglePin: () => onTogglePin(item),
                onLaunch: onLaunch == null
                    ? null
                    : (sourceRect) => onLaunch!(item, sourceRect),
              )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in groups[letter]!)
                    SizedBox.square(
                      dimension: 126,
                      child: _MetroDrawerTile(
                        item: item,
                        pinned: pinnedIds.contains(item.id),
                        selectionMode: selectionMode,
                        selected: selectedIds.contains(item.id),
                        onSelect: () => onSelect(item),
                        onTogglePin: () => onTogglePin(item),
                        onLaunch: onLaunch == null
                            ? null
                            : (sourceRect) => onLaunch!(item, sourceRect),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _MetroPhoneAppRow extends StatelessWidget {
  _MetroPhoneAppRow({
    required this.item,
    required this.title,
    required this.pinned,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onTogglePin,
    required this.onLaunch,
  });

  final GlobalKey _rowKey = GlobalKey();
  final HomeGridItem item;
  final String title;
  final bool pinned;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onTogglePin;
  final ValueChanged<Rect>? onLaunch;

  void _launch() {
    final render = _rowKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) {
      return;
    }
    onLaunch?.call(
      MatrixUtils.transformRect(
        render.getTransformTo(null),
        Offset.zero & render.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localIcon = item.localApp?.icon;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selectionMode ? onSelect : (onLaunch == null ? null : _launch),
      onLongPress: selectionMode ? onSelect : onTogglePin,
      child: Container(
        key: _rowKey,
        height: 64,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        color: selected
            ? const Color(0x330078D7)
            : Colors.transparent,
        child: Row(
          children: [
            SizedBox.square(
              dimension: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: metroTileColor(item.id, item.tileColorValue),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: localIcon != null
                      ? Icon(localIcon, color: Colors.white, size: 30)
                      : AppIconImage(iconPath: item.app?.iconPath),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (selectionMode)
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: Colors.white,
                size: 24,
              )
            else
              IconButton(
                tooltip: pinned ? 'Unpin from Start' : 'Pin to Start',
                onPressed: onTogglePin,
                icon: Icon(
                  pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: Colors.white.withValues(alpha: 0.78),
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetroAlphabetJumpDialog extends StatelessWidget {
  const _MetroAlphabetJumpDialog({required this.availableLetters});

  final Set<String> availableLetters;

  @override
  Widget build(BuildContext context) {
    const letters = <String>[
      '#',
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z',
    ];
    return Dialog(
      backgroundColor: const Color(0xFF10151B),
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 6,
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
            children: [
              for (final letter in letters)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: availableLetters.contains(letter)
                      ? () => Navigator.of(context).pop(letter)
                      : null,
                  child: ColoredBox(
                    color: availableLetters.contains(letter)
                        ? const Color(0xFF0078D7)
                        : const Color(0xFF20262D),
                    child: Center(
                      child: Text(
                        letter,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: availableLetters.contains(letter)
                                ? 1
                                : 0.24,
                          ),
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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


class _MetroSlideIn extends StatelessWidget {
  const _MetroSlideIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: 1 - value * 0.45,
        child: Transform.translate(
          offset: Offset(52 * value, 0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _MetroZoomIn extends StatelessWidget {
  const _MetroZoomIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(
          scale: 0.90 + 0.10 * value,
          child: child,
        ),
      ),
      child: child,
    );
  }
}
