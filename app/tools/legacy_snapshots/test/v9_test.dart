// Step 9 (7aba72f, the current release on main): every store — onboarding
// v1, settings v1, talk v2 (conversation ids, Clear flag), phrases v1
// (with a tombstone), learn activity v1, sos v1, device id.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapgen/v9/core/catalogue/sign_catalogue.dart';
import 'package:snapgen/v9/core/conversation/conversation_repository.dart';
import 'package:snapgen/v9/core/device/device_id.dart';
import 'package:snapgen/v9/core/phrases/saved_phrases_repository.dart';
import 'package:snapgen/v9/core/profile/onboarding_store.dart';
import 'package:snapgen/v9/core/settings/settings_store.dart';
import 'package:snapgen/v9/core/storage/key_value_store.dart';
import 'package:snapgen/v9/features/learn/data/activity_repository.dart';
import 'package:snapgen/v9/features/learn/domain/activity_event.dart';
import 'package:snapgen/v9/features/learn/domain/local_day.dart';
import 'package:snapgen/v9/features/sos/data/emergency_contacts_repository.dart';

import 'dump.dart';

void main() {
  test('step 9 store', () async {
    final kv = MemoryKeyValueStore({
      // a step 7 message (talk v1, no conversation id) still in the list
      'talk.messages': '[{"side":"me","text":"hi","at":"2026-10-12T20:00:00.000"}]',
      'talk.version': 1,
    });
    final s = OnboardingStore(kv);
    await s.saveRole(UserRole.speak);
    await s.saveSpoken(SpokenLanguage.ar);
    await s.saveSignLanguageId('asl');
    await s.saveGlove(const PairedGlove(id: 'AA:BB:CC:DD:EE:09', name: 'Ishara-0B9E'));
    await s.saveDone(done: true);
    final st = SettingsStore(kv);
    await st.setString(SettingsStore.kLanguage, 'ar');
    await st.setString(SettingsStore.kTheme, 'dark');
    await st.setBool(SettingsStore.kBigText, value: true);
    await st.setBool(SettingsStore.kHighContrast, value: false);
    await st.setBool(SettingsStore.kVibrate, value: true);
    await st.setBool(SettingsStore.kSubtitles, value: false);
    await st.setSignSpeed(1.5);
    await st.setString(SettingsStore.kCharacter, 'nour');
    await st.setBool(SettingsStore.kDeveloper, value: true);
    final talk = LocalConversationRepository(kv, gap: () => const Duration(minutes: 10), random: Random(9));
    await talk.add(TalkMessage(side: MessageSide.me, text: 'hi again', at: DateTime(2026, 10, 12, 20, 4)));
    await talk.add(TalkMessage(side: MessageSide.them, text: 'محتاج مساعدة؟', at: DateTime(2026, 10, 15, 18, 2, 1, 250, 3)));
    await talk.add(TalkMessage(side: MessageSide.me, text: 'yes', at: DateTime(2026, 10, 15, 18, 2, 30)));
    await talk.startNewConversation();
    await kv.setBool('talk.privacySeen', value: true);
    var t = DateTime.utc(2026, 10, 15, 16, 3, 0, 0, 77);
    final phrases = LocalSavedPhrasesRepository(kv, now: () => t = t.add(const Duration(seconds: 7)), random: Random(99));
    await phrases.star('محتاج مساعدة؟');
    await phrases.star('Where is the pharmacy?');
    await phrases.unstar('Where is the pharmacy?');
    final device = DeviceId.of(kv, random: Random(19));
    final log = LocalActivityRepository(kv);
    final at = DateTime.utc(2026, 10, 15, 7, 45);
    await log.append(ActivityEvent(id: 'q1', type: ActivityType.quiz, moduleId: 'start', passed: true, xp: 10, day: LocalDay.of(at.toLocal()), at: at, deviceId: device, label: 'hello'));
    await log.append(ActivityEvent(id: 'm1', type: ActivityType.missionDone, moduleId: 'daily', passed: true, xp: 30, day: LocalDay.of(at.toLocal()), at: at, deviceId: device, prob: 1));
    final sos = LocalEmergencyContactsRepository(kv);
    await sos.add(const EmergencyContact(name: 'Mona', phone: '+201012345678'));
    await sos.add(const EmergencyContact(name: 'علي', phone: '+201123456789'));
    dump('v9', kv.keys, (k) => kv.getString(k) ?? kv.getBool(k) ?? kv.getInt(k));
  });
}
