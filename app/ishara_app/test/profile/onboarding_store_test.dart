import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

void main() {
  test('defaults: I sign, Arabic voice, no glove, not done', () {
    final s = OnboardingStore(MemoryKeyValueStore());
    expect(s.role, UserRole.sign);
    expect(s.spoken, SpokenLanguage.ar);
    expect(s.glove, isNull);
    expect(s.done, isFalse);
    expect(s.export(), isEmpty);
  });

  test('values survive a restart (a new store on the same data)', () async {
    final kv = MemoryKeyValueStore();
    final s = OnboardingStore(kv);
    await s.saveRole(UserRole.speak);
    await s.saveSpoken(SpokenLanguage.en);
    await s.saveSignLanguageId('asl');
    await s.saveGlove(const PairedGlove(id: 'AA:BB', name: 'Ishara-3FA2'));
    await s.saveDone(done: true);
    final again = OnboardingStore(kv);
    expect(again.role, UserRole.speak);
    expect(again.spoken, SpokenLanguage.en);
    expect(again.signLanguageId, 'asl');
    expect(again.glove, const PairedGlove(id: 'AA:BB', name: 'Ishara-3FA2'));
    expect(again.done, isTrue);
  });

  test('S6-2: export gives every saved value for the database migration, '
      'and clear removes them', () async {
    final kv = MemoryKeyValueStore();
    final s = OnboardingStore(kv);
    await s.saveRole(UserRole.speak);
    await s.saveSpoken(SpokenLanguage.en);
    await s.saveSignLanguageId('asl');
    await s.saveGlove(const PairedGlove(id: 'id-1', name: 'Ishara-0001'));
    await s.saveDone(done: true);
    expect(s.export(), {
      OnboardingStore.kVersion: OnboardingStore.schemaVersion,
      OnboardingStore.kRole: 'speak',
      OnboardingStore.kSpoken: 'en',
      OnboardingStore.kSignLanguage: 'asl',
      OnboardingStore.kGloveId: 'id-1',
      OnboardingStore.kGloveName: 'Ishara-0001',
      OnboardingStore.kDone: true,
    });
    // nothing else is stored, so nothing can be missed by the migration
    expect(kv.keys, s.export().keys.toSet());
    await s.clear();
    expect(kv.keys, isEmpty);
  });

  test('forgetting the glove keeps the other answers', () async {
    final s = OnboardingStore(MemoryKeyValueStore());
    await s.saveRole(UserRole.speak);
    await s.saveGlove(const PairedGlove(id: 'x', name: 'Ishara-0002'));
    await s.forgetGlove();
    expect(s.glove, isNull);
    expect(s.role, UserRole.speak);
  });

  test('unknown stored values fall back to the defaults', () {
    final s = OnboardingStore(
      MemoryKeyValueStore({
        OnboardingStore.kRole: 'dance',
        OnboardingStore.kSpoken: 'fr',
        OnboardingStore.kDone: 'yes',
      }),
    );
    expect(s.role, UserRole.sign);
    expect(s.spoken, SpokenLanguage.ar);
    expect(s.done, isFalse);
  });

  group('providers', () {
    test('the profile loads the saved answers and saves changes', () async {
      final kv = MemoryKeyValueStore();
      await OnboardingStore(kv).saveRole(UserRole.speak);
      final c = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(kv)],
      );
      addTearDown(c.dispose);
      expect(c.read(profileControllerProvider).role, UserRole.speak);
      final p = c.read(profileControllerProvider.notifier);
      await p.setSpoken(SpokenLanguage.en);
      await p.setGlove(const PairedGlove(id: 'g', name: 'Ishara-0003'));
      await p.finishOnboarding();
      final s = OnboardingStore(kv);
      expect(s.spoken, SpokenLanguage.en);
      expect(s.glove?.name, 'Ishara-0003');
      expect(s.done, isTrue);
      await p.forgetGlove();
      expect(c.read(profileControllerProvider).glove, isNull);
      expect(OnboardingStore(kv).glove, isNull);
    });

    test('sign language: saved on select; a stored arsl falls back to ASL '
        '(sign rule 8)', () async {
      final kv = MemoryKeyValueStore({OnboardingStore.kSignLanguage: 'arsl'});
      final c = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(kv)],
      );
      addTearDown(c.dispose);
      expect(c.read(activeSignLanguageProvider), SignLanguage.asl);
      expect(
        c.read(activeSignLanguageProvider.notifier).select(SignLanguage.arsl),
        isFalse,
      );
      expect(kv.getString(OnboardingStore.kSignLanguage), 'arsl');
      expect(
        c.read(activeSignLanguageProvider.notifier).select(SignLanguage.asl),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(kv.getString(OnboardingStore.kSignLanguage), 'asl');
    });
  });
}
