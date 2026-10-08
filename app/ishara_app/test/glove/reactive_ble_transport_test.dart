@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/ble/reactive_ble_transport.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/glove_transport.dart';

final _svc = Uuid.parse(IsharaUuids.service);
final Set<Uuid> _all = {
  for (final c in [
    IsharaUuids.data,
    IsharaUuids.cmd,
    IsharaUuids.event,
    IsharaUuids.info,
  ])
    Uuid.parse(c),
};

/// A scripted radio. The glove side answers CMD writes with EVENT lines.
class FakeBleApi implements BleApi {
  new({this.status = BleStatus.ready});

  @override
  BleStatus status;
  final statusCtl = StreamController<BleStatus>.broadcast(sync: true);
  final scanCtl = StreamController<DiscoveredDevice>.broadcast(sync: true);
  final connCtl = StreamController<ConnectionStateUpdate>.broadcast(sync: true);
  final notifiers = <Uuid, StreamController<List<int>>>{};
  final calls = <String>[];
  Set<Uuid> characteristics = _all;
  bool scanCancelled = false;
  bool connectionCancelled = false;

  /// The platform disconnect throws (e.g. the adapter was turned off).
  bool failDisconnect = false;

  /// EVENT lines the glove sends for each command.
  Map<String, List<String>> replies = {
    'GETCAL': ['#CAL NONE'],
    'STREAM 1': ['#OK STREAM'],
    'STREAM 0': ['#OK STREAM'],
  };

  @override
  Stream<BleStatus> get statusStream => statusCtl.stream;

  @override
  Stream<DiscoveredDevice> scan(List<Uuid> services) {
    calls.add('scan');
    return scanCtl.stream.doOnCancel(() => scanCancelled = true);
  }

  @override
  Stream<ConnectionStateUpdate> connect(
    String id, {
    required Duration timeout,
  }) {
    calls.add('connect $id');
    return connCtl.stream.doOnCancel(() {
      connectionCancelled = true;
      if (failDisconnect) throw Exception('disconnectDevice failed');
    });
  }

  void update(DeviceConnectionState s) => connCtl.add(
    ConnectionStateUpdate(deviceId: 'AA', connectionState: s, failure: null),
  );

  @override
  Future<int> requestMtu(String id, int mtu) async {
    calls.add('mtu $mtu');
    return mtu;
  }

  @override
  Future<Set<Uuid>> characteristicsOf(String id, Uuid service) async {
    calls.add('discover');
    return service == _svc ? characteristics : {};
  }

  @override
  Future<List<int>> read(QualifiedCharacteristic c) async {
    calls.add('read ${c.characteristicId}');
    return utf8.encode('{"proto":1,"fw":"0.3.0","board":"devkit"}');
  }

  StreamController<List<int>> notifier(String uuid) => notifiers.putIfAbsent(
    Uuid.parse(uuid),
    () => StreamController<List<int>>.broadcast(sync: true),
  );

  @override
  Stream<List<int>> subscribe(QualifiedCharacteristic c) {
    calls.add('subscribe ${c.characteristicId}');
    final ctl = notifier(c.characteristicId.toString());
    if (c.characteristicId == Uuid.parse(IsharaUuids.event)) {
      // The glove sends #BAT when EVENT is subscribed (BLE §6).
      scheduleMicrotask(() => line('#BAT OK 3.92V 78%'));
    }
    return ctl.stream;
  }

  void line(String l) => notifier(IsharaUuids.event).add(utf8.encode('$l\n'));

  @override
  Future<void> writeWithResponse(
    QualifiedCharacteristic c,
    List<int> value,
  ) async {
    final cmd = utf8.decode(value);
    calls.add('write ${c.characteristicId} $cmd');
    replies[cmd]?.forEach(line);
  }
}

