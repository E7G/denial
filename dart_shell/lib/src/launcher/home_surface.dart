import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/input_layout.dart';
import '../local_apps/local_flutter_application.dart';
import '../localization/denial_localizations.dart';
import '../state/display_layout.dart';
import '../state/output_configuration.dart';
import '../state/shell_controller.dart';
import '../settings/settings_controller.dart';
import '../settings/embedded_settings_surface.dart';
import '../settings/shell_settings.dart';
import '../widgets/retained_translation.dart';
import '../widgets/app_icon.dart';
import '../widgets/connectivity/bluetooth_detail_surface.dart';
import '../widgets/shell_surface_host.dart';
import 'controllers/application_recents_controller.dart';
import 'controllers/home_grid_controller.dart';
import 'controllers/home_grid_layout.dart';
import 'controllers/home_overlay_navigation.dart';
import 'models/home_drag_session.dart';
import 'models/home_grid_item.dart';
import 'widgets/home_app_page.dart';
import 'widgets/home_backdrop.dart';
import 'widgets/home_empty_state.dart';
import 'widgets/home_tiles.dart';
import 'widgets/page_dots.dart';

part 'home_surface_view.dart';
part 'home_pager.dart';
part 'home_drag_overlay.dart';
part 'home_surface_models.dart';

class HomeSurface extends ConsumerStatefulWidget {
  const HomeSurface({
    super.key,
    this.active = true,
    this.interactive = true,
    this.contentOpacity,
    this.useShellLaunchTransition = false,
  });

  /// Whether the built-in launcher is currently part of the visible shell
  /// scene. Its laid-out subtree is retained offstage while inactive, avoiding
  /// a cold grid/icon rebuild on the first frame of a swipe back to home.
  final bool active;

  /// Whether pointer events may reach launcher content. The launcher can stay
  /// visible behind shell-owned transitions without accepting accidental taps.
  final bool interactive;

  /// Fades icons, widgets and page indicators independently of the backdrop.
  /// The animation updates composited opacity without rebuilding the grid.
  final Animation<double>? contentOpacity;

  /// Coordinates launches with the integrated shell's placeholder and window
  /// matching. The standalone launcher leaves this off and starts apps
  /// directly because it does not render the shell transition layer.
  final bool useShellLaunchTransition;

  @override
  ConsumerState<HomeSurface> createState() => _HomeSurfaceState();
}

class _HomeSurfaceState extends ConsumerState<HomeSurface> {
  static const double _pageHorizontalPadding = 28;
  static const double _appRowVisualHeight = 184;
  static const double _pageDotsReservedHeight = 12;
  static const EdgeInsets _contentPadding = EdgeInsets.fromLTRB(0, 66, 0, 8);
  static const Duration _backgroundTapMaxDuration = Duration(milliseconds: 260);
  static const Duration _doubleTapMaxInterval = Duration(milliseconds: 360);
  static const double _tapMoveTolerance = 18;
  static const double _doubleTapDistanceTolerance = 72;

