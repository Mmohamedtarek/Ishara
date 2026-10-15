import 'dart:async';
import 'dart:convert';

import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:meta/meta.dart';

/// One emergency contact (Q-T4 phase 1).
@immutable
class EmergencyContact {
  const new({required this.name, required this.phone});

  final String name;

  /// E.164 (`+201012345678`).
  final String phone;

  Map<String, Object> toJson() => {'name': name, 'phone': phone};

  static EmergencyContact? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    final phone = j['phone'];
    if (name is! String || phone is! String || !phone.startsWith('+')) {
      return null;
    }
    return EmergencyContact(name: name, phone: phone);
  }

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact && other.name == name && other.phone == phone;

  @override
  int get hashCode => Object.hash(name, phone);
}

/// The emergency contacts, on this phone only: never synced or sent
/// anywhere (only the user's own SOS actions use them).
abstract interface class EmergencyContactsRepository {
  static const max = 3;

  List<EmergencyContact> get contacts;
  Stream<List<EmergencyContact>> get changes;

  /// Adds a contact (at most [max]); false when full.
  Future<bool> add(EmergencyContact contact);
  Future<void> replace(int index, EmergencyContact contact);
  Future<void> remove(int index);
}

/// In the phone's key-value store (S6-2 pattern), versioned. Not part of
/// the step 10 sync.
class LocalEmergencyContactsRepository implements EmergencyContactsRepository {
  new(this._kv) : _list = _load(_kv);

  final KeyValueStore _kv;
  final List<EmergencyContact> _list;
  final _changes = StreamController<List<EmergencyContact>>.broadcast();

  static const schemaVersion = 1;
  static const kVersion = 'sos.version';
  static const kContacts = 'sos.contacts';
  static final _log = Log('sos');

  static List<EmergencyContact> _load(KeyValueStore kv) {
    final raw = kv.getString(kContacts);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) throw const FormatException('not a list');
      return [for (final j in list) ?EmergencyContact.fromJson(j)]
          .take(EmergencyContactsRepository.max)
          .toList();
    } on FormatException catch (e) {
      _log.warn('load_failed', {'error': e.message});
      return [];
    }
  }

  @override
  List<EmergencyContact> get contacts => List.unmodifiable(_list);

  @override
  Stream<List<EmergencyContact>> get changes => _changes.stream;

  @override
  Future<bool> add(EmergencyContact contact) async {
    if (_list.length >= EmergencyContactsRepository.max) return false;
    _list.add(contact);
    await _save();
    return true;
  }

  @override
  Future<void> replace(int index, EmergencyContact contact) async {
    if (index < 0 || index >= _list.length) return;
    _list[index] = contact;
    await _save();
  }

  @override
  Future<void> remove(int index) async {
    if (index < 0 || index >= _list.length) return;
    _list.removeAt(index);
    await _save();
  }

  Future<void> _save() async {
    _changes.add(contacts);
    await _kv.setInt(kVersion, schemaVersion);
    await _kv.setString(
      kContacts,
      jsonEncode([for (final c in _list) c.toJson()]),
    );
  }

  /// Every stored value by key, for the step 10 migration (to the phone's
  /// own database: these never sync).
  Map<String, Object> export() => {
    if (_kv.getInt(kVersion) case final int v) kVersion: v,
    if (_kv.getString(kContacts) case final String v) kContacts: v,
  };

  Future<void> clear() async {
    _list.clear();
    _changes.add(contacts);
    await _kv.remove(kVersion);
    await _kv.remove(kContacts);
  }

  Future<void> dispose() => _changes.close();
}
