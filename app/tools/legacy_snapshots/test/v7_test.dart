// Step 7 (3e72281): onboarding v1 + talk v1 (no conversation ids) + the
// privacy notice flag, written by that version's classes.
import 'package:flutter_test/flutter_test.dart';
import 'package:snapgen/v7/core/catalogue/sign_catalogue.dart';
import 'package:snapgen/v7/core/conversation/conversation_repository.dart';
import 'package:snapgen/v7/core/profile/onboarding_store.dart';
import 'package:snapgen/v7/core/storage/key_value_store.dart';

import 'dump.dart';

void main() {
  test('step 7 store', () async {
    final kv = MemoryKeyValueStore();
    final s = OnboardingStore(kv);
    await s.saveRole(UserRole.sign);
    await s.saveSpoken(SpokenLanguage.ar);
    await s.saveSignLanguageId('asl');
    await s.saveGlove(const PairedGlove(id: 'AA:BB:CC:DD:EE:02', name: 'Ishara-77C1'));
    await s.saveDone(done: true);
    final talk = LocalConversationRepository(kv);
    await talk.add(TalkMessage(side: MessageSide.me, text: 'مرحبا', at: DateTime(2026, 10, 12, 21, 3, 5, 120)));
    await talk.add(TalkMessage(side: MessageSide.them, text: 'Where is the pharmacy?', at: DateTime(2026, 10, 12, 21, 3, 40, 7)));
    await talk.add(TalkMessage(side: MessageSide.me, text: 'thank you', at: DateTime(2026, 10, 13, 8, 15)));
    await kv.setBool('talk.privacySeen', value: true); // TalkSpeechController.kPrivacySeen
    dump('v7', kv.keys, (k) => kv.getString(k) ?? kv.getBool(k) ?? kv.getInt(k));
  });
}