extension<T> on Stream<T> {
  Stream<T> doOnCancel(void Function() f) {
    late StreamController<T> out;
    StreamSubscription<T>? sub;
    out = StreamController<T>(
      onListen: () =>
          sub = listen(out.add, onError: out.addError, onDone: out.close),
      onCancel: () async {
        f();
        await sub?.cancel();
      },
    );
    return out.stream;
  }
}

DiscoveredDevice _dev(String id, String name, int rssi) => DiscoveredDevice(
  id: id,
  name: name,
  serviceData: const {},
  manufacturerData: Uint8List(0),
  rssi: rssi,
  serviceUuids: [_svc],
);

const _glove = DiscoveredGlove(id: 'AA', name: 'Ishara-3FA2', rssi: -50);

/// Real (short) time for tests that close or cancel connections:
/// cancelling a broadcast subscription completes in the root zone, which
/// FakeAsync never runs. On a device this completes normally.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

Future<GloveLink> _openReal(FakeBleApi a) async {
  final f = ReactiveBleTransport(a).open(_glove);
  await _settle();
  a.update(DeviceConnectionState.connected);
  return await f;
}

void main() {
  group('adapter state', () {
    for (final (status, problem) in [
      (BleStatus.poweredOff, BluetoothProblem.off),
      (BleStatus.unauthorized, BluetoothProblem.unauthorized),
      (BleStatus.locationServicesDisabled, BluetoothProblem.locationOff),
      (BleStatus.unsupported, BluetoothProblem.unsupported),
    ]) {
      test('$status -> $problem (scan and connect)', () async {
        final t = ReactiveBleTransport(FakeBleApi(status: status));
        await expectLater(
          t.scan(timeout: const Duration(seconds: 1)),
          emitsError(
            isA<BluetoothUnavailableFailure>().having(
              (f) => f.problem,
              'problem',
              problem,
            ),
          ),
        );
        await expectLater(
          t.open(_glove),
          throwsA(isA<BluetoothUnavailableFailure>()),
        );
      });
    }

    test('unknown, then ready: waits for the state', () async {
      final api = FakeBleApi(status: BleStatus.unknown);
      final lists = <List<DiscoveredGlove>>[];
      ReactiveBleTransport(api)
          .scan(timeout: const Duration(milliseconds: 300))
          .listen(lists.add);
      await _settle();
      expect(lists, isEmpty);
      api.statusCtl.add(BleStatus.ready);
      await _settle();
      expect(lists, [<DiscoveredGlove>[]]);
    });

    test('state never known -> not ready after the wait', () async {
      final t = ReactiveBleTransport(
        FakeBleApi(status: BleStatus.unknown),
        statusWait: const Duration(milliseconds: 100),
      );
      await expectLater(
        t.open(_glove),
        throwsA(
          isA<BluetoothUnavailableFailure>().having(
            (f) => f.problem,
            'problem',
            BluetoothProblem.notReady,
          ),
        ),
      );
    });
  });

  group('scan', () {
    test(
      'Ishara gloves only, deduplicated, strongest first, ends on time',
      () async {
        final api = FakeBleApi();
        final lists = <List<DiscoveredGlove>>[];
        final done = Completer<void>();
        ReactiveBleTransport(api)
            .scan(timeout: const Duration(milliseconds: 300))
            .listen(lists.add, onDone: done.complete);
        await _settle();
        api.scanCtl
          ..add(_dev('AA', 'Ishara-3FA2', -70))
          ..add(_dev('BB', 'Speaker', -30)) // not a glove
          ..add(_dev('CC', 'Ishara-12', -40)) // wrong name format
          ..add(_dev('DD', 'Ishara-00B1', -55))
          ..add(_dev('AA', 'Ishara-3FA2', -45)); // same glove, stronger now
        await _settle();
        expect(lists.last.map((g) => (g.name, g.rssi)), [
          ('Ishara-3FA2', -45),
          ('Ishara-00B1', -55),
        ]);
        await done.future.timeout(const Duration(seconds: 2));
        await _settle();
        expect(api.scanCancelled, isTrue);
      },
    );
  });

  group('open (BLE §3 steps 1-3)', () {
    test('connect, MTU 247 (negotiated or read back), service check', () async {
      final api = FakeBleApi();
      final link = await _openReal(api);
      expect(api.calls, ['connect AA', 'mtu 247', 'discover']);
      expect(link.mtu, 247);
    });

    test(
      'missing characteristic: not an Ishara glove, connection dropped',
      () async {
        final api = FakeBleApi()
          ..characteristics = {Uuid.parse(IsharaUuids.cmd)};
        await expectLater(_openReal(api), throwsA(isA<GloveConnectFailure>()));
        expect(api.connectionCancelled, isTrue);
      },
    );

    test('disconnected while connecting: failure', () async {
      final api = FakeBleApi();
      final f = ReactiveBleTransport(api).open(_glove);
      await _settle();
      api
        ..update(DeviceConnectionState.connecting)
        ..update(DeviceConnectionState.disconnected);
      await expectLater(
        f.timeout(const Duration(seconds: 1)),
        throwsA(isA<GloveConnectFailure>()),
      );
    });

    test('native connect error: failure', () async {
      final api = FakeBleApi();
      final f = ReactiveBleTransport(api).open(_glove);
      await _settle();
      api.connCtl.addError(TimeoutException('native timeout'));
      await expectLater(f, throwsA(isA<GloveConnectFailure>()));
    });

    test('no answer: timeout, connection dropped', () async {
      final api = FakeBleApi();
      final f = ReactiveBleTransport(
        api,
        connectTimeout: const Duration(milliseconds: 100),
      ).open(_glove);
      // The transport allows 2 s of grace over the native timeout.
      await expectLater(
        f.timeout(const Duration(seconds: 4)),
        throwsA(isA<GloveConnectFailure>()),
      );
      expect(api.connectionCancelled, isTrue);
    });
  });

  group('link', () {
    test('INFO read, notifications forwarded, CMD write', () async {
      final api = FakeBleApi();
      final link = await _openReal(api);
      final events = <Uint8List>[];
      final data = <Uint8List>[];
      link.eventNotifications.listen(events.add);
      link.dataNotifications.listen(data.add);
      expect(utf8.decode(await link.readInfo()), contains('"proto":1'));
      await link.subscribeEvents();
      await link.subscribeData();
      await _settle();
      expect(utf8.decode(events.single), '#BAT OK 3.92V 78%\n');
      api.notifier(IsharaUuids.data).add([1, 2, 3]);
      expect(data.single, [1, 2, 3]);
      await link.writeCommand(Uint8List.fromList(utf8.encode('PING')));
      expect(api.calls, contains('write ${Uuid.parse(IsharaUuids.cmd)} PING'));
      expect(api.calls, contains('read ${Uuid.parse(IsharaUuids.info)}'));
    });

    test('close disconnects; a remote disconnect completes closed', () async {
      final a1 = FakeBleApi();
      final l1 = await _openReal(a1);
      await l1.close();
      await l1.closed.timeout(const Duration(seconds: 1));
      expect(a1.connectionCancelled, isTrue);

      final a2 = FakeBleApi();
      final l2 = await _openReal(a2);
      a2.update(DeviceConnectionState.disconnected);
      await l2.closed.timeout(const Duration(seconds: 1));
    });

    test('a notification error means the link is gone', () async {
      final api = FakeBleApi();
      final link = await _openReal(api);
      link.eventNotifications.listen((_) {});
      await link.subscribeEvents();
      api.notifier(IsharaUuids.event).addError(Exception('gatt 133'));
      await link.closed.timeout(const Duration(seconds: 1));
    });
  });

  group('review regressions', () {
    test('a late disconnected of an earlier session is ignored', () async {
      final api = FakeBleApi();
      final f = ReactiveBleTransport(api).open(_glove);
      await _settle();
      api
        ..update(DeviceConnectionState.disconnected) // stale
        ..update(DeviceConnectionState.connecting)
        ..update(DeviceConnectionState.connected);
      final link = await f;
      expect(link.mtu, 247);
    });

    test('a notification error really disconnects', () async {
      final api = FakeBleApi();
      final link = await _openReal(api);
      link.eventNotifications.listen((_) {});
      await link.subscribeEvents();
      api.notifier(IsharaUuids.event).addError(Exception('gatt 133'));
      await link.closed.timeout(const Duration(seconds: 1));
      await _settle();
      expect(api.connectionCancelled, isTrue);
    });

    test('close completes even if the platform disconnect throws', () async {
      final api = FakeBleApi();
      final link = await _openReal(api);
      api.failDisconnect = true;
      await link.close().timeout(const Duration(seconds: 1));
      await link.closed.timeout(const Duration(seconds: 1));
    });

    test('nothing can subscribe or write after the link closed', () async {
      final api = FakeBleApi();
      final link = await _openReal(api);
      await link.close();
      await expectLater(
        link.subscribeData,
        throwsA(isA<GloveDisconnectedFailure>()),
      );
      await expectLater(
        link.writeCommand(Uint8List(1)),
        throwsA(isA<GloveDisconnectedFailure>()),
      );
      await expectLater(
        link.readInfo,
        throwsA(isA<GloveDisconnectedFailure>()),
      );
    });

    test('scan error: the real Bluetooth problem, and the scan ends', () async {
      final api = FakeBleApi();
      final errors = <Object>[];
      final done = Completer<void>();
      ReactiveBleTransport(api)
          .scan(timeout: const Duration(seconds: 5))
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await _settle();
      api.status = BleStatus.poweredOff;
      api.scanCtl.addError(Exception('scan stopped'));
      await done.future.timeout(const Duration(seconds: 1));
      expect(
        errors.single,
        isA<BluetoothUnavailableFailure>().having(
          (f) => f.problem,
          'problem',
          BluetoothProblem.off,
        ),
      );
    });

    test('scan error with Bluetooth ready: a scan failure', () async {
      final api = FakeBleApi();
      final errors = <Object>[];
      ReactiveBleTransport(api)
          .scan(timeout: const Duration(seconds: 5))
          .listen((_) {}, onError: errors.add);
      await _settle();
      api.scanCtl.addError(Exception('throttled'));
      await _settle();
      expect(errors.single, isA<GloveScanFailure>());
      expect((errors.single as GloveScanFailure).kind, 'glove_scan');
    });

    test(
      'state still unknown after the wait: not ready (retry), not unsupported',
      () async {
        final t = ReactiveBleTransport(
          FakeBleApi(status: BleStatus.unknown),
          statusWait: const Duration(milliseconds: 100),
        );
        await expectLater(
          t.open(_glove),
          throwsA(
            isA<BluetoothUnavailableFailure>().having(
              (f) => f.problem,
              'problem',
              BluetoothProblem.notReady,
            ),
          ),
        );
      },
    );
  });

  test('end to end: GloveClient over reactive BLE reaches streaming', () async {
    final api = FakeBleApi();
    final client = GloveClient(ReactiveBleTransport(api));
    final samples = <GloveSample>[];
    client.samples.listen(samples.addAll);
    final connecting = client.connect(_glove);
    await _settle();
    api.update(DeviceConnectionState.connected);
    await connecting.timeout(const Duration(seconds: 4));
    expect(client.status.phase, GlovePhase.ready);
    expect(client.status.battery!.percent, 78);
    expect(client.status.info!.board, 'devkit');
    api
        .notifier(IsharaUuids.data)
        .add(FrameCodec.encode([GloveSample(7, Int16List(11)..[0] = 42)]));
    expect(samples.single.values.first, 42);
    // The glove goes out of range.
    api.update(DeviceConnectionState.disconnected);
    await _settle();
    expect(client.status.failure, isA<GloveDisconnectedFailure>());
    expect(client.status.phase, GlovePhase.idle);
  });
}
