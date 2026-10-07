import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../localization/denial_localizations.dart';
import '../../models/clipboard_history.dart';
import '../../services/fcitx_kimpanel_service.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';

enum ShellOskKeyAction { text, key, space, backspace, enter }

enum ShellOskKeyPhase { tap, pressed, released }

class ShellOskKeyIntent {
  const ShellOskKeyIntent._({
    required this.action,
    this.text,
    this.key,
    this.ctrl = false,
    this.phase = ShellOskKeyPhase.tap,
  });

  const ShellOskKeyIntent.text(String value)
    : this._(action: ShellOskKeyAction.text, text: value);

  const ShellOskKeyIntent.key(String value, {bool ctrl = false})
    : this._(action: ShellOskKeyAction.key, key: value, ctrl: ctrl);

  const ShellOskKeyIntent.space({bool ctrl = false})
    : this._(
        action: ShellOskKeyAction.space,
        text: ' ',
        key: 'space',
        ctrl: ctrl,
      );

  const ShellOskKeyIntent.backspace({
    bool ctrl = false,
    ShellOskKeyPhase phase = ShellOskKeyPhase.tap,
  }) : this._(
         action: ShellOskKeyAction.backspace,
         key: 'BackSpace',
         ctrl: ctrl,
         phase: phase,
       );

  const ShellOskKeyIntent.enter({bool ctrl = false})
    : this._(action: ShellOskKeyAction.enter, key: 'Return', ctrl: ctrl);

  final ShellOskKeyAction action;
  final String? text;
  final String? key;
  final bool ctrl;
  final ShellOskKeyPhase phase;
}

class ShellOskPanel extends StatefulWidget {
  const ShellOskPanel({
    super.key,
    this.onKey,
    this.onKeyTap,
    this.onDismiss,
    this.loadClipboard,
    this.pasteClipboard,
    this.candidateListenable,
    this.onCandidateSelected,
    this.onCandidatePreviousPage,
    this.onCandidateNextPage,
  });

  final ValueChanged<ShellOskKeyIntent>? onKey;
  final VoidCallback? onKeyTap;
  final VoidCallback? onDismiss;
  final Future<ClipboardHistorySnapshot> Function()? loadClipboard;
  final Future<void> Function(ClipboardHistoryEntry entry)? pasteClipboard;
  final ValueListenable<FcitxCandidateSnapshot>? candidateListenable;
  final ValueChanged<int>? onCandidateSelected;
  final VoidCallback? onCandidatePreviousPage;
  final VoidCallback? onCandidateNextPage;

  @override
  State<ShellOskPanel> createState() => _ShellOskPanelState();
}

