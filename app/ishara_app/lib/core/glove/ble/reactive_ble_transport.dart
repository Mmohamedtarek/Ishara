import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/glove_transport.dart';
import 'package:ishara_app/core/logging/log.dart';

/// The parts of `flutter_reactive_ble` the glove uses, so the transport can
/// be tested without a radio.
abstract interface class BleApi {
  /// Adapter state (powered, permissions, location services).
  Stream<BleStatus> get statusStream;
  BleStatus get status;

  /// Scans for devices advertising [services]. Location services are
  /// checked through [statusStream] (`locationServicesDisabled`).
  Stream<DiscoveredDevice> scan(List<Uuid> services);

  /// Connects; cancelling the subscription disconnects.
  Stream<ConnectionStateUpdate> connect(String id, {required Duration timeout});

  Future<int> requestMtu(String id, int mtu);

  /// Discovers services and returns the characteristic UUIDs of [service].
  Future<Set<Uuid>> characteristicsOf(String id, Uuid service);

  Future<List<int>> read(QualifiedCharacteristic c);

  /// Listening enables notifications; cancelling disables them.
  Stream<List<int>> subscribe(QualifiedCharacteristic c);

  Future<void> writeWithResponse(QualifiedCharacteristic c, List<int> value);
}

/// [BleApi] on the real `flutter_reactive_ble` plugin.
class FlutterReactiveBleApi implements BleApi {
  new([this._given]);

  final FlutterReactiveBle? _given;

  /// Created on first use: the plugin starts talking to the platform as
  /// soon as it exists, which the app shouldn't do until the real glove is
  /// actually used.
  late final FlutterReactiveBle _ble = _given ?? FlutterReactiveBle();

  @override
  Stream<BleStatus> get statusStream => _ble.statusStream;

  @override
  BleStatus get status => _ble.status;

  @override
  Stream<DiscoveredDevice> scan(List<Uuid> services) => _ble.scanForDevices(
    withServices: services,
    scanMode: ScanMode.lowLatency,
    // The adapter status already reports locationServicesDisabled where it
    // matters (Android 11 and older).
    requireLocationServicesEnabled: false,
  );

  @override
  Stream<ConnectionStateUpdate> connect(
    String id, {
    required Duration timeout,
  }) => _ble.connectToDevice(
    id: id,
    servicesWithCharacteristicsToDiscover: {
      Uuid.parse(IsharaUuids.service): [
        for (final c in [
          IsharaUuids.data,
          IsharaUuids.cmd,
          IsharaUuids.event,
          IsharaUuids.info,
        ])
          Uuid.parse(c),
      ],
    },
    connectionTimeout: timeout,
  );

  @override
  Future<int> requestMtu(String id, int mtu) =>
      _ble.requestMtu(deviceId: id, mtu: mtu);

  @override
  Future<Set<Uuid>> characteristicsOf(String id, Uuid service) async {
    await _ble.discoverAllServices(id);
    final services = await _ble.getDiscoveredServices(id);
    return {
      for (final s in services)
        if (s.id == service)
          for (final c in s.characteristics) c.id,
    };
  }

  @override
  Future<List<int>> read(QualifiedCharacteristic c) =>
      _ble.readCharacteristic(c);

  @override
  Stream<List<int>> subscribe(QualifiedCharacteristic c) =>
      _ble.subscribeToCharacteristic(c);

  @override
  Future<void> writeWithResponse(QualifiedCharacteristic c, List<int> value) =>
      _ble.writeCharacteristicWithResponse(c, value: value);
}

/// The real glove's radio (BLE-CONTRACT §1-3) on `flutter_reactive_ble`.
class ReactiveBleTransport implements GloveTransport {
  new(
    this._api, {
    this.connectTimeout = const Duration(seconds: 10),
    this.statusWait = const Duration(seconds: 30),
  });

  final BleApi _api;
  final Duration connectTimeout;

  /// How long to wait while the adapter state is unknown (iOS reports
  /// unknown while its Bluetooth permission alert is open, and while the
  /// adapter resets).
  final Duration statusWait;

  final _log = Log('ble');

