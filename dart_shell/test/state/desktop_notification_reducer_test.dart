import 'dart:math';

import 'package:denial_dart_shell/src/models/desktop_notification.dart';
import 'package:denial_dart_shell/src/state/desktop_notification_reducer.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications_state.dart';
import 'package:test/test.dart';

import '../support/legacy_notification_reducer.dart';
import '../support/notification_event_fixtures.dart';

void main() {
  test(
    'unknown closes preserve all collections and still record the event',
    () {
      final reducer = DesktopNotificationReducer();
      final initial = reducer
          .apply(const DesktopNotificationsState(), notificationEvent(1))
          .state;
      final event = closeNotification(99);
      final next = reducer.apply(initial, event).state;
      expect(next.active, same(initial.active));
      expect(next.history, same(initial.history));
      expect(next.bannerQueue, same(initial.bannerQueue));
      expect(next.pendingDismissals, same(initial.pendingDismissals));
      expect(next.lastEvent, same(event));
    },
  );

  test('progress replacements share unchanged banners and dismissals', () {
    final reducer = DesktopNotificationReducer();
    final initial = reducer
        .apply(
          const DesktopNotificationsState(),
          notificationEvent(1, resident: true),
        )
        .state;
    final next = reducer
        .apply(
          initial,
          notificationEvent(
            1,
            resident: true,
            progress: 50,
            kind: DesktopNotificationEventKind.replaced,
          ),
        )
        .state;
    expect(next.active[1]!.progress, 50);
    expect(next.history.single.notification.progress, 50);
    expect(next.bannerQueue, same(initial.bannerQueue));
    expect(next.pendingDismissals, same(initial.pendingDismissals));
    expect(next.history.single.sequence, initial.history.single.sequence);
    expect(initial.active[1]!.progress, 0);
    expect(initial.history.single.notification.progress, 0);
  });

  test(
    'a banner already first retains its queue and an older one moves first',
    () {
      final reducer = DesktopNotificationReducer();
      var state = reducer
          .apply(const DesktopNotificationsState(), notificationEvent(1))
          .state;
      state = reducer.apply(state, notificationEvent(2)).state;
      final unchanged = reducer.apply(state, notificationEvent(2)).state;
      expect(unchanged.bannerQueue, same(state.bannerQueue));
      final reordered = reducer.apply(unchanged, notificationEvent(1)).state;
      expect(reordered.bannerQueue, [1, 2]);
      expect(state.bannerQueue, [2, 1]);
    },
  );

  test('closing preserves history and clears pending dismissal', () {
    final reducer = DesktopNotificationReducer();
    final initial = reducer
        .apply(const DesktopNotificationsState(), notificationEvent(1))
        .state
        .copyWith(pendingDismissals: const {1});
    final closed = reducer
        .apply(initial, closeNotification(1, reason: 3))
        .state;
    expect(closed.active, isEmpty);
    expect(closed.bannerQueue, isEmpty);
    expect(closed.pendingDismissals, isEmpty);
    expect(closed.history.single.active, isFalse);
    expect(closed.history.single.unread, isTrue);
    expect(closed.history.single.closeReason, 3);
    expect(
      reducer.apply(closed, closeNotification(1, reason: 3)).state.history,
      same(closed.history),
    );
    expect(initial.pendingDismissals, {1});
  });

  test('transient replacements remove history unless the notification is persistent', () {
    final reducer = DesktopNotificationReducer();
    final initial = reducer
        .apply(const DesktopNotificationsState(), notificationEvent(1))
        .state;
    final transient = reducer
        .apply(initial, notificationEvent(1, transient: true))
        .state;
    expect(transient.history, isEmpty);
    expect(transient.bannerQueue, [1]);
    final resident = reducer
        .apply(transient, notificationEvent(1, transient: true, resident: true))
        .state;
    expect(resident.history.single.notification.id, 1);
    expect(resident.bannerQueue, isEmpty);
  });

  test('do-not-disturb keeps only critical new banners', () {
    final reducer = DesktopNotificationReducer();
    var state = const DesktopNotificationsState(doNotDisturb: true);
    state = reducer.apply(state, notificationEvent(1)).state;
    expect(state.bannerQueue, isEmpty);
    state = reducer
        .apply(
          state,
          notificationEvent(2, urgency: DesktopNotificationUrgency.critical),
        )
        .state;
    expect(state.bannerQueue, [2]);
    expect(state.history, hasLength(2));
  });

  test('limits retain ordering and expose the action-cache eviction ID', () {
    final reducer = DesktopNotificationReducer();
    var state = const DesktopNotificationsState();
    for (var i = 0; i < 300; i++) {
      final result = reducer.apply(state, notificationEvent(i));
      expect(result.evictedId, i < 256 ? null : i - 256);
      state = result.state;
    }
    expect(state.active.keys, List.generate(256, (i) => i + 44));
    expect(
      state.history.map((record) => record.notification.id),
      List.generate(100, (i) => 299 - i),
    );
    expect(state.bannerQueue, List.generate(24, (i) => 299 - i));
    expect(state.history.first.sequence, 300);
  });

  test('published collections reject mutations', () {
    final reducer = DesktopNotificationReducer();
    final initial = reducer
        .apply(const DesktopNotificationsState(), notificationEvent(1))
        .state
        .copyWith(pendingDismissals: const {1, 2});
    final state = reducer.apply(initial, notificationEvent(1)).state;
    expect(() => state.active.clear(), throwsUnsupportedError);
    expect(() => state.history.clear(), throwsUnsupportedError);
    expect(() => state.bannerQueue.clear(), throwsUnsupportedError);
    expect(() => state.pendingDismissals.clear(), throwsUnsupportedError);
  });

  test('mixed events preserve the previous reducer behavior', () {
    final random = Random(534);
    final reducer = DesktopNotificationReducer();
    final legacy = LegacyNotificationReducer();
    var actual = const DesktopNotificationsState();
    var expected = const DesktopNotificationsState();
    for (var i = 0; i < 4000; i++) {
      final id = random.nextInt(400);
      if (i % 17 == 0) {
        final dnd = random.nextBool();
        final pending = Set<int>.unmodifiable([random.nextInt(400), id]);
        actual = actual.copyWith(doNotDisturb: dnd, pendingDismissals: pending);
        expected = expected.copyWith(
          doNotDisturb: dnd,
          pendingDismissals: pending,
        );
      }
      final event = random.nextInt(3) == 0
          ? closeNotification(id, reason: random.nextInt(4))
          : notificationEvent(
              id,
              resident: random.nextBool(),
              transient: random.nextBool(),
              timeout: random.nextBool() ? -1 : 0,
              progress: random.nextInt(101),
              kind: random.nextBool()
                  ? DesktopNotificationEventKind.added
                  : DesktopNotificationEventKind.replaced,
              urgency: DesktopNotificationUrgency.values[random.nextInt(3)],
            );
      final result = reducer.apply(actual, event);
      final reference = legacy.apply(expected, event);
      actual = result.state;
      expected = reference.state;
      expect(result.evictedId, reference.evictedId, reason: 'event $i');
      expect(actual.active, expected.active, reason: 'active $i');
      expect(actual.active.keys, expected.active.keys, reason: 'order $i');
      expect(actual.bannerQueue, expected.bannerQueue, reason: 'banners $i');
      expect(
        actual.pendingDismissals,
        expected.pendingDismissals,
        reason: 'pending $i',
      );
      expect(
        actual.history.map(_record),
        expected.history.map(_record),
        reason: 'history $i',
      );
      expect(actual.lastEvent, same(event));
      expect(actual.unreadCount, expected.unreadCount);
    }
  });
}

List<Object> _record(DesktopNotificationRecord record) => [
  record.notification,
  record.sequence,
  record.active,
  record.unread,
  record.closeReason,
];
