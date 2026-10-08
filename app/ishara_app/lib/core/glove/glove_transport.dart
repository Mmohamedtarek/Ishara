import 'dart:async';
import 'dart:typed_data';

import 'package:ishara_app/core/glove/glove_source.dart';

/// UUIDs of BLE-CONTRACT §2.
abstract final class IsharaUuids {
  static const service = '6e1a0001-7b5c-4f3a-9a62-1d2c3b4a5f60';
  static const data = '6e1a0002-7b5c-4f3a-9a62-1d2c3b4a5f60';
  static const cmd = '6e1a0003-7b5c-4f3a-9a62-1d2c3b4a5f60';
  static const event = '6e1a0004-7b5c-4f3a-9a62-1d2c3b4a5f60';
  static const info = '6e1a0005-7b5c-4f3a-9a62-1d2c3b4a5f60';

  /// Advertised name: `Ishara-XXXX` (last 4 hex digits of the MAC, upper case).
  static final namePattern = RegExp(r'^Ishara-[0-9A-F]{4}$');

  /// MTU the app requests (BLE §3).
  static const requestedMtu = 247;
}

/// The radio layer: scanning and opening links. One implementation per BLE
/// library, plus the mock glove. Throws `BluetoothUnavailableFailure` when
/// Bluetooth can't be used.
abstract interface class GloveTransport {
  /// Gloves found so far (advertising the Ishara service), until [timeout].
  Stream<List<DiscoveredGlove>> scan({required Duration timeout});

  /// BLE §3 steps 1-3: connect, request MTU 247 (Android), discover the
  /// service and its 4 characteristics. Throws `GloveConnectFailure`.
  Future<GloveLink> open(DiscoveredGlove glove);
}

/// One open connection to a glove (GATT of BLE-CONTRACT §2).
abstract interface class GloveLink {
  /// Negotiated MTU.
  int get mtu;

  /// Reads INFO (JSON).
  Future<Uint8List> readInfo();

  /// EVENT notifications. Listen to this **before** [subscribeEvents]: the
  /// glove sends `#BAT` as soon as the subscription is made (BLE §6).
  Stream<Uint8List> get eventNotifications;

  /// DATA notifications. Listen before [subscribeData].
  Stream<Uint8List> get dataNotifications;

  /// Enables EVENT notifications (do this before [subscribeData]).
  Future<void> subscribeEvents();

  /// Enables DATA notifications.
  Future<void> subscribeData();

  /// Writes one command to CMD (with response).
  Future<void> writeCommand(Uint8List bytes);

  /// Completes when the link drops (for any reason, including [close]).
  Future<void> get closed;

  /// Disconnects.
  Future<void> close();
}