  static final _service = Uuid.parse(IsharaUuids.service);
  static final Set<Uuid> _required = {
    for (final c in [
      IsharaUuids.data,
      IsharaUuids.cmd,
      IsharaUuids.event,
      IsharaUuids.info,
    ])
      Uuid.parse(c),
  };

  static BluetoothProblem? _problemOf(BleStatus s) => switch (s) {
    BleStatus.ready => null,
    BleStatus.poweredOff => BluetoothProblem.off,
    BleStatus.unauthorized => BluetoothProblem.unauthorized,
    BleStatus.locationServicesDisabled => BluetoothProblem.locationOff,
    BleStatus.unsupported => BluetoothProblem.unsupported,
    // Still not known after the wait: retryable, never "unsupported".
    BleStatus.unknown => BluetoothProblem.notReady,
  };

  /// Throws [BluetoothUnavailableFailure] unless the adapter is ready.
  Future<void> _ensureReady() async {
    var status = _api.status;
    if (status == BleStatus.unknown) {
      status = await _api.statusStream
          .firstWhere((s) => s != BleStatus.unknown)
          .timeout(statusWait, onTimeout: () => BleStatus.unknown);
    }
    final problem = _problemOf(status);
    if (problem != null) throw BluetoothUnavailableFailure(problem);
  }