  late final PageController _pageController;
  final GlobalKey _homeStackKey = GlobalKey();
  final GlobalKey _gridViewportKey = GlobalKey();
  _HomeResizeSession? _resizeSession;
  int? _resizeModeIndex;
  bool _appDrawerOpen = false;
  bool _appDrawerFocusSearch = false;
  bool _appDrawerPrepared = false;
  List<HomeGridItem>? _drawerCatalogSource;
  bool? _drawerCatalogShowSystemTiles;
  Locale? _drawerCatalogLocale;
  List<HomeGridItem> _drawerApplicationItems = const <HomeGridItem>[];
  List<HomeGridItem> _drawerSystemItems = const <HomeGridItem>[];
  List<HomeGridItem?>? _drawerPinnedSource;
  Set<String> _drawerPinnedIds = const <String>{};
  bool _semanticZoomOpen = false;
  bool _charmsOpen = false;
  bool _tabletOutputScaleBootstrapRunning = false;
  bool _tabletOutputScaleBootstrapComplete = false;
  int _tabletOutputScaleBootstrapAttempts = 0;
  HomeGridItem? _openFolder;
  double _currentTileWidth = 0;
  double _currentTileHeight = 0;
  int _currentRows = 0;
  int _currentPageCount = 0;
  int _currentPageSize = 0;
  Timer? _dragEndTimer;
  Timer? _tabletOutputScaleRetryTimer;
  bool _interactionResetScheduled = false;
  DateTime _lastAutoPageTurn = DateTime.fromMillisecondsSinceEpoch(0);
  int? _activePointer;
  final Map<int, Offset> _pointerPositions = <int, Offset>{};
  double? _pinchStartDistance;
  bool _pinchConsumed = false;
  Offset? _tapStartGlobalPosition;
  Duration? _tapStartTime;
  bool _tapMoved = false;
  bool _tapStartedOnInteractiveItem = false;
  Duration? _lastBackgroundTapTime;
  Offset? _lastBackgroundTapPosition;
  DateTime _lastScreenOffRequest = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(homeGridControllerProvider.notifier)
          .setLauncherActive(widget.active && widget.interactive);
      unawaited(_bootstrapTabletOutputScale());
    });
  }

  ({List<HomeGridItem> applications, List<HomeGridItem> systemItems})
  _drawerCatalog(List<HomeGridItem> allItems, {required bool showSystemTiles}) {
    final locale = Localizations.maybeLocaleOf(context);
    if (!identical(_drawerCatalogSource, allItems) ||
        _drawerCatalogShowSystemTiles != showSystemTiles ||
        _drawerCatalogLocale != locale) {
      _drawerCatalogSource = allItems;
      _drawerCatalogShowSystemTiles = showSystemTiles;
      _drawerCatalogLocale = locale;
      _drawerApplicationItems =
          allItems.where((item) => item.isApplication).toList(growable: false)
            ..sort((a, b) {
              final aTitle =
                  (a.localApp?.titleFor(context) ?? a.app?.name ?? a.id)
                      .toLowerCase();
              final bTitle =
                  (b.localApp?.titleFor(context) ?? b.app?.name ?? b.id)
                      .toLowerCase();
              return aTitle.compareTo(bTitle);
            });
      _drawerSystemItems = showSystemTiles
          ? allItems.where((item) => item.isSystemTile).toList(growable: false)
          : const <HomeGridItem>[];
    }
    return (
      applications: _drawerApplicationItems,
      systemItems: _drawerSystemItems,
    );
  }

  Set<String> _drawerPinnedItems(List<HomeGridItem?> slots) {
    if (!identical(_drawerPinnedSource, slots)) {
      _drawerPinnedSource = slots;
      _drawerPinnedIds = <String>{
        for (final item in slots)
          if (item != null) item.id,
      };
    }
    return _drawerPinnedIds;
  }

  Future<void> _bootstrapTabletOutputScale() async {
    if (_tabletOutputScaleBootstrapRunning ||
        _tabletOutputScaleBootstrapComplete) {
      return;
    }
    _tabletOutputScaleBootstrapRunning = true;
    _tabletOutputScaleBootstrapAttempts += 1;

    final tabletSettings = ref.read(shellSettingsProvider).tablet;
    if (!tabletSettings.enabled) {
      _tabletOutputScaleBootstrapComplete = true;
      _tabletOutputScaleBootstrapRunning = false;
      return;
    }

    try {
      final controller = ref.read(outputConfigurationProvider.notifier);
      await controller.refresh();
      if (!mounted) {
        return;
      }

      final outputState = ref.read(outputConfigurationProvider);
      final configuration = outputState.configuration;
      if (configuration == null || outputState.applying) {
        return;
      }
      if (configuration.outputs.length != 1 ||
          !configuration.capabilities.apply ||
          !configuration.capabilities.scale ||
          !configuration.capabilities.persistent) {
        _tabletOutputScaleBootstrapComplete = true;
        return;
      }

      final output = configuration.outputs.single;
      final mode = output.currentMode;
      final isMiPad2Panel =
          output.name == 'DSI-1' && mode?.width == 1536 && mode?.height == 2048;
      if (!isMiPad2Panel) {
        _tabletOutputScaleBootstrapComplete = true;
        return;
      }
      if (output.scale >= 1.75) {
        _tabletOutputScaleBootstrapComplete = true;
        return;
      }

      controller.setScale(output.name, 2.0);
      final applied = await controller.apply();
      if (!applied || !mounted) {
        return;
      }

      final confirmation = ref
          .read(outputConfigurationProvider)
          .configuration
          ?.pendingConfirmation;
      if (confirmation != null) {
        await controller.keepChanges();
      }
      _tabletOutputScaleBootstrapComplete = true;
    } finally {
      _tabletOutputScaleBootstrapRunning = false;
      if (mounted &&
          !_tabletOutputScaleBootstrapComplete &&
          _tabletOutputScaleBootstrapAttempts < 12) {
        _tabletOutputScaleRetryTimer?.cancel();
        _tabletOutputScaleRetryTimer = Timer(
          const Duration(milliseconds: 750),
          () {
            if (mounted) {
              unawaited(_bootstrapTabletOutputScale());
            }
          },
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant HomeSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasRefreshActive = oldWidget.active && oldWidget.interactive;
    final isRefreshActive = widget.active && widget.interactive;
    if (wasRefreshActive != isRefreshActive) {
      ref
          .read(homeGridControllerProvider.notifier)
          .setLauncherActive(isRefreshActive);
    }
    if ((oldWidget.active && !widget.active) ||
        (oldWidget.interactive && !widget.interactive)) {
      _cancelInteraction();
    }
  }

  @override
  void dispose() {
    _dragEndTimer?.cancel();
    _tabletOutputScaleRetryTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _cancelInteraction() {
    _dragEndTimer?.cancel();
    _appDrawerOpen = false;
    _appDrawerFocusSearch = false;
    _semanticZoomOpen = false;
    _charmsOpen = false;
    _openFolder = null;
    ref.read(homeOverlayNavigationProvider.notifier).setModalOpen(false);
    _dragEndTimer = null;
    _activePointer = null;
    _pointerPositions.clear();
    _pinchStartDistance = null;
    _pinchConsumed = false;
    _resetTapTracking();
    _resizeSession = null;
    _resizeModeIndex = null;
    if (_interactionResetScheduled) {
      return;
    }
    _interactionResetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _interactionResetScheduled = false;
      if (!mounted) {
        return;
      }
      ref.read(homeDragSessionProvider.notifier).clear();
      ref
          .read(homeGridControllerProvider.notifier)
          .setDraggingSourceIndex(null);
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerPositions[event.pointer] = event.position;
    if (_pointerPositions.length == 2) {
      final points = _pointerPositions.values.toList(growable: false);
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchConsumed = false;
    }

    final resizeModeWasActive = _resizeModeIndex != null;
    _dismissResizeModeIfPointerOutside(event.position);
    if (_activePointer != null) {
      return;
    }

    _activePointer = event.pointer;
    _tapStartGlobalPosition = event.position;
    _tapStartTime = event.timeStamp;
    _tapMoved = false;
    _tapStartedOnInteractiveItem =
        _appDrawerOpen ||
        _openFolder != null ||
        resizeModeWasActive ||
        _pointerInsideHomeItem(event.position);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _pointerPositions[event.pointer] = event.position;
    if (_handleSemanticPinch()) {
      return;
    }
    if (event.pointer != _activePointer) {
      return;
    }
    final tapStart = _tapStartGlobalPosition;
    if (tapStart != null &&
        (event.position - tapStart).distance > _tapMoveTolerance) {
      _tapMoved = true;
    }
    if (_maybeOpenAppDrawerDuringSwipe(event)) {
      return;
    }
    _syncDragSessionToPointer(
      event.position,
      pageCount: _currentPageCount,
      autoPage: true,
    );
  }

  void _handlePointerUp(PointerEvent event) {
    _pointerPositions.remove(event.pointer);
    if (_pointerPositions.length < 2) {
      _pinchStartDistance = null;
    }
    if (_pinchConsumed) {
      if (event.pointer == _activePointer) {
        _activePointer = null;
        _resetTapTracking();
      }
      if (_pointerPositions.isEmpty) {
        _pinchConsumed = false;
      }
      return;
    }
    if (event.pointer != _activePointer) {
      return;
    }
    _activePointer = null;
    if (event is PointerUpEvent) {
      if (ref.read(homeDragSessionProvider) != null) {
        _handleItemDragEnd(event.position);
      }
      if (!_handleMetroSwipe(event)) {
        _handlePotentialBackgroundTap(event);
      }
    } else {
      if (ref.read(homeDragSessionProvider) != null) {
        _handleItemDragEnd();
      }
      _resetTapTracking();
    }
  }

  bool _maybeOpenAppDrawerDuringSwipe(PointerMoveEvent event) {
    if (_appDrawerOpen ||
        _semanticZoomOpen ||
        _charmsOpen ||
        _openFolder != null ||
        _tapStartedOnInteractiveItem ||
        ref.read(homeDragSessionProvider) != null) {
      return false;
    }
    final start = _tapStartGlobalPosition;
    if (start == null) {
      return false;
    }
    final size = MediaQuery.sizeOf(context);
    if (size.height <= size.width) {
      return false;
    }
    final delta = event.position - start;
    if (delta.dx > -48 || delta.dx.abs() < delta.dy.abs() * 1.35) {
      return false;
    }

    // Start the reveal while the finger is still moving. Previously the
    // drawer was first constructed after pointer-up, which made a normal
    // swipe feel like it stalled before responding.
    _tapMoved = true;
    _resetTapTracking();
    _openAppDrawer();
    return true;
  }

  bool _handleSemanticPinch() {
    if (_pinchConsumed ||
        _pointerPositions.length != 2 ||
        _appDrawerOpen ||
        _openFolder != null ||
        _semanticZoomOpen ||
        _charmsOpen) {
      return false;
    }
    final size = MediaQuery.sizeOf(context);
    if (size.height > size.width || _currentPageCount <= 1) {
      return false;
    }
    final startDistance = _pinchStartDistance;
    if (startDistance == null || startDistance < 32) {
      return false;
    }
    final points = _pointerPositions.values.toList(growable: false);
    final currentDistance = (points[0] - points[1]).distance;
    if (currentDistance / startDistance > 0.68) {
      return false;
    }
    _pinchConsumed = true;
    _activePointer = null;
    _resetTapTracking();
    _openSemanticZoom();
    return true;
  }

  void _openAppDrawer({bool focusSearch = false}) {
    _clearResizeMode();
    _lastBackgroundTapTime = null;
    _lastBackgroundTapPosition = null;
    ref.read(homeOverlayNavigationProvider.notifier).setModalOpen(true);
    setState(() {
      _appDrawerPrepared = true;
      _charmsOpen = false;
      _semanticZoomOpen = false;
      _appDrawerOpen = true;
      _appDrawerFocusSearch = focusSearch;
    });
  }

  void _openQuickSettingsFromStart() {
    _clearResizeMode();
    _lastBackgroundTapTime = null;
    _lastBackgroundTapPosition = null;
    ref.read(shellControllerProvider.notifier).openQuickSettings();
  }

  void _closeAppDrawer() {
    if (!_appDrawerOpen) {
      return;
    }
    ref.read(homeOverlayNavigationProvider.notifier).setModalOpen(false);
    setState(() {
      _appDrawerOpen = false;
      _appDrawerFocusSearch = false;
    });
  }

  void _openSemanticZoom() {
    if (_currentPageCount <= 1) {
      return;
    }
    _clearResizeMode();
    ref.read(homeOverlayNavigationProvider.notifier).setModalOpen(true);
    setState(() {
      _appDrawerOpen = false;
      _charmsOpen = false;
      _semanticZoomOpen = true;
    });
  }

  void _closeSemanticZoom() {
    if (!_semanticZoomOpen) {
      return;
    }
    ref.read(homeOverlayNavigationProvider.notifier).setModalOpen(false);
    setState(() => _semanticZoomOpen = false);
  }

  void _renameStartGroup(int page, String name) {
    ref.read(homeGridControllerProvider.notifier).renameGroup(page, name);
  }

  void _jumpToStartGroup(int page) {
    final safePage = page.clamp(0, math.max(0, _currentPageCount - 1)).toInt();
    ref.read(homeGridControllerProvider.notifier).setPage(safePage);
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          safePage,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    _closeSemanticZoom();
  }

  void _openCharms() {
    _clearResizeMode();
    ref.read(homeOverlayNavigationProvider.notifier).setModalOpen(true);
    setState(() {
      _appDrawerOpen = false;
      _semanticZoomOpen = false;
      _charmsOpen = true;
    });
  }

  void _closeCharms() {
    if (!_charmsOpen) {
      return;
    }
    ref.read(homeOverlayNavigationProvider.notifier).setModalOpen(false);
    setState(() => _charmsOpen = false);
  }

  void _openBluetoothFromCharms() {
    _closeCharms();
    ref
        .read(shellSurfaceControllerProvider.notifier)
        .show(
          keyName: 'bluetooth-details',
          debugLabel: 'Bluetooth details',
          presentation: ShellSurfacePresentation.fullscreen,
          builder: (_, handle) => BluetoothDetailSurface(onClose: handle.close),
        );
  }

  void _openSettingsFromCharms() {
    _closeCharms();
    showEmbeddedSettingsSurface(ref);
  }

  bool _handleMetroSwipe(PointerUpEvent event) {
    final start = _tapStartGlobalPosition;
    final startTime = _tapStartTime;
    if (start == null || startTime == null) {
      return false;
    }
    final delta = event.position - start;
    final elapsed = event.timeStamp - startTime;
    if (elapsed > const Duration(milliseconds: 850) ||
        delta.distance < 70 ||
        delta.dx.abs() < delta.dy.abs() * 1.25) {
      return false;
    }

    final size = MediaQuery.sizeOf(context);
    final portrait = size.height > size.width;

    if (!_appDrawerOpen &&
        !_semanticZoomOpen &&
        !_charmsOpen &&
        start.dx >= size.width - 42 &&
        delta.dx < -72) {
      _resetTapTracking();
      _openCharms();
      return true;
    }

    if (portrait &&
        !_appDrawerOpen &&
        !_semanticZoomOpen &&
        !_charmsOpen &&
        delta.dx < -110) {
      _resetTapTracking();
      _openAppDrawer();
      return true;
    }

    return false;
  }

  void _launchFromAppDrawer(HomeGridItem item, Rect sourceRect) {
    _closeAppDrawer();
    unawaited(_launchApp(item, sourceRect));
  }

  void _createFolderFromDrawer(String name, Iterable<HomeGridItem> items) {
    final created = ref
        .read(homeGridControllerProvider.notifier)
        .createFolder(name, items.map((item) => item.id));
    if (!created) {
      return;
    }
    _closeAppDrawer();
  }

  void _openFolderItem(HomeGridItem folder) {
    if (!folder.isFolder || folder.folderItems.isEmpty) {
      return;
    }
    _clearResizeMode();
    ref.read(homeOverlayNavigationProvider.notifier).setModalOpen(true);
    setState(() => _openFolder = folder);
  }

  void _closeFolder() {
    if (_openFolder == null) {
      return;
    }
    ref.read(homeOverlayNavigationProvider.notifier).setModalOpen(false);
    setState(() => _openFolder = null);
  }

  void _launchFromFolder(HomeGridItem item, Rect sourceRect) {
    _closeFolder();
    unawaited(_launchApp(item, sourceRect));
  }

  void _renameOpenFolder(String name) {
    final folder = _openFolder;
    if (folder == null || !folder.isFolder) {
      return;
    }
    ref.read(homeGridControllerProvider.notifier).renameFolder(folder.id, name);
    setState(() => _openFolder = folder.withFolderName(name));
  }

  void _togglePinFromAppDrawer(HomeGridItem item) {
    final controller = ref.read(homeGridControllerProvider.notifier);
    final state = ref.read(homeGridControllerProvider).asData?.value;
    if (state == null) {
      return;
    }
    if (state.isPinned(item.id)) {
      controller.unpinItem(item.id);
    } else {
      controller.pinItem(item);
    }
  }

  void _removeFromStart(HomeGridItem item) {
    _clearResizeMode();
    ref.read(homeGridControllerProvider.notifier).unpinItem(item.id);
  }

  void _cycleTileSize(HomeGridItem item, int index, int pageSize) {
    if (!item.resizable || pageSize <= 0) {
      return;
    }
    final controller = ref.read(homeGridControllerProvider.notifier);
    final candidates = <({int colSpan, int rowSpan})>[
      (colSpan: 1, rowSpan: 1),
      (colSpan: 2, rowSpan: 1),
      (colSpan: 2, rowSpan: 2),
      (colSpan: 1, rowSpan: 2),
    ];
    final currentIndex = candidates.indexWhere(
      (candidate) =>
          candidate.colSpan == item.colSpan &&
          candidate.rowSpan == item.rowSpan,
    );
    for (var offset = 1; offset <= candidates.length; offset += 1) {
      final candidate =
          candidates[(math.max(0, currentIndex) + offset) % candidates.length];
      if (candidate.colSpan < item.minColSpan ||
          candidate.colSpan > item.maxColSpan ||
          candidate.rowSpan < item.minRowSpan ||
          candidate.rowSpan > item.maxRowSpan) {
        continue;
      }
      if (controller.canResizeSlot(
        index,
        candidate.colSpan,
        candidate.rowSpan,
        pageSize,
      )) {
        controller.resizeSlot(
          index,
          candidate.colSpan,
          candidate.rowSpan,
          pageSize,
        );
        return;
      }
    }
  }

  void _cycleTileColor(HomeGridItem item) {
    final current = item.tileColorValue;
    int? next;
    if (current == null) {
      next = metroTilePalette.first.toARGB32();
    } else {
      final index = metroTilePalette.indexWhere(
        (color) => color.toARGB32() == current,
      );
      next = index < 0 || index == metroTilePalette.length - 1
          ? null
          : metroTilePalette[index + 1].toARGB32();
    }
    ref.read(homeGridControllerProvider.notifier).setTileColor(item.id, next);
  }

  Future<void> _launchApp(HomeGridItem item, Rect sourceRect) async {
    if (item.isFolder) {
      _openFolderItem(item);
      return;
    }

    final localApp = item.localApp;
    if (localApp != null) {
      _launchLocalApp(localApp, sourceRect);
      return;
    }

    final app = item.app;
    if (app == null) {
      return;
    }
    ref
        .read(applicationRecentsProvider.notifier)
        .record(desktopApplicationRecentId(app.id));
    final launcher = ref.read(appLauncherProvider);
    if (!widget.useShellLaunchTransition) {
      await launcher.launch(app);
      return;
    }

    final shellController = ref.read(shellControllerProvider.notifier);
    final expectedAppIds = launcher.expectedWindowAppIds(app);
    if (launcher.usesLegacyTextInput(app)) {
      shellController.registerLegacyTextInputAppIds(expectedAppIds);
    }
    final existingWindow = launcher.findOpenWindow(
      app,
      ref.read(shellControllerProvider).openAppWindows,
    );
    if (existingWindow != null) {
      shellController.activateAppFromLauncher(
        window: existingWindow,
        appName: app.name,
        iconPath: app.iconPath,
        sourceRect: sourceRect,
      );
      return;
    }
    final requestId = shellController.beginAppLaunch(
      appName: app.name,
      iconPath: app.iconPath,
      expectedAppIds: expectedAppIds,
    );
    if (requestId == null) {
      return;
    }

    final started = await launcher.launch(app, launchRequestId: requestId);
    if (mounted && !started) {
      shellController.failAppLaunch(requestId);
    }
  }

  void _launchLocalApp(LocalFlutterApplication app, Rect sourceRect) {
    ref
        .read(applicationRecentsProvider.notifier)
        .record(localApplicationRecentId(app.id));
    final displayLayout = ref.read(displayLayoutProvider);
    final mainOutput = displayLayout?.mainOutput;
    final availableBounds = mainOutput == null
        ? Offset.zero & MediaQuery.sizeOf(context)
        : displayLayout!.workAreaOf(mainOutput);
    final statusBarHeight =
        MediaQuery.paddingOf(context).top + ShellMetrics.appStatusBarHeight;
    final applicationBounds = Rect.fromLTWH(
      availableBounds.left,
      availableBounds.top + statusBarHeight,
      availableBounds.width,
      math.max(64.0, availableBounds.height - statusBarHeight),
    );
    final title = app.titleFor(context);
    final launcher = ref.read(localFlutterApplicationLauncherProvider);
    if (!widget.useShellLaunchTransition) {
      launcher.launch(
        app.id,
        availableBounds: availableBounds,
        geometry: applicationBounds,
        title: title,
      );
      return;
    }

    final shellState = ref.read(shellControllerProvider);
    for (final window in shellState.windows) {
      if (window.isLocalFlutter && window.appId == app.id) {
        ref
            .read(shellControllerProvider.notifier)
            .activateAppFromLauncher(
              window: window,
              appName: title,
              iconPath: null,
              sourceRect: sourceRect,
            );
        launcher.launch(
          app.id,
          availableBounds: availableBounds,
          geometry: applicationBounds,
          title: title,
        );
        return;
      }
    }

    final shellController = ref.read(shellControllerProvider.notifier);
    final requestId = shellController.beginAppLaunch(
      appName: title,
      iconPath: null,
      expectedAppIds: <String>[app.id],
    );
    if (requestId == null) {
      return;
    }
    final started = launcher.launch(
      app.id,
      availableBounds: availableBounds,
      geometry: applicationBounds,
      title: title,
    );
    if (!started) {
      shellController.failAppLaunch(requestId);
    }
  }

  void _handlePotentialBackgroundTap(PointerUpEvent event) {
    final startPosition = _tapStartGlobalPosition;
    final startTime = _tapStartTime;
    final invalidTap =
        startPosition == null ||
        startTime == null ||
        _tapMoved ||
        _tapStartedOnInteractiveItem ||
        (event.position - startPosition).distance > _tapMoveTolerance ||
        event.timeStamp - startTime > _backgroundTapMaxDuration ||
        _pointerInsideHomeItem(event.position);
    _resetTapTracking();

    if (invalidTap) {
      _lastBackgroundTapTime = null;
      _lastBackgroundTapPosition = null;
      return;
    }

    final lastTime = _lastBackgroundTapTime;
    final lastPosition = _lastBackgroundTapPosition;
    if (lastTime != null &&
        lastPosition != null &&
        event.timeStamp - lastTime <= _doubleTapMaxInterval &&
        (event.position - lastPosition).distance <=
            _doubleTapDistanceTolerance) {
      _lastBackgroundTapTime = null;
      _lastBackgroundTapPosition = null;
      _requestLockAndScreenOffFromDoubleTap();
      return;
    }

    _lastBackgroundTapTime = event.timeStamp;
    _lastBackgroundTapPosition = event.position;
  }

  void _resetTapTracking() {
    _tapStartGlobalPosition = null;
    _tapStartTime = null;
    _tapMoved = false;
    _tapStartedOnInteractiveItem = false;
  }

  void _requestLockAndScreenOffFromDoubleTap() {
    final now = DateTime.now();
    if (now.difference(_lastScreenOffRequest) < const Duration(seconds: 1)) {
      return;
    }

    _lastScreenOffRequest = now;
    ref.read(shellControllerProvider.notifier).lockAndBlankDisplays();
  }

  bool _pointerInsideHomeItem(Offset globalPosition) {
    if (_currentRows <= 0 ||
        _currentTileWidth <= 0 ||
        _currentTileHeight <= 0) {
      return false;
    }

    final gridState = ref.read(homeGridControllerProvider).asData?.value;
    if (gridState == null) {
      return false;
    }

    final context = _gridViewportKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    final pageSize = HomeGridLayout.columns * _currentRows;
    if (pageSize <= 0) {
      return false;
    }

    final pageStart = gridState.page * pageSize;
    final pageEnd = pageStart + pageSize;
    final localPosition = renderObject.globalToLocal(globalPosition);
    for (
      var index = pageStart;
      index < pageEnd && index < gridState.slots.length;
      index += 1
    ) {
      final item = gridState.slots[index];
      if (item == null) {
        continue;
      }

      final cells = HomeGridLayout.cellsFor(
        index,
        item,
        columns: HomeGridLayout.columns,
      );
      if (cells.any((cell) => cell < pageStart || cell >= pageEnd)) {
        continue;
      }

      final localIndex = index - pageStart;
      final row = localIndex ~/ HomeGridLayout.columns;
      final column = localIndex % HomeGridLayout.columns;
      final rect = Rect.fromLTWH(
        _pageHorizontalPadding +
            column * (_currentTileWidth + HomeGridLayout.gridGap),
        row * (_currentTileHeight + HomeGridLayout.gridGap),
        item.colSpan * _currentTileWidth +
            (item.colSpan - 1) * HomeGridLayout.gridGap,
        item.rowSpan * _currentTileHeight +
            (item.rowSpan - 1) * HomeGridLayout.gridGap,
      ).inflate(8);

      if (rect.contains(localPosition)) {
        return true;
      }
    }

    return false;
  }

  void _handleItemDragAutoPage(Offset globalPosition, int pageCount) {
    final now = DateTime.now();
    if (now.difference(_lastAutoPageTurn) < const Duration(milliseconds: 520)) {
      return;
    }

    final page = ref.read(homeGridControllerProvider).asData?.value.page ?? 0;
    final size = MediaQuery.sizeOf(context);
    final portrait = size.height > size.width;
    final forwardEdge = portrait
        ? globalPosition.dy > size.height - 72
        : globalPosition.dx > size.width - 64;
    final backwardEdge = portrait
        ? globalPosition.dy < 72
        : globalPosition.dx < 64;
    if (forwardEdge && page < pageCount - 1) {
      _lastAutoPageTurn = now;
      unawaited(
        _pageController.nextPage(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    } else if (backwardEdge && page > 0) {
      _lastAutoPageTurn = now;
      unawaited(
        _pageController.previousPage(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _handleItemDragStart(
    HomeGridItem item,
    int fromIndex,
    int pageSize,
    LongPressStartDetails details,
    Size feedbackSize,
  ) {
    _startItemDrag(
      item: item,
      fromIndex: fromIndex,
      pageSize: pageSize,
      pointerGlobalPosition: details.globalPosition,
      localAnchor: details.localPosition,
      feedbackSize: feedbackSize,
    );
  }

  void _startItemDrag({
    required HomeGridItem item,
    required int fromIndex,
    required int pageSize,
    required Offset pointerGlobalPosition,
    required Offset localAnchor,
    required Size feedbackSize,
  }) {
    _dragEndTimer?.cancel();
    _dragEndTimer = null;
    final session = HomeDragSession(
      item: item,
      fromIndex: fromIndex,
      pageSize: pageSize,
      pointerGlobalPosition: pointerGlobalPosition,
      localAnchor: _clampDragAnchor(localAnchor, feedbackSize),
      feedbackSize: feedbackSize,
    );
    final targetedSession = session.copyWith(
      targetIndex: _targetIndexForDragSession(session),
      replaceTargetIndex: true,
    );
    ref
        .read(homeGridControllerProvider.notifier)
        .setDraggingSourceIndex(fromIndex);
    ref.read(homeDragSessionProvider.notifier).setSession(targetedSession);
  }

  void _handleItemResizeModeStart(
    HomeGridItem item,
    int index,
    int pageSize,
    LongPressStartDetails details,
  ) {
    if (!item.resizable) {
      return;
    }
    _dragEndTimer?.cancel();
    _dragEndTimer = null;
    _resizeSession = null;
    ref.read(homeDragSessionProvider.notifier).clear();
    ref.read(homeGridControllerProvider.notifier).setDraggingSourceIndex(null);
    setState(() {
      _resizeModeIndex = index;
    });
  }

  void _handleItemResizeModeMove(
    HomeGridItem item,
    int index,
    int pageSize,
    LongPressMoveUpdateDetails details,
    Size feedbackSize,
  ) {
    if (_resizeModeIndex == null) {
      return;
    }
    if (details.offsetFromOrigin.distance < 28) {
      return;
    }

    final localAnchor = details.localPosition - details.localOffsetFromOrigin;
    _clearResizeMode();
    _startItemDrag(
      item: item,
      fromIndex: index,
      pageSize: pageSize,
      pointerGlobalPosition: details.globalPosition,
      localAnchor: localAnchor,
      feedbackSize: feedbackSize,
    );
    _syncDragSessionToPointer(
      details.globalPosition,
      pageCount: _currentPageCount,
      autoPage: true,
    );
  }

  void _handleItemResizeModeEnd() {
    _resizeSession = null;
  }

  void _handleItemResizeStart(
    HomeGridItem item,
    int index,
    int pageSize,
    DragStartDetails details,
  ) {
    if (!item.resizable ||
        pageSize <= 0 ||
        _currentRows <= 0 ||
        _currentTileWidth <= 0 ||
        _currentTileHeight <= 0) {
      return;
    }
    _dragEndTimer?.cancel();
    _dragEndTimer = null;
    ref.read(homeDragSessionProvider.notifier).clear();
    ref.read(homeGridControllerProvider.notifier).setDraggingSourceIndex(null);
    _resizeSession = _HomeResizeSession(
      item: item,
      index: index,
      pageSize: pageSize,
      startGlobalPosition: details.globalPosition,
      startColSpan: item.colSpan,
      startRowSpan: item.rowSpan,
    );
  }

  void _handleItemResizeUpdate(DragUpdateDetails details) {
    final session = _resizeSession;
    if (session == null) {
      return;
    }
    final target = _targetSpanForResizeSession(session, details.globalPosition);
    final best = _bestResizableSpan(session, target);
    if (best == null) {
      return;
    }

    final gridState = ref.read(homeGridControllerProvider).asData?.value;
    final currentItem =
        gridState != null && session.index < gridState.slots.length
        ? gridState.slots[session.index]
        : null;
    if (currentItem == null ||
        (currentItem.colSpan == best.colSpan &&
            currentItem.rowSpan == best.rowSpan)) {
      return;
    }

    ref
        .read(homeGridControllerProvider.notifier)
        .resizeSlot(
          session.index,
          best.colSpan,
          best.rowSpan,
          session.pageSize,
        );
  }

  void _handleItemResizeEnd() {
    final session = _resizeSession;
    if (session == null) {
      return;
    }
    _resizeSession = null;
  }

  void _clearResizeMode() {
    if (_resizeModeIndex == null && _resizeSession == null) {
      return;
    }

    _resizeSession = null;
    if (mounted) {
      setState(() {
        _resizeModeIndex = null;
      });
    } else {
      _resizeModeIndex = null;
    }
  }

  void _dismissResizeModeIfPointerOutside(Offset globalPosition) {
    if (_resizeModeIndex == null ||
        _currentRows <= 0 ||
        _currentTileWidth <= 0 ||
        _currentTileHeight <= 0) {
      return;
    }

    if (_pointerInsideResizeModeItem(globalPosition)) {
      return;
    }

    _clearResizeMode();
  }

  bool _pointerInsideResizeModeItem(Offset globalPosition) {
    final index = _resizeModeIndex;
    if (index == null) {
      return false;
    }

    final gridState = ref.read(homeGridControllerProvider).asData?.value;
    if (gridState == null || index < 0 || index >= gridState.slots.length) {
      return false;
    }

    final item = gridState.slots[index];
    if (item == null) {
      return false;
    }

    final context = _gridViewportKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    final pageSize = HomeGridLayout.columns * _currentRows;
    if (pageSize <= 0) {
      return false;
    }
    final page = gridState.page;
    final localIndex = index - page * pageSize;
    if (localIndex < 0 || localIndex >= pageSize) {
      return false;
    }

    final row = localIndex ~/ HomeGridLayout.columns;
    final column = localIndex % HomeGridLayout.columns;
    final localPosition = renderObject.globalToLocal(globalPosition);
    final rect = Rect.fromLTWH(
      _pageHorizontalPadding +
          column * (_currentTileWidth + HomeGridLayout.gridGap),
      row * (_currentTileHeight + HomeGridLayout.gridGap),
      item.colSpan * _currentTileWidth +
          (item.colSpan - 1) * HomeGridLayout.gridGap,
      item.rowSpan * _currentTileHeight +
          (item.rowSpan - 1) * HomeGridLayout.gridGap,
    ).inflate(14);
    return rect.contains(localPosition);
  }

  void _handleItemDragUpdate(
    LongPressMoveUpdateDetails details,
    int pageCount,
  ) {
    _syncDragSessionToPointer(
      details.globalPosition,
      pageCount: pageCount,
      autoPage: true,
    );
  }

  void _syncDragSessionToPointer(
    Offset globalPosition, {
    required int pageCount,
    required bool autoPage,
  }) {
    final session = ref.read(homeDragSessionProvider);
    if (session == null) {
      return;
    }
    final next = session.copyWith(
      pointerGlobalPosition: globalPosition,
      replaceTargetIndex: true,
    );
    final targetedNext = next.copyWith(
      targetIndex: _targetIndexForDragSession(next),
      replaceTargetIndex: true,
    );
    ref.read(homeDragSessionProvider.notifier).setSession(targetedNext);
    if (autoPage && pageCount > 1) {
      _handleItemDragAutoPage(globalPosition, pageCount);
    }
  }

  _HomeGridSpan _targetSpanForResizeSession(
    _HomeResizeSession session,
    Offset globalPosition,
  ) {
    final stepX = _currentTileWidth + HomeGridLayout.gridGap;
    final stepY = _currentTileHeight + HomeGridLayout.gridGap;
    final delta = globalPosition - session.startGlobalPosition;
    final colSpan = session.startColSpan + (delta.dx / stepX).round();
    final rowSpan = session.startRowSpan + (delta.dy / stepY).round();

    return _HomeGridSpan(
      colSpan: colSpan
          .clamp(session.item.minColSpan, _maxColSpan(session))
          .toInt(),
      rowSpan: rowSpan
          .clamp(session.item.minRowSpan, _maxRowSpan(session))
          .toInt(),
    );
  }

  _HomeGridSpan? _bestResizableSpan(
    _HomeResizeSession session,
    _HomeGridSpan target,
  ) {
    final controller = ref.read(homeGridControllerProvider.notifier);
    _HomeGridSpan? best;
    var bestDistance = double.infinity;
    var bestAreaDistance = double.infinity;

    for (
      var rowSpan = session.item.minRowSpan;
      rowSpan <= _maxRowSpan(session);
      rowSpan += 1
    ) {
      for (
        var colSpan = session.item.minColSpan;
        colSpan <= _maxColSpan(session);
        colSpan += 1
      ) {
        if (!controller.canResizeSlot(
          session.index,
          colSpan,
          rowSpan,
          session.pageSize,
        )) {
          continue;
        }

        final distance =
            math.pow(colSpan - target.colSpan, 2) +
            math.pow(rowSpan - target.rowSpan, 2);
        final areaDistance =
            (colSpan * rowSpan - target.colSpan * target.rowSpan).abs();
        if (distance < bestDistance ||
            (distance == bestDistance && areaDistance < bestAreaDistance)) {
          best = _HomeGridSpan(colSpan: colSpan, rowSpan: rowSpan);
          bestDistance = distance.toDouble();
          bestAreaDistance = areaDistance.toDouble();
        }
      }
    }

    return best;
  }

  int _maxColSpan(_HomeResizeSession session) {
    final localIndex = session.index % session.pageSize;
    final column = localIndex % HomeGridLayout.columns;
    return math.min(session.item.maxColSpan, HomeGridLayout.columns - column);
  }

  int _maxRowSpan(_HomeResizeSession session) {
    final localIndex = session.index % session.pageSize;
    final row = localIndex ~/ HomeGridLayout.columns;
    return math.min(
      session.item.maxRowSpan,
      math.max(session.item.minRowSpan, _currentRows - row),
    );
  }

  void _handleItemDragEnd([Offset? finalGlobalPosition]) {
    var session = ref.read(homeDragSessionProvider);
    if (session == null) {
      return;
    }
    if (finalGlobalPosition != null) {
      session = session.copyWith(
        pointerGlobalPosition: finalGlobalPosition,
        replaceTargetIndex: true,
      );
      session = session.copyWith(
        targetIndex: _targetIndexForDragSession(session),
        replaceTargetIndex: true,
      );
      ref.read(homeDragSessionProvider.notifier).setSession(session);
    }

    final targetIndex = session.targetIndex;
    final gridController = ref.read(homeGridControllerProvider.notifier);
    if (targetIndex != null &&
        gridController.canMoveSlot(
          session.fromIndex,
          targetIndex,
          session.pageSize,
        )) {
      gridController.moveSlot(session.fromIndex, targetIndex, session.pageSize);
    }

    _dragEndTimer?.cancel();
    _dragEndTimer = Timer(const Duration(milliseconds: 70), () {
      _dragEndTimer = null;
      if (!mounted || ref.read(homeDragSessionProvider) != session) {
        return;
      }
      ref.read(homeDragSessionProvider.notifier).clear();
      ref
          .read(homeGridControllerProvider.notifier)
          .setDraggingSourceIndex(null);
    });
  }

  Offset _clampDragAnchor(Offset anchor, Size size) {
    return Offset(
      anchor.dx.clamp(0.0, size.width).toDouble(),
      anchor.dy.clamp(0.0, size.height).toDouble(),
    );
  }

  int? _targetIndexForDragSession(HomeDragSession session) {
    if (session.pageSize <= 0 ||
        _currentRows <= 0 ||
        _currentTileWidth <= 0 ||
        _currentTileHeight <= 0) {
      return null;
    }

    final gridState = ref.read(homeGridControllerProvider).asData?.value;
    if (gridState == null) {
      return null;
    }

    final context = _gridViewportKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    final pointerLocal = renderObject.globalToLocal(
      session.pointerGlobalPosition,
    );
    final dragRect = session.localAnchor & session.feedbackSize;
    final localRect = Rect.fromLTWH(
      pointerLocal.dx - dragRect.left,
      pointerLocal.dy - dragRect.top,
      dragRect.width,
      dragRect.height,
    );
    final gridRect = Rect.fromLTWH(
      _pageHorizontalPadding,
      0,
      renderObject.size.width - _pageHorizontalPadding * 2,
      renderObject.size.height,
    );
    if (!localRect.overlaps(gridRect)) {
      return null;
    }

    final stepX = _currentTileWidth + HomeGridLayout.gridGap;
    final stepY = _currentTileHeight + HomeGridLayout.gridGap;
    final pageStart = gridState.page * session.pageSize;
    var bestIndex = pageStart;
    var bestOverlap = -1.0;
    var bestDistance = double.infinity;
    final dragCenter = localRect.center;
    final gridController = ref.read(homeGridControllerProvider.notifier);

    for (var row = 0; row <= _currentRows - session.item.rowSpan; row += 1) {
      for (
        var column = 0;
        column <= HomeGridLayout.columns - session.item.colSpan;
        column += 1
      ) {
        final left = _pageHorizontalPadding + column * stepX;
        final top = row * stepY;
        final candidateRect = Rect.fromLTWH(
          left,
          top,
          session.item.colSpan * _currentTileWidth +
              (session.item.colSpan - 1) * HomeGridLayout.gridGap,
          session.item.rowSpan * _currentTileHeight +
              (session.item.rowSpan - 1) * HomeGridLayout.gridGap,
        );
        final overlap = HomeGridLayout.rectOverlapArea(
          localRect,
          candidateRect,
        );
        if (overlap <= 0) {
          continue;
        }

        final index = pageStart + row * HomeGridLayout.columns + column;
        if (!gridController.canMoveSlot(
          session.fromIndex,
          index,
          session.pageSize,
        )) {
          continue;
        }

        final distance = (dragCenter - candidateRect.center).distanceSquared;
        if (overlap > bestOverlap ||
            (overlap == bestOverlap && distance < bestDistance)) {
          bestIndex = index;
          bestOverlap = overlap;
          bestDistance = distance;
        }
      }
    }

    return bestOverlap > 0 ? bestIndex : null;
  }

  Offset? _dragOverlayOffset(HomeDragSession session) {
    final context = _homeStackKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    return renderObject.globalToLocal(session.pointerGlobalPosition) -
        session.localAnchor;
  }

  void _syncSafePage(int currentPage, int safePage) {
    if (currentPage == safePage) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(homeGridControllerProvider.notifier).setPage(safePage);
    });
  }

  void _handlePageChanged(int page, int pageCount) {
    _clearResizeMode();
    ref.read(homeGridControllerProvider.notifier).setPage(page);
    final activeDrag = ref.read(homeDragSessionProvider);
    if (activeDrag != null) {
      _syncDragSessionToPointer(
        activeDrag.pointerGlobalPosition,
        pageCount: pageCount,
        autoPage: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      homeOverlayNavigationProvider.select((state) => state.backRequestSerial),
      (previous, next) {
        if (previous == next || !widget.active || !widget.interactive) {
          return;
        }
        if (_openFolder != null) {
          _closeFolder();
        } else if (_appDrawerOpen) {
          _closeAppDrawer();
        } else if (_resizeModeIndex != null) {
          _clearResizeMode();
        }
      },
    );
    // Page changes happen midway through a swipe. Only the dots need that
    // signal; rebuilding both visible icon grids here disrupts the gesture.
    final contents = ref.watch(
      homeGridControllerProvider.select(
        (value) => (
          slots: value.asData?.value.slots,
          allItems: value.asData?.value.allItems,
          draggingSourceIndex: value.asData?.value.draggingSourceIndex,
          hasError: value.hasError,
        ),
      ),
    );
    return _HomeSurfaceView(
      owner: this,
      active: widget.active,
      interactive: widget.interactive,
      contents: contents,
    );
  }
}
