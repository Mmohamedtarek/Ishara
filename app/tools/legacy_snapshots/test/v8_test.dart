// Step 8 (dc355a1): + learn activity v1 and the device id.
import 'package:flutter_test/flutter_test.dart';
import 'package:snapgen/v8/core/catalogue/sign_catalogue.dart';
import 'package:snapgen/v8/core/conversation/conversation_repository.dart';
import 'package:snapgen/v8/core/device/device_id.dart';
import 'package:snapgen/v8/core/profile/onboarding_store.dart';
import 'package:snapgen/v8/core/storage/key_value_store.dart';
import 'package:snapgen/v8/features/learn/data/activity_repository.dart';
import 'package:snapgen/v8/features/learn/domain/activity_event.dart';
import 'package:snapgen/v8/features/learn/domain/local_day.dart';

import 'dart:math';

import 'dump.dart';

void main() {
  test('step 8 store', () async {
    final kv = MemoryKeyValueStore();
    final s = OnboardingStore(kv);
    await s.saveRole(UserRole.sign);
    await s.saveSpoken(SpokenLanguage.en);
    await s.saveSignLanguageId('asl');
    await s.saveDone(done: true);
    final talk = LocalConversationRepository(kv);
    await talk.add(TalkMessage(side: MessageSide.them, text: 'hello', at: DateTime(2026, 10, 14, 10)));
    await kv.setBool('talk.privacySeen', value: true);
    final device = DeviceId.of(kv, random: Random(8));
    final log = LocalActivityRepository(kv);
    final at = DateTime.utc(2026, 10, 14, 9, 30);
    ActivityEvent e(String id, ActivityType t, {String? label, bool passed = true, double? prob, int xp = 10}) =>
        ActivityEvent(id: id, type: t, moduleId: 'start', passed: passed, xp: xp, day: LocalDay.of(at.toLocal()), at: at, deviceId: device, label: label, prob: prob);
    await log.append(e('e1', ActivityType.quiz, label: 'hello'));
    await log.append(e('e2', ActivityType.practice, label: 'thanks', prob: 0.8734, xp: 15));
    await log.append(e('e3', ActivityType.practice, label: 'yes', passed: false, prob: 0.31, xp: 0));
    await log.append(e('e4', ActivityType.missionDone, prob: 0.8, xp: 0));
    dump('v8', kv.keys, (k) => kv.getString(k) ?? kv.getBool(k) ?? kv.getInt(k));
  });
}