class _ShellOskPanelState extends State<ShellOskPanel> {
  _OskLayer _layer = _OskLayer.letters;
  _OskPane _pane = _OskPane.keyboard;
  _OskLayoutMode _layoutMode = _OskLayoutMode.standard;
  bool _shiftEnabled = false;
  bool _capsLocked = false;
  bool _ctrlArmed = false;
  bool _chineseInputEnabled = false;
  DateTime? _lastShiftTapAt;
  Future<ClipboardHistorySnapshot>? _clipboardSnapshot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      // The mobile sheet is retained while hidden. Keep the fresh-keyboard
      // behavior previously supplied by unmounting it on close.
      _layer = _OskLayer.letters;
      _pane = _OskPane.keyboard;
      _shiftEnabled = false;
      _capsLocked = false;
      _ctrlArmed = false;
      _lastShiftTapAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = math.max(MediaQuery.paddingOf(context).bottom, 8.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 560 || constraints.maxHeight < 390;
        final horizontalPadding = compact ? 6.0 : 8.0;
        final topPadding = compact ? 6.0 : 8.0;
        final toolbarHeight = compact ? 38.0 : 42.0;
        final keyGap = compact ? 4.0 : 5.0;
        final rowGap = compact ? 4.0 : 5.0;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPadding,
          ),
          child: Column(
            children: [
              SizedBox(
                height: toolbarHeight,
                child: _WindowsOskToolbar(
                  pane: _pane,
                  layoutMode: _layoutMode,
                  chineseInputEnabled: _chineseInputEnabled,
                  candidateListenable: widget.candidateListenable,
                  onCandidateSelected: _selectCandidate,
                  onCandidatePreviousPage: _previousCandidatePage,
                  onCandidateNextPage: _nextCandidatePage,
                  onKeyboard: () => _setPane(_OskPane.keyboard),
                  onEmoji: () => _setPane(_OskPane.emoji),
                  onClipboard: _openClipboard,
                  onLayouts: () => _setPane(_OskPane.layouts),
                  onToggleLanguage: () =>
                      _handleControl(_OskControl.inputMethod),
                  onDismiss: widget.onDismiss,
                ),
              ),
              SizedBox(height: compact ? 4 : 6),
              Expanded(
                child: switch (_pane) {
                  _OskPane.keyboard => _buildKeyboardRows(
                    compact: compact,
                    keyGap: keyGap,
                    rowGap: rowGap,
                  ),
                  _OskPane.emoji => _OskEmojiPane(onEmoji: _insertEmoji),
                  _OskPane.clipboard => _OskClipboardPane(
                    snapshot: _clipboardSnapshot,
                    onPaste: _pasteClipboardEntry,
                    onRefresh: _refreshClipboard,
                  ),
                  _OskPane.layouts => _OskLayoutPane(
                    selected: _layoutMode,
                    onSelected: _selectLayout,
                  ),
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKeyboardRows({
    required bool compact,
    required double keyGap,
    required double rowGap,
  }) {
    final rows = _rowsForCurrentLayer();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxRowHeight = rows.length <= 4
            ? (compact ? 68.0 : 74.0)
            : (compact ? 54.0 : 60.0);
        final availableHeight =
            constraints.maxHeight - rowGap * (rows.length - 1);
        final minRowHeight = rows.length <= 4 ? 42.0 : 32.0;
        final rowHeight = (availableHeight / rows.length)
            .clamp(minRowHeight, maxRowHeight)
            .toDouble();
        final splitGap = _layoutMode == _OskLayoutMode.split
            ? (constraints.maxWidth * 0.105).clamp(58.0, 96.0).toDouble()
            : 0.0;

        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              _OskRow(
                row: rows[index],
                keyGap: keyGap,
                rowHeight: rowHeight,
                splitGap: splitGap,
                shiftEnabled: _shiftEnabled,
                ctrlArmed: _ctrlArmed,
                chineseInputEnabled: _chineseInputEnabled,
                onKey: _handleKey,
                onKeyLongPress: _handleKeyLongPress,
                onKeyDown: _handleKeyDown,
                onKeyUp: _handleKeyUp,
              ),
              if (index != rows.length - 1) SizedBox(height: rowGap),
            ],
          ],
        );
      },
    );
  }

  List<_OskRowData> _rowsForCurrentLayer() {
    if (_layoutMode == _OskLayoutMode.traditional &&
        _layer == _OskLayer.letters) {
      return _traditionalRows;
    }
    return switch (_layer) {
      _OskLayer.letters => _letterRows,
      _OskLayer.numbers => _numberRows,
      _OskLayer.symbols => _extraSymbolRows,
    };
  }

  void _setPane(_OskPane pane) {
    widget.onKeyTap?.call();
    if (_pane == pane) {
      if (pane != _OskPane.keyboard) {
        setState(() => _pane = _OskPane.keyboard);
      }
      return;
    }
    setState(() => _pane = pane);
  }

  void _openClipboard() {
    widget.onKeyTap?.call();
    setState(() {
      _pane = _OskPane.clipboard;
      _clipboardSnapshot = widget.loadClipboard?.call();
    });
  }

  void _refreshClipboard() {
    setState(() {
      _clipboardSnapshot = widget.loadClipboard?.call();
    });
  }

  Future<void> _pasteClipboardEntry(ClipboardHistoryEntry entry) async {
    widget.onKeyTap?.call();
    try {
      final paste = widget.pasteClipboard;
      if (paste != null) {
        await paste(entry);
      } else {
        widget.onKey?.call(const ShellOskKeyIntent.key('v', ctrl: true));
      }
      if (mounted) {
        setState(() => _pane = _OskPane.keyboard);
      }
    } catch (_) {
      if (mounted) {
        _refreshClipboard();
      }
    }
  }

  void _insertEmoji(String emoji) {
    widget.onKeyTap?.call();
    widget.onKey?.call(ShellOskKeyIntent.text(emoji));
  }

  void _selectCandidate(int index) {
    widget.onKeyTap?.call();
    widget.onCandidateSelected?.call(index);
  }

  void _previousCandidatePage() {
    widget.onKeyTap?.call();
    widget.onCandidatePreviousPage?.call();
  }

  void _nextCandidatePage() {
    widget.onKeyTap?.call();
    widget.onCandidateNextPage?.call();
  }

  void _selectLayout(_OskLayoutMode mode) {
    widget.onKeyTap?.call();
    setState(() {
      _layoutMode = mode;
      _pane = _OskPane.keyboard;
      _layer = _OskLayer.letters;
      _shiftEnabled = false;
      _capsLocked = false;
      _ctrlArmed = false;
    });
  }

  void _handleKey(_OskKeySpec spec) {
    widget.onKeyTap?.call();

    final control = spec.control;
    if (control != null) {
      _handleControl(control);
      return;
    }

    if (_ctrlArmed) {
      final key = spec.namedKey(shiftEnabled: _shiftEnabled);
      if (key != null) {
        widget.onKey?.call(ShellOskKeyIntent.key(key, ctrl: true));
        setState(() {
          _ctrlArmed = false;
          if (_layer == _OskLayer.letters &&
              _shiftEnabled &&
              !_capsLocked &&
              spec.isLetter) {
            _shiftEnabled = false;
          }
        });
        return;
      }
    }

    final text = spec.outputText(shiftEnabled: _shiftEnabled);
    widget.onKey?.call(ShellOskKeyIntent.text(text));
    if (_layer == _OskLayer.letters &&
        _shiftEnabled &&
        !_capsLocked &&
        spec.isLetter) {
      setState(() => _shiftEnabled = false);
    }
  }

  void _handleControl(_OskControl control) {
    switch (control) {
      case _OskControl.shift:
        final now = DateTime.now();
        final doubleTap =
            _lastShiftTapAt != null &&
            now.difference(_lastShiftTapAt!) <=
                const Duration(milliseconds: 420);
        setState(() {
          if (_capsLocked) {
            _capsLocked = false;
            _shiftEnabled = false;
          } else if (doubleTap && _shiftEnabled) {
            _capsLocked = true;
            _shiftEnabled = true;
          } else {
            _shiftEnabled = !_shiftEnabled;
          }
          _lastShiftTapAt = now;
        });
      case _OskControl.symbols:
        setState(() {
          _layer = _OskLayer.numbers;
          _shiftEnabled = false;
          _ctrlArmed = false;
        });
      case _OskControl.extraSymbols:
        setState(() {
          _layer = _OskLayer.symbols;
          _shiftEnabled = false;
          _ctrlArmed = false;
        });
      case _OskControl.letters:
        setState(() {
          _layer = _OskLayer.letters;
          _shiftEnabled = false;
          _ctrlArmed = false;
        });
      case _OskControl.inputMethod:
        widget.onKey?.call(const ShellOskKeyIntent.key('space', ctrl: true));
        setState(() {
          _chineseInputEnabled = !_chineseInputEnabled;
          _shiftEnabled = false;
          _ctrlArmed = false;
        });
      case _OskControl.ctrl:
        setState(() {
          _ctrlArmed = !_ctrlArmed;
          _shiftEnabled = false;
        });
      case _OskControl.escape:
        _sendKey(ShellOskKeyIntent.key('Escape', ctrl: _ctrlArmed));
      case _OskControl.tab:
        _sendKey(ShellOskKeyIntent.key('Tab', ctrl: _ctrlArmed));
      case _OskControl.delete:
        _sendKey(ShellOskKeyIntent.key('Delete', ctrl: _ctrlArmed));
      case _OskControl.space:
        _sendKeyOrText(
          textIntent: ShellOskKeyIntent.space(ctrl: _ctrlArmed),
          key: 'space',
        );
      case _OskControl.backspace:
        _sendKey(ShellOskKeyIntent.backspace(ctrl: _ctrlArmed));
      case _OskControl.enter:
        _sendKey(ShellOskKeyIntent.enter(ctrl: _ctrlArmed));
      case _OskControl.arrowLeft:
        _sendKey(ShellOskKeyIntent.key('Left', ctrl: _ctrlArmed));
      case _OskControl.arrowRight:
        _sendKey(ShellOskKeyIntent.key('Right', ctrl: _ctrlArmed));
      case _OskControl.arrowUp:
        _sendKey(ShellOskKeyIntent.key('Up', ctrl: _ctrlArmed));
      case _OskControl.arrowDown:
        _sendKey(ShellOskKeyIntent.key('Down', ctrl: _ctrlArmed));
    }
  }

  void _handleKeyLongPress(_OskKeySpec spec) {
    if (spec.control != _OskControl.symbols) {
      return;
    }
    widget.onKeyTap?.call();
    setState(() {
      _ctrlArmed = true;
      _shiftEnabled = false;
    });
  }

  void _handleKeyDown(_OskKeySpec spec) {
    if (spec.control != _OskControl.backspace || _ctrlArmed) {
      return;
    }
    widget.onKeyTap?.call();
    widget.onKey?.call(
      const ShellOskKeyIntent.backspace(phase: ShellOskKeyPhase.pressed),
    );
  }

  void _handleKeyUp(_OskKeySpec spec) {
    if (spec.control != _OskControl.backspace) {
      return;
    }
    widget.onKey?.call(
      const ShellOskKeyIntent.backspace(phase: ShellOskKeyPhase.released),
    );
  }

  void _sendKey(ShellOskKeyIntent intent) {
    widget.onKey?.call(intent);
    _consumeCtrl();
  }

  void _sendKeyOrText({
    required ShellOskKeyIntent textIntent,
    required String key,
  }) {
    if (_ctrlArmed) {
      widget.onKey?.call(ShellOskKeyIntent.key(key, ctrl: true));
      _consumeCtrl();
      return;
    }
    widget.onKey?.call(textIntent);
  }

  void _consumeCtrl() {
    if (!_ctrlArmed) {
      return;
    }
    setState(() => _ctrlArmed = false);
  }
}

