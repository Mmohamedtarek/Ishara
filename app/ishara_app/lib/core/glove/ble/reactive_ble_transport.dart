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

  Stream<DiscoveredDevice> scan(
    List<Uuid> services, {
    required bool requireLocationServices,
  });

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
  Stream<DiscoveredDevice> scan(
    List<Uuid> services, {
    required bool requireLocationServices,
  }) => _ble.scanForDevices(
    withServices: services,
    scanMode: ScanMode.lowLatency,
    requireLocationServicesEnabled: requireLocationServices,
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
    required this.isAndroid,
    this.requireLocationServices = false,
    this.connectTimeout = const Duration(seconds: 10),
    this.statusWait = const Duration(seconds: 3),
  });

  final BleApi _api;

  /// Android requests MTU 247; iOS negotiates by itself (BLE §3).
  final bool isAndroid;

  /// Android 11 and older need location services on to scan.
  final bool requireLocationServices;
  final Duration connectTimeout;

  /// How long to wait for the adapter state to be known.
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

  /// Throws [BluetoothUnavailableFailure] unless the adapter is ready.
  Future<void> _ensureReady() async {
    var status = _api.status;
    if (status == BleStatus.unknown) {
      status = await _api.statusStream
          .firstWhere((s) => s != BleStatus.unknown)
          .timeout(statusWait, onTimeout: () => BleStatus.unknown);
    }
    final problem = switch (status) {
      BleStatus.ready => null,
      BleStatus.poweredOff => BluetoothProblem.off,
      BleStatus.unauthorized => BluetoothProblem.unauthorized,
      BleStatus.locationServicesDisabled => BluetoothProblem.locationOff,
      BleStatus.unsupported ||
      BleStatus.unknown => BluetoothProblem.unsupported,
    };
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
        .scan([_service], requireLocationServices: requireLocationServices)
        .listen(
          (d) {
            // Only real Ishara gloves (BLE §1: `Ishara-XXXX`).
            if (!IsharaUuids.namePattern.hasMatch(d.name)) return;
            found[d.id] = DiscoveredGlove(id: d.id, name: d.name, rssi: d.rssi);
            out.add(sorted());
          },
          onError: (Object e, StackTrace st) {
            out.addError(
              GloveConnectFailure('scan failed', cause: e, stackTrace: st),
            );
          },
        );
    final timer = Timer(timeout, () => unawaited(out.close()));
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
    late final StreamSubscription<ConnectionStateUpdate> conn;
    conn = _api
        .connect(glove.id, timeout: connectTimeout)
        .listen(
          (u) {
            switch (u.connectionState) {
              case DeviceConnectionState.connected:
                if (!connected.isCompleted) connected.complete();
              case DeviceConnectionState.disconnected:
                final err = GloveConnectFailure(
                  'disconnected while connecting',
                  cause: u.failure,
                );
                if (!connected.isCompleted) connected.completeError(err);
                if (!closed.isCompleted) closed.complete();
              case DeviceConnectionState.connecting ||
                  DeviceConnectionState.disconnecting:
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
      // BLE §3 step 2: MTU 247 on Android (it starts at 23).
      final mtu = isAndroid
          ? await _api.requestMtu(glove.id, IsharaUuids.requestedMtu)
          : 0;
      // Step 3: the Ishara service with its 4 characteristics.
      final chars = await _api.characteristicsOf(glove.id, _service);
      if (!chars.containsAll(_required)) {
        throw const GloveConnectFailure(
          'not an Ishara glove (service missing)',
        );
      }
      _log.info('linked', {'mtu': mtu});
      return _ReactiveLink(_api, glove.id, mtu, conn, closed);
    } on Object {
      await conn.cancel();
      if (!closed.isCompleted) closed.complete();
      rethrow;
    }
  }
}

class _ReactiveLink implements GloveLink {
  new(this._api, this._id, this.mtu, this._conn, this._closed) {
    unawaited(_closed.future.then((_) => _shutDown()));
  }

  final BleApi _api;
  final String _id;
  final StreamSubscription<ConnectionStateUpdate> _conn;
  final Completer<void> _closed;
  final _events = StreamController<Uint8List>.broadcast(sync: true);
  final _data = StreamController<Uint8List>.broadcast(sync: true);
  final List<StreamSubscription<List<int>>> _notify = [];

  /// Negotiated MTU (0 on iOS: the system picks it, usually 185).
  @override
  final int mtu;

  QualifiedCharacteristic _char(String uuid) => QualifiedCharacteristic(
    serviceId: Uuid.parse(IsharaUuids.service),
    characteristicId: Uuid.parse(uuid),
    deviceId: _id,
  );

  @override
  Future<Uint8List> readInfo() async =>
      Uint8List.fromList(await _api.read(_char(IsharaUuids.info)));

  @override
  Stream<Uint8List> get eventNotifications => _events.stream;

  @override
  Stream<Uint8List> get dataNotifications => _data.stream;

  void _forward(String uuid, StreamController<Uint8List> to) {
    _notify.add(
      _api
          .subscribe(_char(uuid))
          .listen(
            (v) {
              if (!to.isClosed) to.add(Uint8List.fromList(v));
            },
            onError: (Object e) {
              // A notification error means the link is gone.
              if (!_closed.isCompleted) _closed.complete();
            },
          ),
    );
  }

  @override
  Future<void> subscribeEvents() async => _forward(IsharaUuids.event, _events);

  @override
  Future<void> subscribeData() async => _forward(IsharaUuids.data, _data);

  @override
  Future<void> writeCommand(Uint8List bytes) =>
      _api.writeWithResponse(_char(IsharaUuids.cmd), bytes);

  @override
  Future<void> get closed => _closed.future;

  Future<void> _shutDown() async {
    for (final s in _notify) {
      await s.cancel();
    }
    _notify.clear();
    await _events.close();
    await _data.close();
  }

  @override
  Future<void> close() async {
    await _conn.cancel(); // cancelling the connection stream disconnects
    if (!_closed.isCompleted) _closed.complete();
    await _closed.future;
  }
}
