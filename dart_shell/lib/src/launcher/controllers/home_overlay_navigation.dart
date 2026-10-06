import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeOverlayNavigationProvider =
    NotifierProvider<
      HomeOverlayNavigationController,
      HomeOverlayNavigationState
    >(HomeOverlayNavigationController.new);

@immutable
class HomeOverlayNavigationState {
  const HomeOverlayNavigationState({
    this.modalOpen = false,
    this.backRequestSerial = 0,
  });

  final bool modalOpen;
  final int backRequestSerial;

  HomeOverlayNavigationState copyWith({
    bool? modalOpen,
    int? backRequestSerial,
  }) {
    return HomeOverlayNavigationState(
      modalOpen: modalOpen ?? this.modalOpen,
      backRequestSerial: backRequestSerial ?? this.backRequestSerial,
    );
  }
}

class HomeOverlayNavigationController
    extends Notifier<HomeOverlayNavigationState> {
  @override
  HomeOverlayNavigationState build() => const HomeOverlayNavigationState();

  void setModalOpen(bool value) {
    if (state.modalOpen == value) {
      return;
    }
    state = state.copyWith(modalOpen: value);
  }

  void requestBack() {
    state = state.copyWith(backRequestSerial: state.backRequestSerial + 1);
  }
}
