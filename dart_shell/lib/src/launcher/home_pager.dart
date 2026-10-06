part of 'home_surface.dart';

typedef _HomePageContents = ({
  List<HomeGridItem?>? slots,
  List<HomeGridItem>? allItems,
  int? draggingSourceIndex,
  bool hasError,
});

class _HomePager extends ConsumerWidget {
  const _HomePager({required this.owner, required this.contents});

  final _HomeSurfaceState owner;
  final _HomePageContents contents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabletSettings = ref.watch(
      shellSettingsProvider.select((settings) => settings.tablet),
    );
    final viewSize = MediaQuery.sizeOf(context);
    final portrait = viewSize.height > viewSize.width;
    final compactPortrait =
        tabletSettings.enabled &&
        tabletSettings.portraitCompact &&
        portrait;

    final density = compactPortrait
        ? TabletTileDensity.compact
        : tabletSettings.tileDensity;
    switch (density) {
      case TabletTileDensity.compact:
        HomeGridLayout.gridGap = 8;
        HomeGridLayout.maxTileWidth = 154;
        HomeGridLayout.maxTileHeight = 154;
      case TabletTileDensity.comfortable:
        HomeGridLayout.gridGap = 10;
        HomeGridLayout.maxTileWidth = 184;
        HomeGridLayout.maxTileHeight = 184;
      case TabletTileDensity.spacious:
        HomeGridLayout.gridGap = 14;
        HomeGridLayout.maxTileWidth = 214;
        HomeGridLayout.maxTileHeight = 202;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth =
            constraints.maxWidth - _HomeSurfaceState._pageHorizontalPadding * 2;
        // Wide panels get more columns (not smaller pages):
        // full-bleed paging and no vertical overflow.
        HomeGridLayout.columns = HomeGridLayout.columnsForViewport(gridWidth);
        final tileWidth =
            (gridWidth -
                HomeGridLayout.gridGap * (HomeGridLayout.columns - 1)) /
            HomeGridLayout.columns;
        // Cell content is fixed-size, so height must not
        // follow width past its cap (phone tiles never
        // reach it and keep the tuned aspect).
        final tileHeight = math.min(
          tileWidth / HomeAppPage.childAspectRatio,
          HomeGridLayout.maxTileHeight,
        );
        final rows = HomeGridLayout.rowsForHeight(
          constraints.maxHeight - _HomeSurfaceState._pageDotsReservedHeight,
          tileHeight,
        );
        final pageSize = HomeGridLayout.columns * rows;
        final gridHeight =
            rows * tileHeight + (rows - 1) * HomeGridLayout.gridGap;
        final rowVisualHeight = math.min(
          tileHeight,
          _HomeSurfaceState._appRowVisualHeight,
        );
        final visualRowsHeight =
            (rows - 1) * (tileHeight + HomeGridLayout.gridGap) +
            rowVisualHeight;
        final pageDotsTop =
            visualRowsHeight +
            math.max(
                  0,
                  constraints.maxHeight -
                      visualRowsHeight -
                      _HomeSurfaceState._pageDotsReservedHeight,
                ) /
                3;
        owner._currentTileWidth = tileWidth;
        owner._currentTileHeight = tileHeight;
        owner._currentRows = rows;

        final slots = contents.slots ?? const <HomeGridItem?>[];
        final pageCount = HomeGridLayout.pageCountForSlots(slots, pageSize);
        owner._currentPageCount = pageCount;
        owner._currentPageSize = pageSize;
        final currentPage =
            owner.ref.read(homeGridControllerProvider).asData?.value.page ?? 0;
        final safePage = currentPage.clamp(0, pageCount - 1).toInt();
        owner._syncSafePage(currentPage, safePage);

        final content = contents.slots == null
            ? contents.hasError
                  ? HomeEmptyState(label: context.l10n.commonError)
                  : HomeEmptyState(label: context.l10n.commonLoading)
            : PageView.builder(
                controller: owner._pageController,
                scrollDirection: portrait ? Axis.vertical : Axis.horizontal,
                physics: const PageScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                itemCount: pageCount,
                onPageChanged: (page) =>
                    owner._handlePageChanged(page, pageCount),
                itemBuilder: (context, page) {
                  final start = page * pageSize;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _HomeSurfaceState._pageHorizontalPadding,
                    ),
                    child: HomeAppPage(
                      slots: slots,
                      startIndex: start,
                      pageSize: pageSize,
                      columns: HomeGridLayout.columns,
                      gap: HomeGridLayout.gridGap,
                      tileWidth: tileWidth,
                      tileHeight: tileHeight,
                      draggingSourceIndex: contents.draggingSourceIndex,
                      resizeModeIndex: owner._resizeModeIndex,
                      onLaunch: owner._launchApp,
                      onDragStart: owner._handleItemDragStart,
                      onDragEnd: owner._handleItemDragEnd,
                      onDragUpdate: (details) {
                        owner._handleItemDragUpdate(details, pageCount);
                      },
                      onResizeModeStart: owner._handleItemResizeModeStart,
                      onResizeModeMove: owner._handleItemResizeModeMove,
                      onResizeModeEnd: owner._handleItemResizeModeEnd,
                      onResizeStart: owner._handleItemResizeStart,
                      onResizeUpdate: owner._handleItemResizeUpdate,
                      onResizeEnd: owner._handleItemResizeEnd,
                      onRemove: owner._removeFromStart,
                      onCycleColor: owner._cycleTileColor,
                    ),
                  );
                },
              );

        return Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: double.infinity,
                height: gridHeight,
                child: SizedBox.expand(
                  key: owner._gridViewportKey,
                  child: content,
                ),
              ),
            ),
            if (!portrait)
              Positioned(
                top: pageDotsTop,
                left: 0,
                right: 0,
                child: _HomePageDots(count: pageCount),
              )
            else if (pageCount > 1)
              Positioned(
                right: 6,
                top: 0,
                bottom: 0,
                child: _PhonePageRail(count: pageCount),
              ),
          ],
        );
      },
    );
  }
}

class _HomePageDots extends ConsumerWidget {
  const _HomePageDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      homeGridControllerProvider.select(
        (value) => value.asData?.value.page ?? 0,
      ),
    );
    return PageDots(count: count, active: page.clamp(0, count - 1));
  }
}


class _PhonePageRail extends ConsumerWidget {
  const _PhonePageRail({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      homeGridControllerProvider.select(
        (value) => value.asData?.value.page ?? 0,
      ),
    );
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < count; index += 1)
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(vertical: 3),
              width: index == page ? 4 : 3,
              height: index == page ? 22 : 9,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: index == page ? 0.92 : 0.28,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}
