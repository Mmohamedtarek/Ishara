import 'package:drift/drift.dart' show ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/storage_health.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/storage_notice.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

import '../support/failing_db.dart';

const _en =
    "Your phone is out of storage, so Ishara can't save new changes. Free "
    'up some space.';

void main() {
  group('a write that fails (step 10a review)', () {
    test('is reported once; the repositories keep the change for the '
        'session and never throw', () async {
      final health = StorageHealth();
      final db = fullDiskDb(health);
      addTearDown(db.close);
      var raised = 0;
      health.notSaving.addListener(() => raised++);
      final talk = LocalConversationRepository(
        db,
        MemoryKeyValueStore(),
        gap: () => const Duration(minutes: 10),
      );
      await talk.add(
        TalkMessage(side: MessageSide.me, text: 'hi', at: DateTime(2026)),
      );
      expect(talk.messages.single.text, 'hi');
      final phrases = LocalSavedPhrasesRepository(db);
      await phrases.star('hi');
      expect(phrases.phrases.single.text, 'hi');
      final contacts = LocalEmergencyContactsRepository(db);
      expect(
        await contacts.add(const EmergencyContact(name: 'A', phone: '+201')),
        isTrue,
      );
      final kv = await DriftKeyValueStore.load(db);
      await kv.setString('settings.theme', 'dark');
      expect(kv.getString('settings.theme'), 'dark');
      expect(health.notSaving.value, isTrue);
      expect(raised, 1);
      await talk.dispose();
      await phrases.dispose();
      await contacts.dispose();
    });

    test('a working database raises nothing; degraded mode raises at the '
        'first write', () async {
      final ok = StorageHealth();
      final db = AppDatabase(
        NativeDatabase.memory().interceptWith(WriteWatch(ok)),
      );
      addTearDown(db.close);
      await (await DriftKeyValueStore.load(db)).setBool('x', value: true);
      expect(ok.notSaving.value, isFalse);

      final none = StorageHealth(degraded: true);
      final mem = AppDatabase(
        NativeDatabase.memory().interceptWith(WriteWatch(none)),
      );
      addTearDown(mem.close);
      final kv = await DriftKeyValueStore.load(mem);
      expect(none.notSaving.value, isFalse); // reading is fine
      await kv.setBool('x', value: true);
      expect(none.notSaving.value, isTrue);
    });
  });

  group('the notice', () {
    Future<StorageHealth> pump(
      WidgetTester t, {
      Locale locale = const Locale('en'),
      StorageHealth? health,
    }) async {
      final h = health ?? StorageHealth();
      addTearDown(h.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: [storageHealthProvider.overrideWithValue(h)],
          child: MaterialApp(
            theme: IsharaTheme.build(
              brightness: Brightness.light,
              isArabic: locale.languageCode == 'ar',
            ),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => StorageNotice(child: child!),
            home: Scaffold(
              body: TextButton(
                key: const ValueKey('sos'),
                onPressed: () {},
                child: const Text('SOS'),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      return h;
    }

    testWidgets('shows once per session when a write fails, is announced, '
        'and never takes a tap', (t) async {
      final semantics = t.ensureSemantics();
      final h = await pump(t);
      expect(find.text(_en), findsNothing);
      h.writeFailed(StateError('full'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(_en), findsOneWidget);
      // the screen under it still works
      await t.tap(find.byKey(const ValueKey('sos')));
      await t.pump(StorageNotice.shown);
      await t.pump(const Duration(seconds: 1));
      final opacity = t.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text(_en),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0);
      // a later failure doesn't show it again
      h.writeFailed(StateError('again'));
      await t.pump(const Duration(seconds: 1));
      expect(
        t
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.text(_en),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
      semantics.dispose();
    });

    testWidgets('a write that failed before the first frame (the migration) '
        'shows it too, in Arabic', (t) async {
      final h = StorageHealth()..writeFailed(StateError('full'));
      await pump(t, locale: const Locale('ar'), health: h);
      await t.pump(const Duration(milliseconds: 400));
      expect(
        find.text(
          'مساحة الموبايل خلصت، فإشارة مش قادر يحفظ التغييرات الجديدة. '
          'فضّي شوية مساحة.',
        ),
        findsOneWidget,
      );
      await t.pump(StorageNotice.shown);
    });
  });
}
