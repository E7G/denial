import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/input_layout.dart';
import '../state/shell_controller.dart';

class ThreeButtonNavigation extends ConsumerWidget {
  const ThreeButtonNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      shellControllerProvider.select(
        (state) => (
          overviewVisible: state.overviewVisible,
          foregroundWindow: state.foregroundWindow,
          launchRequest: state.launchRequest,
        ),
      ),
    );
    final controller = ref.read(shellControllerProvider.notifier);

    void goHome() {
      if (state.overviewVisible) {
        controller.closeOverview();
        return;
      }
      if (state.foregroundWindow != null || state.launchRequest != null) {
        controller.goHome();
      }
    }

    void toggleOverview() {
      if (state.overviewVisible) {
        controller.closeOverview();
      } else {
        controller.openOverview();
      }
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: ShellMetrics.gestureBottomInset,
      child: Center(
        child: SizedBox(
          width: ShellMetrics.gestureHitWidth,
          height: ShellMetrics.gestureHitHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x990A0D11),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _NavigationButton(
                    semanticLabel: 'Back',
                    icon: Icons.arrow_back_rounded,
                    onTap: controller.navigateBack,
                  ),
                ),
                Expanded(
                  child: _NavigationButton(
                    semanticLabel: 'Home',
                    icon: Icons.circle_outlined,
                    onTap: goHome,
                  ),
                ),
                Expanded(
                  child: _NavigationButton(
                    semanticLabel: state.overviewVisible
                        ? 'Close overview'
                        : 'Overview',
                    icon: Icons.crop_square_rounded,
                    active: state.overviewVisible,
                    onTap: toggleOverview,
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

class _NavigationButton extends StatefulWidget {
  const _NavigationButton({
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_NavigationButton> createState() => _NavigationButtonState();
}

class _NavigationButtonState extends State<_NavigationButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 90),
          scale: _pressed ? 0.84 : 1,
          child: Icon(
            widget.icon,
            size: widget.active ? 26 : 24,
            color: widget.active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.86),
          ),
        ),
      ),
    );
  }
}
