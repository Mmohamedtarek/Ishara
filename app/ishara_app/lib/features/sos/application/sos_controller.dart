import 'dart:async';

import 'package:clock/clock.dart';
import 'package:ishara_app/core/config/app_rules.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';
import 'package:ishara_app/features/sos/data/sos_platform.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sos_controller.g.dart';

@Riverpod(keepAlive: true)
EmergencyContactsRepository emergencyContactsRepository(Ref ref) {
  final repo = LocalEmergencyContactsRepository(
    ref.watch(keyValueStoreProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
}

@Riverpod(keepAlive: true)
Stream<List<EmergencyContact>> emergencyContacts(Ref ref) async* {
  final repo = ref.watch(emergencyContactsRepositoryProvider);
  yield repo.contacts;
  yield* repo.changes;
}

@Riverpod(keepAlive: true)
LocationSource locationSource(Ref ref) => const PhoneLocation();

@Riverpod(keepAlive: true)
LocationPermissions locationPermissions(Ref ref) => const PhoneLocation();

@Riverpod(keepAlive: true)
SosLauncher sosLauncher(Ref ref) => const PhoneSosLauncher();

/// The SOS sheet.
@immutable
class SosState {
  const new({
    this.location,
    this.contacts = const [],
    this.whatsApp = false,
    this.ambulance,
    this.locationOff = false,
  });

  /// Null while locating.
  final SosLocation? location;
  final List<EmergencyContact> contacts;

  /// WhatsApp is installed.
  final bool whatsApp;

  /// The ambulance number (`app_rules.json`), null if the data has none.
  final String? ambulance;

  /// Location is refused or switched off for the app (SOS still works).
  final bool locationOff;

  bool get locating => location == null;

  SosState copyWith({
    SosLocation? location,
    List<EmergencyContact>? contacts,
    bool? whatsApp,
    bool? locationOff,
  }) => SosState(
    location: location ?? this.location,
    contacts: contacts ?? this.contacts,
    whatsApp: whatsApp ?? this.whatsApp,
    ambulance: ambulance,
    locationOff: locationOff ?? this.locationOff,
  );
}

/// One SOS sheet (Q-T4 phase 1). It starts locating the moment it opens
/// (D23 is already spoken: nothing waits for the position). Every action
/// needs the user's own tap and opens another app filled in.
@riverpod
class SosController extends _$SosController {
  @override
  SosState build() {
    final rules = ref.read(appRulesProvider).value;
    final repo = ref.read(emergencyContactsRepositoryProvider);
    unawaited(_locate());
    unawaited(_checkWhatsApp());
    return SosState(contacts: repo.contacts, ambulance: rules?.ambulance);
  }

  Future<void> _locate() async {
    final access = await ref.read(locationPermissionsProvider).status();
    if (!ref.mounted) return;
    if (access != LocationAccess.granted) {
      state = state.copyWith(locationOff: true);
    }
    final where = await SosLocator.locate(ref.read(locationSourceProvider));
    if (ref.mounted) state = state.copyWith(location: where);
  }

  Future<void> _checkWhatsApp() async {
    final has = await ref.read(sosLauncherProvider).hasWhatsApp();
    if (ref.mounted) state = state.copyWith(whatsApp: has);
  }

  DateTime now() => clock.now();

  SosLauncher get _launcher => ref.read(sosLauncherProvider);

  /// The SMS app, every contact as a recipient, [message] filled in.
  Future<bool> sms(String message) =>
      _launcher.sms([for (final c in state.contacts) c.phone], message);

  Future<bool> whatsApp(EmergencyContact c, String message) =>
      _launcher.whatsApp(c.phone, message);

  Future<bool> dial(String number) => _launcher.dial(number);
}
