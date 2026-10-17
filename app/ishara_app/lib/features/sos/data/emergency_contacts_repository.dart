import 'dart:async';

import 'package:drift/drift.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/storage_health.dart';
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

/// In the phone's database (`contacts`, step 10a). Never part of the sync.
class LocalEmergencyContactsRepository implements EmergencyContactsRepository {
  /// `initial`: the stored contacts, in order (`LocalData`).
  new(this._db, {List<EmergencyContact> initial = const []})
    : _list = initial.take(EmergencyContactsRepository.max).toList();

  final AppDatabase _db;
  final List<EmergencyContact> _list;
  final _changes = StreamController<List<EmergencyContact>>.broadcast();

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

  /// The row for [contact] at [position] (the migration writes the same).
  static ContactsCompanion row(int position, EmergencyContact contact) =>
      ContactsCompanion.insert(
        position: Value(position),
        name: contact.name,
        phone: contact.phone,
      );

  /// The whole (tiny) list, rewritten in one transaction.
  Future<void> _save() async {
    _changes.add(contacts);
    final rows = [for (final (i, c) in _list.indexed) row(i, c)];
    await storeOrKeepGoing(
      () => _db.transaction(() async {
        await _db.delete(_db.contacts).go();
        await _db.batch((b) => b.insertAll(_db.contacts, rows));
      }),
    );
  }

  Future<void> dispose() => _changes.close();
}
