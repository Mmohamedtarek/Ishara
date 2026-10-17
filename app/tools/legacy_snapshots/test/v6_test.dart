// Step 6 (432af54): onboarding v1, written by that version's OnboardingStore.
import 'package:flutter_test/flutter_test.dart';
import 'package:snapgen/v6/core/catalogue/sign_catalogue.dart';
import 'package:snapgen/v6/core/profile/onboarding_store.dart';
import 'package:snapgen/v6/core/storage/key_value_store.dart';

import 'dump.dart';

void main() {
  test('step 6 store', () async {
    final kv = MemoryKeyValueStore();
    final s = OnboardingStore(kv);
    await s.saveRole(UserRole.speak);
    await s.saveSpoken(SpokenLanguage.en);
    await s.saveSignLanguageId('asl');
    await s.saveGlove(const PairedGlove(id: 'AA:BB:CC:DD:EE:01', name: 'Ishara-3F2A'));
    await s.saveDone(done: true);
    dump('v6', kv.keys, (k) => kv.getString(k) ?? kv.getBool(k) ?? kv.getInt(k));
  });
}