  @override
  Stream<List<DiscoveredGlove>> scan({required Duration timeout}) async* {
    await _ensureReady();
    final found = <String, DiscoveredGlove>{};
    final out = StreamController<List<DiscoveredGlove>>();
    List<DiscoveredGlove> sorted() =>
        found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    final sub = _api
        .scan([_service])
        .listen(
          (d) {
            // Only real Ishara gloves (BLE §1: `Ishara-XXXX`).
            if (!IsharaUuids.namePattern.hasMatch(d.name)) return;
            found[d.id] = DiscoveredGlove(id: d.id, name: d.name, rssi: d.rssi);
            if (!out.isClosed) out.add(sorted());
          },
          onError: (Object e, StackTrace st) {
            // The scan is dead: say why (often Bluetooth or a permission
            // went away) and end the stream.
            final problem = _problemOf(_api.status);
            if (!out.isClosed) {
              out.addError(
                problem != null && problem != BluetoothProblem.notReady
                    ? BluetoothUnavailableFailure(problem)
                    : GloveScanFailure(cause: e, stackTrace: st),
              );
              unawaited(out.close());
            }
          },
          onDone: () {
            if (!out.isClosed) unawaited(out.close());
          },
        );
    final timer = Timer(timeout, () {
      if (!out.isClosed) unawaited(out.close());
    });
    try {
      yield const [];
      yield* out.stream;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  @override
  Future<GloveLink> open(DiscoveredGlove glove) async {
    await _ensureReady();
    final connected = Completer<void>();
    final closed = Completer<void>();
    // reactive_ble's connection updates are shared per device: a late
    // "disconnected" of an earlier session can arrive first. This attempt
    // starts when it reports "connecting".
    var started = false;
    late final StreamSubscription<ConnectionStateUpdate> conn;
    conn = _api
        .connect(glove.id, timeout: connectTimeout)
        .listen(
          (u) {
            switch (u.connectionState) {
              case DeviceConnectionState.connecting:
                started = true;
              case DeviceConnectionState.connected:
                started = true;
                if (!connected.isCompleted) connected.complete();
              case DeviceConnectionState.disconnected:
                if (!started) return; // stale: an earlier session
                if (!connected.isCompleted) {
                  connected.completeError(
                    GloveConnectFailure(
                      'disconnected while connecting',
                      cause: u.failure,
                    ),
                  );
                }
                if (!closed.isCompleted) closed.complete();
              case DeviceConnectionState.disconnecting:
                break;
            }
          },
          onError: (Object e, StackTrace st) {
            if (!connected.isCompleted) {
              connected.completeError(
                GloveConnectFailure('connect failed', cause: e, stackTrace: st),
              );
            }
            if (!closed.isCompleted) closed.complete();
          },
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
        );
    try {
      await connected.future.timeout(
        connectTimeout + const Duration(seconds: 2),
        onTimeout: () => throw const GloveConnectFailure('connect timeout'),
      );
      // BLE §3 step 2: MTU 247. Android negotiates it now (it starts at 23);
      // iOS has negotiated by itself and returns the value it got.
      final mtu = await _api.requestMtu(glove.id, IsharaUuids.requestedMtu);
      // Step 3: the Ishara service with its 4 characteristics.
      final chars = await _api.characteristicsOf(glove.id, _service);
      if (!chars.containsAll(_required)) {
        throw const GloveConnectFailure(
          'not an Ishara glove (service missing)',
        );
      }
      _log.info('linked', {'mtu': mtu});
      return _ReactiveLink(_api, glove.id, mtu, conn, closed, _log);
    } on Object {
      await _cancelQuietly(conn, _log);
      if (!closed.isCompleted) closed.complete();
      rethrow;
    }
  }
}

/// Cancels the connection subscription (= disconnects). A failing platform
/// disconnect is logged, not thrown: the link counts as closed either way.
Future<void> _cancelQuietly(
  StreamSubscription<ConnectionStateUpdate> conn,
  Log log,
) async {
  try {
    await conn.cancel();
  } on Object catch (e, st) {
    log.failure(
      'disconnect_failed',
      GloveConnectFailure(
        'platform disconnect failed',
        cause: e,
        stackTrace: st,
      ),
    );
  }
}

class _ReactiveLink implements GloveLink {
  new(this._api, this._id, this.mtu, this._conn, this._closed, this._log) {
    unawaited(_closed.future.then((_) => _shutDown()));
  }

  final BleApi _api;
  final String _id;
  final StreamSubscription<ConnectionStateUpdate> _conn;
  final Completer<void> _closed;
  final Log _log;
  final _events = StreamController<Uint8List>.broadcast(sync: true);
  final _data = StreamController<Uint8List>.broadcast(sync: true);
  final List<StreamSubscription<List<int>>> _notify = [];

  @override
  final int mtu;

  QualifiedCharacteristic _char(String uuid) => QualifiedCharacteristic(
    serviceId: Uuid.parse(IsharaUuids.service),
    characteristicId: Uuid.parse(uuid),
    deviceId: _id,
  );

  void _ensureOpen() {
    if (_closed.isCompleted) throw const GloveDisconnectedFailure();
  }

  @override
  Future<Uint8List> readInfo() async {
    _ensureOpen();
    return Uint8List.fromList(await _api.read(_char(IsharaUuids.info)));
  }

  @override
  Stream<Uint8List> get eventNotifications => _events.stream;

  @override
  Stream<Uint8List> get dataNotifications => _data.stream;

  void _forward(String uuid, StreamController<Uint8List> to) {
    _ensureOpen();
    _notify.add(
      _api
          .subscribe(_char(uuid))
          .listen(
            (v) {
              if (!to.isClosed) to.add(Uint8List.fromList(v));
            },
            onError: (Object e, StackTrace st) {
              // Notifications failed (e.g. GATT error): the link is unusable.
              // Disconnect for real, so the glove is free for another phone.
              _log.failure(
                'notification_failed',
                GloveConnectFailure(
                  'notifications failed',
                  cause: e,
                  stackTrace: st,
                ),
              );
              unawaited(close());
            },
          ),
    );
  }

  @override
  Future<void> subscribeEvents() async => _forward(IsharaUuids.event, _events);

  @override
  Future<void> subscribeData() async => _forward(IsharaUuids.data, _data);

  @override
  Future<void> writeCommand(Uint8List bytes) async {
    _ensureOpen();
    await _api.writeWithResponse(_char(IsharaUuids.cmd), bytes);
  }

  @override
  Future<void> get closed => _closed.future;

  Future<void> _shutDown() async {
    for (final s in List.of(_notify)) {
      await s.cancel();
    }
    _notify.clear();
    await _events.close();
    await _data.close();
  }

  @override
  Future<void> close() async {
    try {
      await _cancelQuietly(_conn, _log); // cancelling disconnects
    } finally {
      if (!_closed.isCompleted) _closed.complete();
    }
    await _closed.future;
  }
}