class _WindowsOskToolbar extends StatelessWidget {
  const _WindowsOskToolbar({
    required this.pane,
    required this.layoutMode,
    required this.chineseInputEnabled,
    required this.candidateListenable,
    required this.onCandidateSelected,
    required this.onCandidatePreviousPage,
    required this.onCandidateNextPage,
    required this.onKeyboard,
    required this.onEmoji,
    required this.onClipboard,
    required this.onLayouts,
    required this.onToggleLanguage,
    required this.onDismiss,
  });

  final _OskPane pane;
  final _OskLayoutMode layoutMode;
  final bool chineseInputEnabled;
  final ValueListenable<FcitxCandidateSnapshot>? candidateListenable;
  final ValueChanged<int>? onCandidateSelected;
  final VoidCallback? onCandidatePreviousPage;
  final VoidCallback? onCandidateNextPage;
  final VoidCallback onKeyboard;
  final VoidCallback onEmoji;
  final VoidCallback onClipboard;
  final VoidCallback onLayouts;
  final VoidCallback onToggleLanguage;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Center(
            child: Icon(
              Icons.drag_handle_rounded,
              size: 19,
              color: context.shellColors.textTertiary,
            ),
          ),
        ),
        _OskToolbarButton(
          key: const ValueKey('osk-keyboard-pane'),
          icon: Icons.keyboard_alt_outlined,
          selected: pane == _OskPane.keyboard,
          onTap: onKeyboard,
          semanticLabel: '键盘',
        ),
        const SizedBox(width: 4),
        _OskToolbarButton(
          key: const ValueKey('osk-emoji-pane'),
          icon: Icons.emoji_emotions_outlined,
          selected: pane == _OskPane.emoji,
          onTap: onEmoji,
          semanticLabel: '表情',
        ),
        const SizedBox(width: 4),
        _OskToolbarButton(
          key: const ValueKey('osk-clipboard-pane'),
          icon: Icons.content_paste_rounded,
          selected: pane == _OskPane.clipboard,
          onTap: onClipboard,
          semanticLabel: '剪贴板',
        ),
        const SizedBox(width: 4),
        _OskToolbarButton(
          key: const ValueKey('osk-layout-pane'),
          icon: layoutMode == _OskLayoutMode.split
              ? Icons.view_week_outlined
              : Icons.keyboard_rounded,
          selected: pane == _OskPane.layouts,
          onTap: onLayouts,
          semanticLabel: '键盘布局',
        ),
        const SizedBox(width: 8),
        Expanded(
          child: pane == _OskPane.keyboard
              ? _WindowsCandidateStrip(
                  candidateListenable: candidateListenable,
                  onSelected: onCandidateSelected,
                  onPreviousPage: onCandidatePreviousPage,
                  onNextPage: onCandidateNextPage,
                )
              : const SizedBox.expand(),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          key: const ValueKey('osk-language-toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: onToggleLanguage,
          child: Container(
            width: 54,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: chineseInputEnabled
                  ? context.shellTheme.accentPalette.container
                  : context.shellColors.surfaceContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: chineseInputEnabled
                    ? ShellTheme.of(context).accent
                    : context.shellColors.hairlineSoft,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              chineseInputEnabled ? '中' : 'ENG',
              style: ShellText.base.copyWith(
                color: chineseInputEnabled
                    ? context.shellTheme.accentPalette.onContainer
                    : context.shellColors.panelText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _OskToolbarButton(
          key: const ValueKey('osk-hide-keyboard'),
          icon: Icons.keyboard_hide_rounded,
          onTap: onDismiss,
          semanticLabel: '隐藏键盘',
        ),
      ],
    );
  }
}

