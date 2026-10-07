import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _kimpanelBusName = 'org.kde.impanel';
const String _kimpanelPath = '/org/kde/impanel';
const String _kimpanelInterface = 'org.kde.impanel';
const String _kimpanel2Interface = 'org.kde.impanel2';
const String _fcitxKimpanelInterface = 'org.kde.kimpanel.inputmethod';

final fcitxKimpanelServiceProvider = Provider<FcitxKimpanelService>((ref) {
  final service = FcitxKimpanelService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

@immutable
class FcitxCandidateItem {
  const FcitxCandidateItem({
    required this.index,
    required this.label,
    required this.text,
  });

  final int index;
  final String label;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is FcitxCandidateItem &&
      other.index == index &&
      other.label == label &&
      other.text == text;

  @override
  int get hashCode => Object.hash(index, label, text);
}

@immutable
class FcitxCandidateSnapshot {
  const FcitxCandidateSnapshot({
    required this.available,
    required this.visible,
    required this.items,
    required this.cursor,
    required this.hasPrevious,
    required this.hasNext,
    required this.layoutHint,
  });

  const FcitxCandidateSnapshot.unavailable()
    : available = false,
      visible = false,
      items = const <FcitxCandidateItem>[],
      cursor = -1,
      hasPrevious = false,
      hasNext = false,
      layoutHint = 0;

  final bool available;
  final bool visible;
  final List<FcitxCandidateItem> items;
  final int cursor;
  final bool hasPrevious;
  final bool hasNext;
  final int layoutHint;

  FcitxCandidateSnapshot copyWith({
    bool? available,
    bool? visible,
    List<FcitxCandidateItem>? items,
    int? cursor,
    bool? hasPrevious,
    bool? hasNext,
    int? layoutHint,
  }) {
    return FcitxCandidateSnapshot(
      available: available ?? this.available,
      visible: visible ?? this.visible,
      items: items ?? this.items,
      cursor: cursor ?? this.cursor,
      hasPrevious: hasPrevious ?? this.hasPrevious,
      hasNext: hasNext ?? this.hasNext,
      layoutHint: layoutHint ?? this.layoutHint,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! FcitxCandidateSnapshot ||
        other.available != available ||
        other.visible != visible ||
        other.cursor != cursor ||
        other.hasPrevious != hasPrevious ||
        other.hasNext != hasNext ||
        other.layoutHint != layoutHint ||
        other.items.length != items.length) {
      return false;
    }
    for (var index = 0; index < items.length; index++) {
      if (items[index] != other.items[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    available,
    visible,
    cursor,
    hasPrevious,
    hasNext,
    layoutHint,
    Object.hashAll(items),
  );
}

/// Implements the small KDE Kimpanel panel protocol that Fcitx5 already
/// exposes. Denial consumes structured lookup-table data and paints it as part
/// of the touch keyboard instead of sampling Fcitx's popup surface.
class FcitxKimpanelService {
  FcitxKimpanelService({DBusClient? client})
    : _client = client ?? DBusClient.session(),
      _ownsClient = client == null,
      _endpoint = _FcitxKimpanelEndpoint();

  static const int _maxCandidates = 32;
  static const int _maxCandidateChars = 160;

  final DBusClient _client;
  final bool _ownsClient;
  final _FcitxKimpanelEndpoint _endpoint;
  final StreamController<FcitxCandidateSnapshot> _snapshots =
      StreamController<FcitxCandidateSnapshot>.broadcast(sync: true);
  final ValueNotifier<FcitxCandidateSnapshot> _candidateListenable =
      ValueNotifier<FcitxCandidateSnapshot>(
        const FcitxCandidateSnapshot.unavailable(),
      );

  StreamSubscription<DBusSignal>? _fcitxSignals;
  StreamSubscription<DBusNameOwnerChangedEvent>? _ownerChanges;
  FcitxCandidateSnapshot _current = const FcitxCandidateSnapshot.unavailable();
  bool _started = false;
  bool _disposed = false;
  bool _ownsPanelName = false;

  Stream<FcitxCandidateSnapshot> get snapshots => _snapshots.stream;
  ValueListenable<FcitxCandidateSnapshot> get candidateListenable =>
      _candidateListenable;
  FcitxCandidateSnapshot get current => _current;

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _endpoint.onLookupTable = _acceptLookupTable;

    try {
      await _client.registerObject(_endpoint);
      final reply = await _client.requestName(
        _kimpanelBusName,
        flags: const <DBusRequestNameFlag>{DBusRequestNameFlag.doNotQueue},
      );
      _ownsPanelName =
          reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner;
      if (!_ownsPanelName) {
        _publish(const FcitxCandidateSnapshot.unavailable());
        return;
      }

      _fcitxSignals = DBusSignalStream(
        _client,
        interface: _fcitxKimpanelInterface,
      ).listen(_handleFcitxSignal, onError: (_) => _resetTable());
      _ownerChanges = _client.nameOwnerChanged
          .where((event) => event.name == _fcitxKimpanelInterface)
          .listen((event) {
            if (event.newOwner == null) {
              _resetTable();
              return;
            }
            if (_ownsPanelName) {
              // Fcitx may start the Kimpanel addon only after our bus name
              // becomes available. Repeat the standard panel handshake when
              // that addon acquires its input-method service name so no
              // startup race can leave the lookup table stale.
              unawaited(_endpoint.emitPanelCreated());
              unawaited(_endpoint.emitPanelCreated2());
            }
          });

      _publish(_current.copyWith(available: true));
      await _endpoint.emitPanelCreated();
      await _endpoint.emitPanelCreated2();
    } on Object {
      _ownsPanelName = false;
      _publish(const FcitxCandidateSnapshot.unavailable());
      rethrow;
    }
  }

  void _acceptLookupTable(
    List<String> labels,
    List<String> texts,
    bool hasPrevious,
    bool hasNext,
    int cursor,
    int layoutHint,
  ) {
    final count = texts.length.clamp(0, _maxCandidates).toInt();
    final items = <FcitxCandidateItem>[
      for (var index = 0; index < count; index++)
        FcitxCandidateItem(
          index: index,
          label: _bounded(index < labels.length ? labels[index] : ''),
          text: _bounded(texts[index]),
        ),
    ];
    final safeCursor = cursor >= 0 && cursor < items.length ? cursor : -1;
    _publish(
      FcitxCandidateSnapshot(
        available: _ownsPanelName,
        // SetLookupTable is sent immediately before ShowLookupTable. Showing
        // the fresh data here avoids a one-frame flash without keeping stale
        // candidates alive after an explicit ShowLookupTable(false).
        visible: items.isNotEmpty,
        items: List<FcitxCandidateItem>.unmodifiable(items),
        cursor: safeCursor,
        hasPrevious: hasPrevious,
        hasNext: hasNext,
        layoutHint: layoutHint,
      ),
    );
  }

  String _bounded(String value) {
    final normalized = value.replaceAll('\u0000', '').trim();
    return normalized.length <= _maxCandidateChars
        ? normalized
        : normalized.substring(0, _maxCandidateChars);
  }

  void _handleFcitxSignal(DBusSignal signal) {
    if (signal.interface != _fcitxKimpanelInterface) {
      return;
    }
    switch (signal.name) {
      case 'ShowLookupTable':
        if (signal.signature == DBusSignature('b') &&
            signal.values.isNotEmpty) {
          final value = signal.values.first;
          if (value is DBusBoolean) {
            _publish(
              _current.copyWith(
                available: _ownsPanelName,
                visible: value.value && _current.items.isNotEmpty,
              ),
            );
          }
        }
      case 'Enable':
        if (signal.signature == DBusSignature('b') &&
            signal.values.isNotEmpty) {
          final value = signal.values.first;
          if (value is DBusBoolean && !value.value) {
            _publish(
              _current.copyWith(available: _ownsPanelName, visible: false),
            );
          }
        }
    }
  }

  Future<void> selectCandidate(int index) async {
    if (!_ownsPanelName || index < 0 || index >= _current.items.length) {
      return;
    }
    await _endpoint.emitSelectCandidate(index);
  }

  Future<void> previousPage() async {
    if (_ownsPanelName && _current.hasPrevious) {
      await _endpoint.emitPageUp();
    }
  }

  Future<void> nextPage() async {
    if (_ownsPanelName && _current.hasNext) {
      await _endpoint.emitPageDown();
    }
  }

  void _resetTable() {
    _publish(
      FcitxCandidateSnapshot(
        available: _ownsPanelName,
        visible: false,
        items: const <FcitxCandidateItem>[],
        cursor: -1,
        hasPrevious: false,
        hasNext: false,
        layoutHint: 0,
      ),
    );
  }

  void _publish(FcitxCandidateSnapshot next) {
    if (_disposed || next == _current) {
      return;
    }
    _current = next;
    _candidateListenable.value = next;
    _snapshots.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _fcitxSignals?.cancel();
    await _ownerChanges?.cancel();
    _fcitxSignals = null;
    _ownerChanges = null;
    if (_started) {
      try {
        await _client.unregisterObject(_endpoint);
      } on Object {
        // The bus may already be gone during session teardown.
      }
    }
    if (_ownsClient) {
      await _client.close();
    }
    _candidateListenable.dispose();
    await _snapshots.close();
  }
}

class _FcitxKimpanelEndpoint extends DBusObject {
  _FcitxKimpanelEndpoint() : super(DBusObjectPath(_kimpanelPath));

  void Function(
    List<String> labels,
    List<String> texts,
    bool hasPrevious,
    bool hasNext,
    int cursor,
    int layoutHint,
  )?
  onLookupTable;

  Future<void> emitPanelCreated() =>
      emitSignal(_kimpanelInterface, 'PanelCreated');

  Future<void> emitPanelCreated2() =>
      emitSignal(_kimpanel2Interface, 'PanelCreated2');

  Future<void> emitSelectCandidate(int index) => emitSignal(
    _kimpanelInterface,
    'SelectCandidate',
    <DBusValue>[DBusInt32(index)],
  );

  Future<void> emitPageUp() =>
      emitSignal(_kimpanelInterface, 'LookupTablePageUp');

  Future<void> emitPageDown() =>
      emitSignal(_kimpanelInterface, 'LookupTablePageDown');

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
    DBusIntrospectInterface(
      _kimpanelInterface,
      signals: <DBusIntrospectSignal>[
        _signal('MovePreeditCaret', 'i'),
        _signal('SelectCandidate', 'i'),
        _signal('LookupTablePageUp'),
        _signal('LookupTablePageDown'),
        _signal('TriggerProperty', 's'),
        _signal('PanelCreated'),
        _signal('Exit'),
        _signal('ReloadConfig'),
        _signal('Configure'),
      ],
    ),
    DBusIntrospectInterface(
      _kimpanel2Interface,
      methods: <DBusIntrospectMethod>[
        _method('SetSpotRect', 'iiii'),
        _method('SetRelativeSpotRect', 'iiii'),
        _method('SetRelativeSpotRectV2', 'iiiid'),
        _method('SetLookupTable', 'asasasbbii'),
      ],
      signals: <DBusIntrospectSignal>[
        _signal('PanelCreated2'),
        _signal('PanelRegistered'),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != _kimpanel2Interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (call.name) {
      case 'SetSpotRect':
      case 'SetRelativeSpotRect':
        return call.signature == DBusSignature('iiii')
            ? DBusMethodSuccessResponse()
            : DBusMethodErrorResponse.invalidArgs();
      case 'SetRelativeSpotRectV2':
        return call.signature == DBusSignature('iiiid')
            ? DBusMethodSuccessResponse()
            : DBusMethodErrorResponse.invalidArgs();
      case 'SetLookupTable':
        if (call.signature != DBusSignature('asasasbbii') ||
            call.values.length != 7) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        try {
          onLookupTable?.call(
            call.values[0].asStringArray().toList(growable: false),
            call.values[1].asStringArray().toList(growable: false),
            (call.values[3] as DBusBoolean).value,
            (call.values[4] as DBusBoolean).value,
            call.values[5].asInt32(),
            call.values[6].asInt32(),
          );
          return DBusMethodSuccessResponse();
        } on Object {
          return DBusMethodErrorResponse.invalidArgs();
        }
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

DBusIntrospectMethod _method(String name, String inputSignature) {
  final arguments = <DBusIntrospectArgument>[];
  for (final type in _splitDbusSignature(inputSignature)) {
    arguments.add(
      DBusIntrospectArgument(DBusSignature(type), DBusArgumentDirection.in_),
    );
  }
  return DBusIntrospectMethod(name, args: arguments);
}

DBusIntrospectSignal _signal(String name, [String signature = '']) {
  return DBusIntrospectSignal(
    name,
    args: <DBusIntrospectArgument>[
      for (final type in _splitDbusSignature(signature))
        DBusIntrospectArgument(DBusSignature(type), DBusArgumentDirection.out),
    ],
  );
}

List<String> _splitDbusSignature(String signature) {
  if (signature.isEmpty) {
    return const <String>[];
  }
  final types = <String>[];
  for (var index = 0; index < signature.length;) {
    if (signature.startsWith('as', index)) {
      types.add('as');
      index += 2;
    } else {
      types.add(signature[index]);
      index += 1;
    }
  }
  return types;
}
