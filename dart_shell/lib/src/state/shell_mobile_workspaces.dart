part of 'shell_controller.dart';

mixin _MobileWorkspaceController on Notifier<ShellState> {
  DenialBridge get workspaceBridge;
  void focusWindow(DenialWindow window);
  void closeOverview();

  final _workspaceSizes = <int, Size>{};
  Size? _workspaceViewport;
  MobileWorkspace? _workspaceResizeOrigin;
  int _nextWorkspaceId = 1;

  MobileWorkspaceLayout _workspaceLayout(Size size, MobileWorkspace group) =>
      MobileWorkspaceLayout.resolve(
        size,
        group,
        windows: group.members
            .map(state.windowByObjectId)
            .whereType<DenialWindow>(),
      );

  void resetMobileWorkspaceRuntime() {
    _workspaceSizes.clear();
    _workspaceViewport = null;
    _workspaceResizeOrigin = null;
    _nextWorkspaceId = 1;
  }

  void resetMobileWorkspaceDrag() {
    final original = _workspaceResizeOrigin;
    _workspaceResizeOrigin = null;
    if (original != null) _updateWorkspace(original.id, (_) => original);
  }

  void mergeMobileWorkspace(int sourceId, int targetId) {
    if (state.locked || state.lockLayerVisible || sourceId == targetId) return;
    final source = state.windowByObjectId(sourceId);
    final target = state.windowByObjectId(targetId);
    if (source == null ||
        target == null ||
        !source.isUserApp ||
        !target.isUserApp)
      return;
    final sourceGroup = state.workspaceForObject(sourceId);
    final targetGroup = state.workspaceForObject(targetId);
    if (sourceGroup != null && sourceGroup.id == targetGroup?.id) return;
    final members = <int>{
      ...?targetGroup?.members,
      if (targetGroup == null) targetId,
      ...?sourceGroup?.members,
      if (sourceGroup == null) sourceId,
    }.toList();
    final group = MobileWorkspace(
      id: targetGroup?.id ?? _nextWorkspaceId++,
      members: members,
      mode: targetGroup?.mode ?? MobileWorkspaceMode.automatic,
      focusedId: targetGroup?.focusedId ?? targetId,
    );
    state = state.copyWith(
      mobileWorkspaces: [
        for (final old in state.mobileWorkspaces)
          if (old.id != sourceGroup?.id && old.id != targetGroup?.id) old,
        group,
      ],
    );
  }

  void ungroupMobileWorkspace(int id) {
    if (state.locked || state.lockLayerVisible) return;
    state = state.copyWith(
      mobileWorkspaces: [
        for (final group in state.mobileWorkspaces)
          if (group.id != id) group,
      ],
    );
  }

  void focusMobileRecentsEntry(DenialWindow entry) {
    final group = state.workspaceForObject(entry.objectId);
    focusWindow(state.windowByObjectId(group?.focusedId) ?? entry);
  }

  void closeMobileRecentsEntry(DenialWindow entry) {
    if (state.locked || state.lockLayerVisible) return;
    final members =
        state.workspaceForObject(entry.objectId)?.members ?? [entry.objectId];
    if (state.overviewVisible && state.openAppWindowCount <= members.length)
      closeOverview();
    for (final id in members) {
      final window = state.windowByObjectId(id);
      if (window != null) workspaceBridge.closeWindow(window);
    }
  }

  void setMobileWorkspaceMode(int id, MobileWorkspaceMode mode) {
    _updateWorkspace(
      id,
      (group) => group.copyWith(mode: mode, scrollOffset: 0),
    );
  }

  void _updateWorkspace(
    int id,
    MobileWorkspace Function(MobileWorkspace) update,
  ) {
    if (state.locked || state.lockLayerVisible) return;
    final index = state.mobileWorkspaces.indexWhere((group) => group.id == id);
    if (index < 0) return;
    final groups = List<MobileWorkspace>.of(state.mobileWorkspaces);
    groups[index] = update(groups[index]);
    state = state.copyWith(mobileWorkspaces: groups);
  }

  void scrollMobileWorkspace(int id, double delta) {
    final size = _workspaceViewport;
    if (size == null || !delta.isFinite) return;
    _updateWorkspace(id, (group) {
      final layout = _workspaceLayout(size, group);
      return group.copyWith(
        scrollOffset: (layout.offset + delta)
            .clamp(0.0, layout.maxScroll)
            .toDouble(),
      );
    });
  }

  void settleMobileWorkspaceScroll(int id) {
    final size = _workspaceViewport;
    if (size == null || state.locked || state.lockLayerVisible) return;
    final groups = state.mobileWorkspaces.where((group) => group.id == id);
    if (groups.isEmpty) return;
    final layout = _workspaceLayout(size, groups.first);
    final panes = layout.panes.toList()
      ..sort((a, b) {
        double area(Rect rect) => rect.isEmpty ? 0 : rect.width * rect.height;
        return area(
          b.frame.intersect(layout.viewport),
        ).compareTo(area(a.frame.intersect(layout.viewport)));
      });
    final window = state.windowByObjectId(panes.first.objectId);
    if (window != null && state.foregroundObjectId != window.objectId)
      focusWindow(window);
  }

  void beginMobileWorkspaceResize(int id) {
    if (state.locked || state.lockLayerVisible) return;
    final groups = state.mobileWorkspaces.where((group) => group.id == id);
    _workspaceResizeOrigin = groups.isEmpty ? null : groups.first;
  }

  void resizeMobileWorkspace(int id, int divider, double delta) {
    final size = _workspaceViewport;
    if (size == null || _workspaceResizeOrigin?.id != id) return;
    _updateWorkspace(
      id,
      (group) => group.copyWith(
        weights: _workspaceLayout(
          size,
          group,
        ).resizedWeights(group, divider, delta),
      ),
    );
  }

  void finishMobileWorkspaceResize({bool cancel = false}) {
    final original = _workspaceResizeOrigin;
    _workspaceResizeOrigin = null;
    if (original == null) return;
    _updateWorkspace(
      original.id,
      (group) => cancel ? original : group.copyWith(),
    );
  }

  void synchronizeMobileWorkspaceGeometry(Size size) {
    if (state.locked || state.lockLayerVisible || size.isEmpty) return;
    if (_workspaceResizeOrigin != null &&
        (state.overviewVisible ||
            state.homeTransitionActive ||
            state.launchTransitionActive ||
            state.activeMobileWorkspace?.id != _workspaceResizeOrigin!.id)) {
      finishMobileWorkspaceResize(cancel: true);
    }
    if (_workspaceViewport != size) {
      _workspaceViewport = size;
      finishMobileWorkspaceResize(cancel: true);
    }
    _workspaceViewport = size;
    if (_workspaceResizeOrigin != null &&
        !state.mobileWorkspaces.any(
          (group) => group.id == _workspaceResizeOrigin!.id,
        )) {
      _workspaceResizeOrigin = null;
    }
    final grouped = {
      for (final group in state.mobileWorkspaces) ...group.members,
    };
    for (final id in _workspaceSizes.keys.toList()) {
      if (!grouped.contains(id)) {
        final window = state.windowByObjectId(id);
        if (window != null)
          workspaceBridge.configureMobileWorkspaceWindow(window, null);
        _workspaceSizes.remove(id);
      }
    }
    if (_workspaceResizeOrigin != null) return;
    for (final group in state.mobileWorkspaces) {
      final layout = _workspaceLayout(size, group);
      for (final pane in layout.panes) {
        final window = state.windowByObjectId(pane.objectId);
        if (window == null) continue;
        final target = pane.clientFrame(window).size;
        if (target.width < 64 ||
            target.height < 64 ||
            _workspaceSizes[pane.objectId] == target)
          continue;
        workspaceBridge.configureMobileWorkspaceWindow(window, target);
        _workspaceSizes[pane.objectId] = target;
      }
    }
  }
}