class _WindowsCandidateStrip extends StatelessWidget {
  const _WindowsCandidateStrip({
    required this.candidateListenable,
    required this.onSelected,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final ValueListenable<FcitxCandidateSnapshot>? candidateListenable;
  final ValueChanged<int>? onSelected;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  Widget build(BuildContext context) {
    final listenable = candidateListenable;
    if (listenable == null) {
      return const SizedBox.expand(key: ValueKey('osk-candidates-empty'));
    }
    return ValueListenableBuilder<FcitxCandidateSnapshot>(
      valueListenable: listenable,
      builder: (context, snapshot, _) {
        final show =
            snapshot.available && snapshot.visible && snapshot.items.isNotEmpty;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: !show
              ? const SizedBox.expand(key: ValueKey('osk-candidates-empty'))
              : Row(
                  key: const ValueKey('osk-candidates-visible'),
                  children: [
                    Expanded(
                      child: ListView.separated(
                        key: const ValueKey('osk-candidate-list'),
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        itemCount: snapshot.items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 2),
                        itemBuilder: (context, index) {
                          final item = snapshot.items[index];
                          return _OskCandidateButton(
                            key: ValueKey(
                              'osk-candidate-' + item.index.toString(),
                            ),
                            item: item,
                            selected: snapshot.cursor == item.index,
                            onTap: onSelected == null
                                ? null
                                : () => onSelected!(item.index),
                          );
                        },
                      ),
                    ),
                    if (snapshot.hasPrevious || snapshot.hasNext) ...[
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 20,
                        width: 1,
                        child: ColoredBox(
                          color: context.shellColors.hairlineSoft,
                        ),
                      ),
                      const SizedBox(width: 2),
                      _OskCandidatePageButton(
                        key: const ValueKey('osk-candidate-page-up'),
                        icon: Icons.chevron_left_rounded,
                        enabled: snapshot.hasPrevious,
                        onTap: onPreviousPage,
                        semanticLabel: '上一页候选词',
                      ),
                      _OskCandidatePageButton(
                        key: const ValueKey('osk-candidate-page-down'),
                        icon: Icons.chevron_right_rounded,
                        enabled: snapshot.hasNext,
                        onTap: onNextPage,
                        semanticLabel: '下一页候选词',
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _OskCandidateButton extends StatefulWidget {
  const _OskCandidateButton({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final FcitxCandidateItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_OskCandidateButton> createState() => _OskCandidateButtonState();
}

class _OskCandidateButtonState extends State<_OskCandidateButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || widget.onTap == null) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.shellTheme.accentPalette;
    final background = widget.selected
        ? accent.container
        : _pressed
        ? context.shellColors.surfaceContainerHighest
        : const Color(0x00000000);
    final foreground = widget.selected
        ? accent.onContainer
        : context.shellColors.panelText;
    final labelColor = widget.selected
        ? accent.onContainer.withValues(alpha: 0.72)
        : context.shellColors.textTertiary;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: [
        if (widget.item.label.isNotEmpty) widget.item.label,
        widget.item.text,
      ].join(' '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
            height: 32,
            constraints: const BoxConstraints(maxWidth: 210),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.item.label.isNotEmpty) ...[
                  Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: ShellText.base.copyWith(
                      color: labelColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    widget.item.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: ShellText.base.copyWith(
                      color: foreground,
                      fontSize: 16,
                      fontWeight: widget.selected
                          ? FontWeight.w600
                          : FontWeight.w500,
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

class _OskCandidatePageButton extends StatelessWidget {
  const _OskCandidatePageButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 30,
          height: 32,
          child: Center(
            child: Icon(
              icon,
              size: 19,
              color: enabled
                  ? context.shellColors.panelText
                  : context.shellColors.textTertiary.withValues(alpha: 0.38),
            ),
          ),
        ),
      ),
    );
  }
}

class _OskToolbarButton extends StatelessWidget {
  const _OskToolbarButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 32,
          decoration: BoxDecoration(
            color: selected
                ? context.shellColors.surfaceContainerHighest
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 20,
            color: selected
                ? context.shellColors.panelText
                : context.shellColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _OskEmojiPane extends StatelessWidget {
  const _OskEmojiPane({required this.onEmoji});

  final ValueChanged<String> onEmoji;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 54).floor().clamp(7, 14);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            childAspectRatio: 1.08,
          ),
          itemCount: _commonEmoji.length,
          itemBuilder: (context, index) {
            final emoji = _commonEmoji[index];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onEmoji(emoji),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.shellColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: context.shellColors.hairlineSoft),
                ),
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(
                      fontSize: 26,
                      height: 1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _OskClipboardPane extends StatelessWidget {
  const _OskClipboardPane({
    required this.snapshot,
    required this.onPaste,
    required this.onRefresh,
  });

  final Future<ClipboardHistorySnapshot>? snapshot;
  final ValueChanged<ClipboardHistoryEntry> onPaste;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final future = snapshot;
    if (future == null) {
      return const _OskPaneMessage(
        icon: Icons.content_paste_rounded,
        title: '剪贴板',
        subtitle: '打开后显示最近复制的内容',
      );
    }
    return FutureBuilder<ClipboardHistorySnapshot>(
      future: future,
      builder: (context, async) {
        if (async.connectionState != ConnectionState.done) {
          return const Center(child: SizedBox(width: 28, height: 28));
        }
        if (async.hasError) {
          return _OskPaneMessage(
            icon: Icons.refresh_rounded,
            title: '剪贴板暂不可用',
            subtitle: '点此重新加载',
            onTap: onRefresh,
          );
        }
        final data = async.data;
        if (data == null || data.locked) {
          return const _OskPaneMessage(
            icon: Icons.lock_outline_rounded,
            title: '剪贴板已锁定',
            subtitle: '解锁会话后可查看历史',
          );
        }
        final entries = data.entries.take(18).toList(growable: false);
        if (entries.isEmpty) {
          return const _OskPaneMessage(
            icon: Icons.content_paste_off_rounded,
            title: '剪贴板是空的',
            subtitle: '复制文字或图片后会显示在这里',
          );
        }
        return Column(
          children: [
            SizedBox(
              height: 30,
              child: Row(
                children: [
                  Text(
                    '剪贴板历史',
                    style: ShellText.base.copyWith(
                      color: context.shellColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  _OskToolbarButton(
                    icon: Icons.refresh_rounded,
                    onTap: onRefresh,
                    semanticLabel: '刷新剪贴板',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: 2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 2.3,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final preview = entry.isImage
                      ? '图片 ' +
                            entry.width.toString() +
                            '×' +
                            entry.height.toString()
                      : entry.preview.trim();
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPaste(entry),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.shellColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: entry.pinned
                              ? ShellTheme.of(context).accent
                              : context.shellColors.hairlineSoft,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          preview.isEmpty ? '空内容' : preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: ShellText.base.copyWith(
                            color: context.shellColors.panelText,
                            fontSize: 12,
                            height: 1.18,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OskLayoutPane extends StatelessWidget {
  const _OskLayoutPane({required this.selected, required this.onSelected});

  final _OskLayoutMode selected;
  final ValueChanged<_OskLayoutMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OskLayoutChoice(
            icon: Icons.keyboard_alt_outlined,
            title: '默认',
            subtitle: '大键帽，适合触摸',
            selected: selected == _OskLayoutMode.standard,
            onTap: () => onSelected(_OskLayoutMode.standard),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _OskLayoutChoice(
            icon: Icons.view_week_outlined,
            title: '拆分',
            subtitle: '左右分开，双手握持',
            selected: selected == _OskLayoutMode.split,
            onTap: () => onSelected(_OskLayoutMode.split),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _OskLayoutChoice(
            icon: Icons.keyboard_rounded,
            title: '传统',
            subtitle: 'Esc / Tab / Ctrl / 方向键',
            selected: selected == _OskLayoutMode.traditional,
            onTap: () => onSelected(_OskLayoutMode.traditional),
          ),
        ),
      ],
    );
  }
}

class _OskLayoutChoice extends StatelessWidget {
  const _OskLayoutChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? context.shellTheme.accentPalette.container
              : context.shellColors.surfaceContainer,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? ShellTheme.of(context).accent
                : context.shellColors.hairlineSoft,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 26,
                color: selected
                    ? context.shellTheme.accentPalette.onContainer
                    : context.shellColors.panelText,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: ShellText.base.copyWith(
                  color: context.shellColors.panelText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: ShellText.base.copyWith(
                  color: context.shellColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OskPaneMessage extends StatelessWidget {
  const _OskPaneMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: context.shellColors.textSecondary),
          const SizedBox(height: 8),
          Text(
            title,
            style: ShellText.base.copyWith(
              color: context.shellColors.panelText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: ShellText.base.copyWith(
              color: context.shellColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

class _OskRow extends StatelessWidget {
  const _OskRow({
    required this.row,
    required this.keyGap,
    required this.rowHeight,
    required this.splitGap,
    required this.shiftEnabled,
    required this.ctrlArmed,
    required this.chineseInputEnabled,
    required this.onKey,
    required this.onKeyLongPress,
    required this.onKeyDown,
    required this.onKeyUp,
  });

  final _OskRowData row;
  final double keyGap;
  final double rowHeight;
  final double splitGap;
  final bool shiftEnabled;
  final bool ctrlArmed;
  final bool chineseInputEnabled;
  final ValueChanged<_OskKeySpec> onKey;
  final ValueChanged<_OskKeySpec> onKeyLongPress;
  final ValueChanged<_OskKeySpec> onKeyDown;
  final ValueChanged<_OskKeySpec> onKeyUp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inset = math.min(row.sideInset, constraints.maxWidth * 0.08);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < row.keys.length; index++) ...[
                  Expanded(
                    flex: row.keys[index].flex,
                    child: _OskKeyButton(
                      key: ValueKey<String>(row.keys[index].animationKey),
                      spec: row.keys[index],
                      selected: row.keys[index].isSelected(
                        shiftEnabled: shiftEnabled,
                        ctrlArmed: ctrlArmed,
                        chineseInputEnabled: chineseInputEnabled,
                      ),
                      shiftEnabled: shiftEnabled,
                      ctrlArmed: ctrlArmed,
                      chineseInputEnabled: chineseInputEnabled,
                      onPressed: () => onKey(row.keys[index]),
                      onLongPress: () => onKeyLongPress(row.keys[index]),
                      holdEnabled:
                          row.keys[index].control == _OskControl.backspace &&
                          !ctrlArmed,
                      onHoldStarted: () => onKeyDown(row.keys[index]),
                      onHoldEnded: () => onKeyUp(row.keys[index]),
                    ),
                  ),
                  if (splitGap > 0 && row.splitAfter == index + 1)
                    SizedBox(width: splitGap),
                  if (index != row.keys.length - 1) SizedBox(width: keyGap),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OskKeyButton extends StatefulWidget {
  const _OskKeyButton({
    super.key,
    required this.spec,
    required this.selected,
    required this.shiftEnabled,
    required this.ctrlArmed,
    required this.chineseInputEnabled,
    required this.onPressed,
    required this.onLongPress,
    required this.holdEnabled,
    required this.onHoldStarted,
    required this.onHoldEnded,
  });

  final _OskKeySpec spec;
  final bool selected;
  final bool shiftEnabled;
  final bool ctrlArmed;
  final bool chineseInputEnabled;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  final bool holdEnabled;
  final VoidCallback onHoldStarted;
  final VoidCallback onHoldEnded;

  @override
  State<_OskKeyButton> createState() => _OskKeyButtonState();
}

class _OskKeyButtonState extends State<_OskKeyButton>
    with SingleTickerProviderStateMixin {
  static const Duration _minimumVisibleDuration = Duration(milliseconds: 42);
  static const Duration _fadeOutDuration = Duration(milliseconds: 90);

  late final AnimationController _glow = AnimationController(
    vsync: this,
    value: 0,
  );
  DateTime? _lastPressStartedAt;
  bool _pressed = false;
  bool _holdActive = false;
  bool _enabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.valuesOf(context).enabled;
    if (!_enabled) {
      // Offstage alone neither cancels a held native key nor its animation.
      _finishHold();
      _pressed = false;
      _lastPressStartedAt = null;
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _finishHold();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final control = widget.spec.control;
    final accent = ShellTheme.of(context).accent;
    final background = _backgroundFor(widget.spec, widget.selected);
    final baseBorder = widget.selected
        ? accent
        : context.shellColors.hairlineSoft;
    final baseForeground = widget.selected
        ? context.shellTheme.accentPalette.onContainer
        : control == null
        ? context.shellColors.panelText
        : context.shellColors.textSecondary;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.spec.semanticLabel(
        shiftEnabled: widget.shiftEnabled,
        chineseInputEnabled: widget.chineseInputEnabled,
        l10n: context.l10n,
      ),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _handlePointerDown(),
        onPointerUp: (_) => _handlePointerEnd(),
        onPointerCancel: (_) => _handlePointerEnd(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !_enabled || widget.holdEnabled ? null : widget.onPressed,
          onLongPress: !_enabled || widget.holdEnabled
              ? null
              : widget.onLongPress,
          child: AnimatedBuilder(
            animation: _glow,
            builder: (context, child) {
              final glow = _glow.value;
              final foreground = Color.lerp(
                baseForeground,
                context.shellColors.panelText,
                glow * 0.55,
              )!;
              final border = Color.lerp(baseBorder, accent, glow)!;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.lerp(
                    background,
                    widget.selected
                        ? context.shellTheme.accentPalette.container
                        : context.shellColors.surfaceContainerHighest,
                    glow * 0.72,
                  ),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: border, width: 1),
                ),
                child: Center(
                  child: widget.spec.icon == null
                      ? _OskKeyLabel(
                          label: widget.spec.labelText(
                            shiftEnabled: widget.shiftEnabled,
                            ctrlArmed: widget.ctrlArmed,
                            chineseInputEnabled: widget.chineseInputEnabled,
                            l10n: context.l10n,
                          ),
                          color: foreground,
                          isWide: widget.spec.flex >= 28,
                        )
                      : Icon(widget.spec.icon, color: foreground, size: 22),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _handlePointerDown() {
    if (!_enabled) return;
    _startGlow();
    if (!widget.holdEnabled || _holdActive) {
      return;
    }
    _holdActive = true;
    widget.onHoldStarted();
  }

  void _handlePointerEnd() {
    _finishHold();
    _releaseGlow();
  }

  void _finishHold() {
    if (!_holdActive) {
      return;
    }
    _holdActive = false;
    widget.onHoldEnded();
  }

  void _startGlow() {
    _pressed = true;
    _lastPressStartedAt = DateTime.now();
    _glow.stop();
    _glow.value = 1;
  }

  void _releaseGlow() {
    _pressed = false;
    final startedAt = _lastPressStartedAt;
    if (startedAt == null) {
      _fadeOut();
      return;
    }

    final elapsed = DateTime.now().difference(startedAt);
    final remaining = _minimumVisibleDuration - elapsed;
    if (remaining <= Duration.zero) {
      _fadeOut();
      return;
    }

    Future<void>.delayed(remaining, () {
      if (!mounted || _pressed || _lastPressStartedAt != startedAt) {
        return;
      }
      _fadeOut();
    });
  }

  void _fadeOut() {
    _glow.animateTo(0, duration: _fadeOutDuration, curve: Curves.linear);
  }

  Color _backgroundFor(_OskKeySpec spec, bool selected) {
    final control = spec.control;
    if (selected) {
      return context.shellTheme.accentPalette.container;
    }
    if (control == _OskControl.space) {
      return context.shellColors.surfaceContainerHighest;
    }
    if (control != null) {
      return context.shellColors.surfaceContainer;
    }
    return context.shellColors.surfaceContainerHigh;
  }
}

class _OskKeyLabel extends StatelessWidget {
  const _OskKeyLabel({
    required this.label,
    required this.color,
    required this.isWide,
  });

  final String label;
  final Color color;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final style = ShellText.cardTitle.copyWith(
      color: color,
      fontSize: isWide ? 17 : 21,
      fontWeight: isWide ? FontWeight.w600 : FontWeight.w500,
      height: 1,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, softWrap: false, style: style),
      ),
    );
  }
}

enum _OskLayer { letters, numbers, symbols }

enum _OskPane { keyboard, emoji, clipboard, layouts }

enum _OskLayoutMode { standard, split, traditional }

enum _OskControl {
  shift,
  symbols,
  extraSymbols,
  letters,
  inputMethod,
  ctrl,
  escape,
  tab,
  delete,
  space,
  backspace,
  enter,
  arrowLeft,
  arrowRight,
  arrowUp,
  arrowDown,
}

class _OskRowData {
  const _OskRowData(this.keys, {this.sideInset = 0, this.splitAfter});

  final List<_OskKeySpec> keys;
  final double sideInset;
  final int? splitAfter;
}

class _OskKeySpec {
  const _OskKeySpec.text(this.value, {this.flex = 10})
    : control = null,
      icon = null;

  const _OskKeySpec.control(this.control, {this.icon, this.flex = 14})
    : value = null;

  final String? value;
  final _OskControl? control;
  final IconData? icon;
  final int flex;

  bool get isLetter {
    final text = value;
    if (text == null || text.length != 1) {
      return false;
    }
    final code = text.codeUnitAt(0);
    return code >= 97 && code <= 122;
  }

  String outputText({required bool shiftEnabled}) {
    final text = value ?? '';
    return shiftEnabled && isLetter ? text.toUpperCase() : text;
  }

  String labelText({
    required bool shiftEnabled,
    required bool ctrlArmed,
    required bool chineseInputEnabled,
    required AppLocalizations l10n,
  }) {
    if (control == _OskControl.symbols && ctrlArmed) {
      return l10n.oskControlKey;
    }
    if (control == _OskControl.symbols) {
      return l10n.oskNumbersAndSymbolsKey;
    }
    if (control == _OskControl.extraSymbols) {
      return l10n.oskMoreSymbolsKey;
    }
    if (control == _OskControl.letters) {
      return l10n.oskLettersKey;
    }
    if (control == _OskControl.inputMethod) {
      return chineseInputEnabled ? '中' : 'ENG';
    }
    if (control == _OskControl.ctrl) return 'Ctrl';
    if (control == _OskControl.escape) return 'Esc';
    if (control == _OskControl.tab) return 'Tab';
    if (control == _OskControl.delete) return 'Del';
    return outputText(shiftEnabled: shiftEnabled);
  }

  String semanticLabel({
    required bool shiftEnabled,
    required bool chineseInputEnabled,
    required AppLocalizations l10n,
  }) {
    return switch (control) {
      _OskControl.shift => l10n.oskShift,
      _OskControl.symbols => l10n.oskNumbersAndSymbols,
      _OskControl.extraSymbols => l10n.oskMoreSymbols,
      _OskControl.letters => l10n.oskLetters,
      _OskControl.inputMethod => chineseInputEnabled ? '中文拼音输入' : '英文输入',
      _OskControl.ctrl => 'Control',
      _OskControl.escape => 'Escape',
      _OskControl.tab => 'Tab',
      _OskControl.delete => 'Delete',
      _OskControl.space => l10n.oskSpace,
      _OskControl.backspace => l10n.oskBackspace,
      _OskControl.enter => l10n.oskEnter,
      _OskControl.arrowLeft => 'Left arrow',
      _OskControl.arrowRight => 'Right arrow',
      _OskControl.arrowUp => l10n.oskArrowUp,
      _OskControl.arrowDown => l10n.oskArrowDown,
      null => labelText(
        shiftEnabled: shiftEnabled,
        ctrlArmed: false,
        chineseInputEnabled: chineseInputEnabled,
        l10n: l10n,
      ),
    };
  }

  String? namedKey({required bool shiftEnabled}) {
    final control = this.control;
    if (control != null) {
      return switch (control) {
        _OskControl.ctrl => 'Control_L',
        _OskControl.escape => 'Escape',
        _OskControl.tab => 'Tab',
        _OskControl.delete => 'Delete',
        _OskControl.space => 'space',
        _OskControl.backspace => 'BackSpace',
        _OskControl.enter => 'Return',
        _OskControl.arrowLeft => 'Left',
        _OskControl.arrowRight => 'Right',
        _OskControl.arrowUp => 'Up',
        _OskControl.arrowDown => 'Down',
        _ => null,
      };
    }

    final text = value;
    if (text == null || text.isEmpty) {
      return null;
    }
    if (isLetter) {
      return text.toLowerCase();
    }
    return switch (text) {
      ',' => 'comma',
      '.' => 'period',
      '/' => 'slash',
      r'\' => 'backslash',
      '-' => 'minus',
      '=' => 'equal',
      "'" => 'apostrophe',
      ';' => 'semicolon',
      ':' => 'colon',
      '[' => 'bracketleft',
      ']' => 'bracketright',
      _ => shiftEnabled ? outputText(shiftEnabled: true) : text,
    };
  }

  String get animationKey {
    final control = this.control;
    if (control == null) {
      return 'text:$value:$flex';
    }
    return 'control:${control.name}:${icon?.codePoint ?? 0}:$flex';
  }

  bool isSelected({
    required bool shiftEnabled,
    required bool ctrlArmed,
    required bool chineseInputEnabled,
  }) {
    return (control == _OskControl.shift && shiftEnabled) ||
        (control == _OskControl.symbols && ctrlArmed) ||
        (control == _OskControl.ctrl && ctrlArmed) ||
        (control == _OskControl.inputMethod && chineseInputEnabled);
  }
}

const _commonEmoji = <String>[
  '😀',
  '😃',
  '😄',
  '😁',
  '😆',
  '😅',
  '😂',
  '🤣',
  '😊',
  '🙂',
  '🙃',
  '😉',
  '😍',
  '🥰',
  '😘',
  '😋',
  '😎',
  '🤓',
  '🥳',
  '🤩',
  '😏',
  '😴',
  '😭',
  '😤',
  '😡',
  '🤯',
  '🥶',
  '🥵',
  '😱',
  '🤔',
  '🫡',
  '🤗',
  '🤭',
  '🫢',
  '🙄',
  '😬',
  '👍',
  '👎',
  '👌',
  '✌️',
  '🤞',
  '🤟',
  '🤙',
  '👏',
  '🙌',
  '🫶',
  '🙏',
  '💪',
  '❤️',
  '🧡',
  '💛',
  '💚',
  '💙',
  '💜',
  '🖤',
  '🤍',
  '💯',
  '✨',
  '🔥',
  '🎉',
  '✅',
  '❌',
  '⭐',
  '🌟',
  '⚡',
  '☀️',
  '🌙',
  '☁️',
  '🌈',
  '🍎',
  '🍔',
  '☕',
  '⚽',
  '🏀',
  '🎮',
  '🎧',
  '📱',
  '💻',
  '⌨️',
  '🖱️',
  '🚀',
  '🚗',
  '✈️',
  '🏠',
];

const _letterRows = [
  _OskRowData([
    _OskKeySpec.text('q'),
    _OskKeySpec.text('w'),
    _OskKeySpec.text('e'),
    _OskKeySpec.text('r'),
    _OskKeySpec.text('t'),
    _OskKeySpec.text('y'),
    _OskKeySpec.text('u'),
    _OskKeySpec.text('i'),
    _OskKeySpec.text('o'),
    _OskKeySpec.text('p'),
  ], splitAfter: 5),
  _OskRowData(
    [
      _OskKeySpec.text('a'),
      _OskKeySpec.text('s'),
      _OskKeySpec.text('d'),
      _OskKeySpec.text('f'),
      _OskKeySpec.text('g'),
      _OskKeySpec.text('h'),
      _OskKeySpec.text('j'),
      _OskKeySpec.text('k'),
      _OskKeySpec.text('l'),
    ],
    sideInset: 18,
    splitAfter: 5,
  ),
  _OskRowData([
    _OskKeySpec.control(
      _OskControl.shift,
      icon: Icons.keyboard_arrow_up_rounded,
      flex: 15,
    ),
    _OskKeySpec.text('z'),
    _OskKeySpec.text('x'),
    _OskKeySpec.text('c'),
    _OskKeySpec.text('v'),
    _OskKeySpec.text('b'),
    _OskKeySpec.text('n'),
    _OskKeySpec.text('m'),
    _OskKeySpec.control(
      _OskControl.backspace,
      icon: Icons.backspace_rounded,
      flex: 15,
    ),
  ], splitAfter: 5),
  _OskRowData([
    _OskKeySpec.control(_OskControl.symbols, flex: 15),
    _OskKeySpec.control(_OskControl.inputMethod, flex: 15),
    _OskKeySpec.text(',', flex: 9),
    _OskKeySpec.control(
      _OskControl.space,
      icon: Icons.space_bar_rounded,
      flex: 34,
    ),
    _OskKeySpec.text('.', flex: 10),
    _OskKeySpec.control(
      _OskControl.enter,
      icon: Icons.keyboard_return_rounded,
      flex: 17,
    ),
  ]),
];

const _traditionalRows = [
  _OskRowData([
    _OskKeySpec.control(_OskControl.escape, flex: 12),
    _OskKeySpec.text('1'),
    _OskKeySpec.text('2'),
    _OskKeySpec.text('3'),
    _OskKeySpec.text('4'),
    _OskKeySpec.text('5'),
    _OskKeySpec.text('6'),
    _OskKeySpec.text('7'),
    _OskKeySpec.text('8'),
    _OskKeySpec.text('9'),
    _OskKeySpec.text('0'),
    _OskKeySpec.control(
      _OskControl.backspace,
      icon: Icons.backspace_rounded,
      flex: 16,
    ),
  ]),
  _OskRowData([
    _OskKeySpec.control(_OskControl.tab, flex: 14),
    _OskKeySpec.text('q'),
    _OskKeySpec.text('w'),
    _OskKeySpec.text('e'),
    _OskKeySpec.text('r'),
    _OskKeySpec.text('t'),
    _OskKeySpec.text('y'),
    _OskKeySpec.text('u'),
    _OskKeySpec.text('i'),
    _OskKeySpec.text('o'),
    _OskKeySpec.text('p'),
    _OskKeySpec.text('['),
    _OskKeySpec.text(']'),
  ]),
  _OskRowData([
    _OskKeySpec.control(_OskControl.ctrl, flex: 14),
    _OskKeySpec.text('a'),
    _OskKeySpec.text('s'),
    _OskKeySpec.text('d'),
    _OskKeySpec.text('f'),
    _OskKeySpec.text('g'),
    _OskKeySpec.text('h'),
    _OskKeySpec.text('j'),
    _OskKeySpec.text('k'),
    _OskKeySpec.text('l'),
    _OskKeySpec.text(';'),
    _OskKeySpec.text("'"),
    _OskKeySpec.control(
      _OskControl.enter,
      icon: Icons.keyboard_return_rounded,
      flex: 17,
    ),
  ]),
  _OskRowData([
    _OskKeySpec.control(
      _OskControl.shift,
      icon: Icons.keyboard_arrow_up_rounded,
      flex: 17,
    ),
    _OskKeySpec.text('z'),
    _OskKeySpec.text('x'),
    _OskKeySpec.text('c'),
    _OskKeySpec.text('v'),
    _OskKeySpec.text('b'),
    _OskKeySpec.text('n'),
    _OskKeySpec.text('m'),
    _OskKeySpec.text(','),
    _OskKeySpec.text('.'),
    _OskKeySpec.text('/'),
    _OskKeySpec.control(_OskControl.delete, flex: 14),
  ]),
  _OskRowData([
    _OskKeySpec.control(_OskControl.symbols, flex: 15),
    _OskKeySpec.control(_OskControl.inputMethod, flex: 15),
    _OskKeySpec.control(
      _OskControl.arrowLeft,
      icon: Icons.keyboard_arrow_left_rounded,
      flex: 10,
    ),
    _OskKeySpec.control(
      _OskControl.space,
      icon: Icons.space_bar_rounded,
      flex: 38,
    ),
    _OskKeySpec.control(
      _OskControl.arrowRight,
      icon: Icons.keyboard_arrow_right_rounded,
      flex: 10,
    ),
    _OskKeySpec.control(
      _OskControl.arrowUp,
      icon: Icons.keyboard_arrow_up_rounded,
      flex: 10,
    ),
    _OskKeySpec.control(
      _OskControl.arrowDown,
      icon: Icons.keyboard_arrow_down_rounded,
      flex: 10,
    ),
  ]),
];

const _numberRows = [
  _OskRowData([
    _OskKeySpec.text('1'),
    _OskKeySpec.text('2'),
    _OskKeySpec.text('3'),
    _OskKeySpec.text('4'),
    _OskKeySpec.text('5'),
    _OskKeySpec.text('6'),
    _OskKeySpec.text('7'),
    _OskKeySpec.text('8'),
    _OskKeySpec.text('9'),
    _OskKeySpec.text('0'),
  ]),
  _OskRowData([
    _OskKeySpec.text('@'),
    _OskKeySpec.text('#'),
    _OskKeySpec.text(r'$'),
    _OskKeySpec.text('_'),
    _OskKeySpec.text('&'),
    _OskKeySpec.text('-'),
    _OskKeySpec.text('+'),
    _OskKeySpec.text('('),
    _OskKeySpec.text(')'),
  ], sideInset: 18),
  _OskRowData([
    _OskKeySpec.control(_OskControl.extraSymbols, flex: 15),
    _OskKeySpec.text('*'),
    _OskKeySpec.text('"'),
    _OskKeySpec.text("'"),
    _OskKeySpec.text(':'),
    _OskKeySpec.text(';'),
    _OskKeySpec.text('/'),
    _OskKeySpec.text(r'\'),
    _OskKeySpec.text('!'),
    _OskKeySpec.text('?'),
    _OskKeySpec.control(
      _OskControl.backspace,
      icon: Icons.backspace_rounded,
      flex: 15,
    ),
  ]),
  _OskRowData([
    _OskKeySpec.control(_OskControl.letters, flex: 17),
    _OskKeySpec.control(
      _OskControl.arrowUp,
      icon: Icons.keyboard_arrow_up_rounded,
      flex: 10,
    ),
    _OskKeySpec.control(
      _OskControl.space,
      icon: Icons.space_bar_rounded,
      flex: 46,
    ),
    _OskKeySpec.control(
      _OskControl.arrowDown,
      icon: Icons.keyboard_arrow_down_rounded,
      flex: 10,
    ),
    _OskKeySpec.control(
      _OskControl.enter,
      icon: Icons.keyboard_return_rounded,
      flex: 17,
    ),
  ]),
];

const _extraSymbolRows = [
  _OskRowData([
    _OskKeySpec.text('~'),
    _OskKeySpec.text('`'),
    _OskKeySpec.text('|'),
    _OskKeySpec.text('^'),
    _OskKeySpec.text('%'),
  ], sideInset: 86),
  _OskRowData([
    _OskKeySpec.text('='),
    _OskKeySpec.text('<'),
    _OskKeySpec.text('>'),
    _OskKeySpec.text('['),
    _OskKeySpec.text(']'),
  ], sideInset: 86),
  _OskRowData([
    _OskKeySpec.control(_OskControl.symbols, flex: 17),
    _OskKeySpec.text('{'),
    _OskKeySpec.text('}'),
    _OskKeySpec.control(
      _OskControl.backspace,
      icon: Icons.backspace_rounded,
      flex: 17,
    ),
  ]),
  _OskRowData([
    _OskKeySpec.control(_OskControl.letters, flex: 17),
    _OskKeySpec.text(',', flex: 10),
    _OskKeySpec.control(
      _OskControl.space,
      icon: Icons.space_bar_rounded,
      flex: 46,
    ),
    _OskKeySpec.text('.', flex: 10),
    _OskKeySpec.control(
      _OskControl.enter,
      icon: Icons.keyboard_return_rounded,
      flex: 17,
    ),
  ]),
];
