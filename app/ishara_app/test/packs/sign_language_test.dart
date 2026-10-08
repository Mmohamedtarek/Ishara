import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/sign_language_picker.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

Widget _host(ProviderContainer c, {Locale locale = const Locale('en')}) =>
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: IsharaTheme.build(
          brightness: Brightness.light,
          isArabic: locale.languageCode == 'ar',
        ),
        home: const Scaffold(body: Center(child: SignLanguagePicker())),
      ),
    );

void main() {
  group('rules', () {
    test('ASL is the default', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(activeSignLanguageProvider), SignLanguage.asl);
      expect(c.read(activePackProvider).language, SignLanguage.asl);
      expect(PackRegistry.defaultLanguage, SignLanguage.asl);
    });

    test('choosing ArSL keeps ASL and changes nothing', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final changes = <SignLanguage>[];
      c.listen(activeSignLanguageProvider, (_, n) => changes.add(n));
      expect(
        c.read(activeSignLanguageProvider.notifier).select(SignLanguage.arsl),
        isFalse,
      );
      expect(c.read(activeSignLanguageProvider), SignLanguage.asl);
      expect(changes, isEmpty);
      expect(
        c.read(activeSignLanguageProvider.notifier).select(SignLanguage.asl),
        isTrue,
      );
    });

    test('a stored or synced "arsl" falls back to ASL without crashing', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(activeSignLanguageProvider.notifier);
      for (final stored in ['arsl', null, '', 'ARSL', 'klingon', 'asl']) {
        n.restore(stored);
        expect(
          c.read(activeSignLanguageProvider),
          SignLanguage.asl,
          reason: '$stored',
        );
        expect(PackRegistry.resolve(stored), SignLanguage.asl);
      }
    });

    test('no feature can load a pack with available: false', () {
      expect(PackRegistry.isAvailable(SignLanguage.arsl), isFalse);
      expect(
        () => PackRegistry.require(SignLanguage.arsl),
        throwsA(
          isA<PackUnavailableFailure>()
              .having((f) => f.language, 'language', SignLanguage.arsl)
              .having((f) => f.kind, 'kind', 'pack_unavailable'),
        ),
      );
      final asl = PackRegistry.require(SignLanguage.asl);
      expect(asl.catalogueAsset, 'assets/packs/asl/signs.json');
      expect(asl.modelDir, 'assets/packs/asl/kit/model');
      expect(asl.mockDir, 'assets/packs/asl/kit/mock');
      expect(asl.avatarLibraryAsset, startsWith('assets/packs/asl/'));
      expect(SignLanguage.tryParse('arsl'), SignLanguage.arsl);
      expect(SignLanguage.arsl.id, 'arsl');
    });
  });

  group('picker', () {
    testWidgets('ArSL first with the badge; ASL selected', (t) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(c));
      final arsl = t.getTopLeft(
        find.byKey(const ValueKey('sign-language-arsl')),
      );
      final asl = t.getTopLeft(find.byKey(const ValueKey('sign-language-asl')));
      // Reading order (the pills may wrap onto two rows).
      expect(
        arsl.dy < asl.dy || (arsl.dy == asl.dy && arsl.dx < asl.dx),
        isTrue,
        reason: 'prototype order: ArSL, then ASL',
      );
      expect(find.text('Coming soon'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sign-language-arsl')),
          matching: find.text('Coming soon'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping ArSL: dialog (EN), OK closes, ASL kept', (t) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(c));
      await t.tap(find.byKey(const ValueKey('sign-language-arsl')));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Egyptian Arabic Sign Language is coming in a future update. '
          'For now, Ishara uses American Sign Language (ASL).',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.read(activeSignLanguageProvider), SignLanguage.asl);
    });

    testWidgets('Arabic: dialog text and تمام button', (t) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(c, locale: const Locale('ar')));
      expect(find.text('قريبًا'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('sign-language-arsl')));
      await t.pumpAndSettle();
      expect(
        find.text(
          'لغة الإشارة المصرية هتكون متاحة في تحديث قريب. '
          'حاليًا Ishara بيستخدم لغة الإشارة الأمريكية (ASL).',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('تمام'));
      await t.pumpAndSettle();
      expect(c.read(activeSignLanguageProvider), SignLanguage.asl);
    });

    testWidgets('a double tap opens one dialog only', (t) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(c));
      final pill = find.byKey(const ValueKey('sign-language-arsl'));
      await t.tap(pill);
      await t.tap(pill, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        t.widget<AlertDialog>(find.byType(AlertDialog)).semanticLabel,
        'Coming soon',
      );
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('accessibility: selected state, badge read out, 48 dp', (
      t,
    ) async {
      final h = t.ensureSemantics();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(c));
      final arsl = t.getSemantics(
        find.byKey(const ValueKey('sign-language-arsl')),
      );
      expect(arsl.label, 'Egyptian Arabic Sign (ArSL), Coming soon');
      final asl = t.getSemantics(
        find.byKey(const ValueKey('sign-language-asl')),
      );
      expect(asl.label, 'American Sign (ASL)');
      expect(
        t.getSize(find.byKey(const ValueKey('sign-language-asl'))).height,
        greaterThanOrEqualTo(48),
      );
      t.semantics.tap(
        find.semantics.byLabel('Egyptian Arabic Sign (ArSL), Coming soon'),
      );
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        t.getSize(find.byKey(const ValueKey('arsl-coming-soon-ok'))).height,
        greaterThanOrEqualTo(48),
      );
      h.dispose();
    });
  });
}
