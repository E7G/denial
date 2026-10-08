import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Monotonic request signal used by non-shade UI to force the next shade
/// presentation onto the Quick Settings page.
final quickSettingsPageRequestProvider =
    NotifierProvider<QuickSettingsPageRequestController, int>(
      QuickSettingsPageRequestController.new,
    );

class QuickSettingsPageRequestController extends Notifier<int> {
  @override
  int build() => 0;

  void request() {
    state = state >= 0x7ffffffe ? 1 : state + 1;
  }
}
