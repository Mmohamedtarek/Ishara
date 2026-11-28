import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/account/account_deletion.dart';
import 'package:ishara_app/core/account/account_providers.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/device/app_info.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';
import 'package:ishara_app/core/sync/sync_engine.dart';
import 'package:ishara_app/core/sync/sync_providers.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/features/settings/presentation/account_flows.dart';
import 'package:ishara_app/features/settings/presentation/settings_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

import '../support/fake_sos.dart';
import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// A signed-in account on the fake backend.
Future<FakeAuthRepository> _account({bool verified = false}) async {
  final auth = FakeAuthRepository(delay: Duration.zero);
  await auth.createAccount(
    name: 'Alice',
    email: 'alice@example.com',
    password: 'secret123',
  );
  if (verified) {
    auth.verify('alice@example.com');
    await auth.refreshUser();
  }
  return auth;
}

Future<(Harness, ProviderContainer)> _settings(
  WidgetTester t, {
  required FakeAuthRepository auth,
  AppLanguage language = AppLanguage.en,
  List<Override> extra = const [],
}) async {
  addTearDown(rootBundle.clear);
  final talk = TalkFakes();
  addTearDown(talk.feed.dispose);
  final h = await pumpScreen(
    t,
    const SettingsScreen(),
    language: language,
    harness: Harness(
      store: MemoryKeyValueStore({'setup.spoken': 'en'}),
      auth: auth,
    ),
    overrides: [
      ...talk.overrides,
      ...SosFakes().overrides,
      appVersionProvider.overrideWithValue(const AsyncData('1.0.0 (1)')),
      ...extra,
    ],
  );
  return (h, ProviderScope.containerOf(t.element(find.byType(Scaffold).first)));
}

Future<void> _scrollTo(WidgetTester t, String key) async {
  final built = find.byKey(ValueKey(key), skipOffstage: false);
  if (built.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      find.byKey(ValueKey(key)),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('settings-body')),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

/// Drains the 2.4 s toast.
Future<void> _toastGone(WidgetTester t) => t.pump(const Duration(seconds: 3));

void main() {
  group('email not verified yet (Q-B3)', () {
    testWidgets('the note, Resend with its 60 s wait, "I\'ve verified" '
        'before and after the link', (t) async {
      final auth = await _account();
      addTearDown(auth.dispose);
      await _settings(t, auth: auth);
      expect(
        find.text(
          'Verify your email to keep your progress in your account. We sent '
          'you a link.',
        ),
        findsOneWidget,
      );
      await t.tap(_key('verify-resend'));
      await t.pump();
      expect(auth.verificationsSent, ['alice@example.com']);
      expect(find.text('Email sent. Check your inbox.'), findsOneWidget);
      expect(find.text('Resend in 60 s'), findsOneWidget);
      await t.tap(_key('verify-resend'));
      await t.pump();
      expect(auth.verificationsSent, hasLength(1)); // waiting
      await t.pump(const Duration(seconds: 60));
      expect(find.text('Resend email'), findsOneWidget);
      await _toastGone(t);

      await t.tap(_key('verify-check'));
      await t.pump();
      expect(
        find.text('Not verified yet. Open the link in the email first.'),
        findsOneWidget,
      );
      await _toastGone(t);
      auth.verify('alice@example.com');
      await t.tap(_key('verify-check'));
      await t.pump();
      await t.pump();
      expect(
        find.text('Email verified. Your progress now syncs.'),
        findsOneWidget,
      );
      expect(_key('settings-verify'), findsNothing);
      await _toastGone(t);
    });

    testWidgets('Arabic, and the buttons work with TalkBack', (t) async {
      final semantics = t.ensureSemantics();
      final auth = await _account();
      addTearDown(auth.dispose);
      await _settings(t, auth: auth, language: AppLanguage.ar);
      expect(
        find.text(
          'أكّد إيميلك عشان تقدّمك يتحفظ في حسابك. بعتنالك لينك على الإيميل.',
        ),
        findsOneWidget,
      );
      for (final label in ['ابعت الإيميل تاني', 'أكّدت خلاص']) {
        expect(
          t.getSemantics(find.bySemanticsLabel(label)),
          matchesSemantics(
            label: label,
            isButton: true,
            hasTapAction: true,
            isEnabled: true,
            hasEnabledState: true,
            isFocusable: true,
            hasFocusAction: true,
          ),
          reason: label,
        );
      }
      semantics.dispose();
    });

    testWidgets('a network problem on Resend says so, never raw', (t) async {
      final auth = await _account();
      addTearDown(auth.dispose);
      await _settings(t, auth: auth);
      auth.failNext = AuthProblem.network;
      await t.tap(_key('verify-resend'));
      await t.pump();
      expect(
        find.text('No internet connection. Check it and try again.'),
        findsOneWidget,
      );
      expect(find.text('Resend email'), findsOneWidget); // no wait started
      await _toastGone(t);
    });
  });

  group('the sync line (S10-8)', () {
    testWidgets('verified: "Synced" or "Not synced yet", read out when it '
        'changes', (t) async {
      final auth = await _account(verified: true);
      addTearDown(auth.dispose);
      final state = ValueNotifier(SyncState.synced);
      addTearDown(state.dispose);
      await _settings(
        t,
        auth: auth,
        extra: [syncStateProvider.overrideWithValue(state)],
      );
      expect(_key('settings-verify'), findsNothing);
      expect(find.text('Synced with your account'), findsOneWidget);
      state.value = SyncState.pending;
      await t.pump();
      expect(
        find.text(
          "Not synced yet. Your changes will upload when you're online.",
        ),
        findsOneWidget,
      );
      final live = find.ancestor(
        of: find.textContaining('Not synced yet'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
      );
      expect(live, findsOneWidget);
      state.value = SyncState.off;
      await t.pump();
      expect(_key('settings-sync'), findsNothing);
    });
  });

  group('sign out (S10-6)', () {
    testWidgets("changes that can't upload: asks first; Cancel keeps you "
        'signed in; Sign out anyway clears', (t) async {
      final auth = await _account(verified: true);
      addTearDown(auth.dispose);
      final sync = _Sync(allSent: false);
      final (h, c) = await _settings(
        t,
        auth: auth,
        extra: [syncControlProvider.overrideWithValue(sync)],
      );
      await _scrollTo(t, 'settings-sign-out');
      await t.tap(_key('settings-sign-out'));
      await t.pumpAndSettle();
      expect(sync.flushed, 1);
      expect(_key('sign-out-unsynced'), findsOneWidget);
      expect(find.text('Sign out anyway?'), findsOneWidget);
      expect(
        find.text(
          "Some changes haven't uploaded yet. If you sign out now, they'll be "
          'lost.',
        ),
        findsOneWidget,
      );
      await t.tap(_key('sign-out-cancel'));
      await t.pumpAndSettle();
      expect(auth.currentUser, isNotNull);
      expect(sync.cleared, 0);
      expect(h.location, '/screen');

      await t.tap(_key('settings-sign-out'));
      await t.pumpAndSettle();
      await t.tap(_key('sign-out-anyway'));
      await t.pumpAndSettle();
      expect(auth.currentUser, isNull);
      expect(sync.cleared, 1);
      expect(h.location, '/welcome');
      expect(c.read(syncControlProvider), same(sync));
      await _toastGone(t);
    });

    testWidgets('everything up: signs out at once and clears', (t) async {
      final auth = await _account(verified: true);
      addTearDown(auth.dispose);
      final sync = _Sync(allSent: true);
      final (h, _) = await _settings(
        t,
        auth: auth,
        extra: [syncControlProvider.overrideWithValue(sync)],
      );
      await _scrollTo(t, 'settings-sign-out');
      await t.tap(_key('settings-sign-out'));
      await t.pumpAndSettle();
      expect(_key('sign-out-unsynced'), findsNothing);
      expect(auth.currentUser, isNull);
      expect(sync.cleared, 1);
      expect(h.location, '/welcome');
      await _toastGone(t);
    });

    testWidgets('a guest signs out without the sync', (t) async {
      final auth = FakeAuthRepository(delay: Duration.zero);
      addTearDown(auth.dispose);
      final sync = _Sync(allSent: false);
      final (h, _) = await _settings(
        t,
        auth: auth,
        extra: [syncControlProvider.overrideWithValue(sync)],
      );
      await _scrollTo(t, 'settings-sign-out');
      await t.tap(_key('settings-sign-out'));
      await t.pumpAndSettle();
      expect(sync.flushed, 0);
      expect(sync.cleared, 0);
      expect(h.location, '/welcome');
      await _toastGone(t);
    });

    testWidgets('email not verified: says the data stays on the phone; '
        'never flushes, keeps the phrases', (t) async {
      final auth = await _account(); // not verified
      addTearDown(auth.dispose);
      final sync = _Sync(allSent: false);
      final (h, c) = await _settings(
        t,
        auth: auth,
        extra: [syncControlProvider.overrideWithValue(sync)],
      );
      await c.read(savedPhrasesRepositoryProvider).star('hello');
      await _scrollTo(t, 'settings-sign-out');
      await t.tap(_key('settings-sign-out'));
      await t.pumpAndSettle();
      expect(_key('sign-out-unverified'), findsOneWidget);
      expect(
        find.text(
          "Your email isn't verified yet, so your phrases and Learn progress "
          "aren't in your account. They'll stay on this phone.",
        ),
        findsOneWidget,
      );
      await t.tap(_key('sign-out-cancel'));
      await t.pumpAndSettle();
      expect(auth.currentUser, isNotNull);
      await t.tap(_key('settings-sign-out'));
      await t.pumpAndSettle();
      await t.tap(_key('sign-out-anyway'));
      await t.pumpAndSettle();
      expect(auth.currentUser, isNull);
      expect(sync.flushed, 0);
      expect(sync.cleared, 0);
      expect(
        c.read(savedPhrasesRepositoryProvider).phrases.single.text,
        'hello',
      );
      expect(h.location, '/welcome');
      await _toastGone(t);
    });
  });

  group('delete account (Q-B1)', () {
    Future<void> open(WidgetTester t) async {
      await _scrollTo(t, 'settings-delete-account');
      await t.tap(_key('settings-delete-account'));
      await t.pumpAndSettle();
    }

    testWidgets('a guest has no Delete account', (t) async {
      final auth = FakeAuthRepository(delay: Duration.zero);
      addTearDown(auth.dispose);
      await _settings(t, auth: auth);
      expect(
        find.byKey(
          const ValueKey('settings-delete-account'),
          skipOffstage: false,
        ),
        findsNothing,
      );
    });

    testWidgets('confirm with the email: the button waits for it; then the '
        'account and the phone data go, back to Welcome', (t) async {
      final auth = await _account(verified: true);
      addTearDown(auth.dispose);
      final (h, c) = await _settings(t, auth: auth);
      await c
          .read(conversationRepositoryProvider)
          .add(
            TalkMessage(side: MessageSide.me, text: 'hi', at: DateTime(2026)),
          );
      await open(t);
      expect(
        find.textContaining('This deletes alice@example.com'),
        findsOneWidget,
      );
      final go = t.widget<TextButton>(_key('delete-go'));
      expect(go.onPressed, isNull);
      await t.enterText(_key('delete-email'), 'Alice@Example.com ');
      await t.pump();
      expect(t.widget<TextButton>(_key('delete-go')).onPressed, isNotNull);
      await t.tap(_key('delete-go'));
      await t.pumpAndSettle();
      // the password first, every time (Q-B1, user 2026-11-27)
      expect(find.text('Enter your password'), findsOneWidget);
      expect(auth.currentUser, isNotNull);
      await t.enterText(_key('delete-password-field'), 'secret123');
      await t.pump();
      // the account call takes a moment: N18 beside the spinner meanwhile
      auth.delay = const Duration(seconds: 1);
      await t.tap(_key('delete-password-go'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pump();
      expect(find.text('Deleting your account…'), findsOneWidget);
      // two account calls (the password, then the deletion), 1 s each
      for (var i = 0; i < 2; i++) {
        await t.pump(const Duration(seconds: 1));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await t.pump();
      }
      await t.pump();
      expect(find.text('Your account was deleted.'), findsOneWidget);
      expect(h.location, '/welcome');
      expect(auth.currentUser, isNull);
      expect(c.read(conversationRepositoryProvider).messages, isEmpty);
      await _toastGone(t);
    });

    testWidgets('Cancel deletes nothing', (t) async {
      final auth = await _account(verified: true);
      addTearDown(auth.dispose);
      await _settings(t, auth: auth);
      await open(t);
      await t.tap(_key('delete-cancel'));
      await t.pumpAndSettle();
      expect(auth.currentUser, isNotNull);
    });

    testWidgets('Cancel at the password deletes nothing (nothing pending, '
        'the sync not stopped)', (t) async {
      final auth = await _account(verified: true);
      addTearDown(auth.dispose);
      final (h, c) = await _settings(t, auth: auth);
      await open(t);
      await t.enterText(_key('delete-email'), 'alice@example.com');
      await t.pump();
      await t.tap(_key('delete-go'));
      await t.pumpAndSettle();
      await t.tap(_key('delete-password-cancel'));
      await t.pumpAndSettle();
      expect(_key('delete-password'), findsNothing);
      expect(auth.currentUser, isNotNull);
      expect(h.location, '/screen');
      expect(c.read(accountDeletionControllerProvider), DeletionState.idle);
      final pending = await t.runAsync(
        () => AccountDeletion(
          db: c.read(appDatabaseProvider),
          remote: null,
          auth: auth,
          wipeLocal: () async {},
        ).pending(),
      );
      expect(pending, isNull);
    });

    testWidgets('the password: a wrong one says so and deletes nothing; the '
        'right one finishes', (t) async {
      final auth = await _account(verified: true);
      addTearDown(auth.dispose);
      final (h, _) = await _settings(t, auth: auth);
      await open(t);
      await t.enterText(_key('delete-email'), 'alice@example.com');
      await t.pump();
      await t.runAsync(() async {
        await t.tap(_key('delete-go'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      expect(find.text('Enter your password'), findsOneWidget);
      await t.enterText(_key('delete-password-field'), 'nope');
      await t.pump();
      await t.runAsync(() async {
        await t.tap(_key('delete-password-go'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      await t.pump();
      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(auth.currentUser, isNotNull);
      await _toastGone(t);
      await t.pumpAndSettle();
      await t.enterText(_key('delete-password-field'), 'secret123');
      await t.pump();
      await t.runAsync(() async {
        await t.tap(_key('delete-password-go'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      await t.pump();
      expect(h.location, '/welcome');
      expect(auth.currentUser, isNull);
      await _toastGone(t);
    });

    testWidgets('offline: the password cannot be checked, so nothing starts; '
        'it says so and asks again', (t) async {
      final auth = await _account(verified: true);
      addTearDown(auth.dispose);
      final (h, c) = await _settings(t, auth: auth);
      await open(t);
      await t.enterText(_key('delete-email'), 'alice@example.com');
      await t.pump();
      await t.tap(_key('delete-go'));
      await t.pumpAndSettle();
      await t.enterText(_key('delete-password-field'), 'secret123');
      await t.pump();
      auth.offline = true;
      await t.runAsync(() async {
        await t.tap(_key('delete-password-go'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      await t.pump();
      expect(
        find.text('No internet connection. Check it and try again.'),
        findsOneWidget,
      );
      await _toastGone(t);
      await t.pumpAndSettle();
      expect(_key('delete-password'), findsOneWidget); // asks again
      expect(h.location, '/screen');
      final pending = await t.runAsync(
        () => AccountDeletion(
          db: c.read(appDatabaseProvider),
          remote: null,
          auth: auth,
          wipeLocal: () async {},
        ).pending(),
      );
      expect(pending, isNull);
      expect(auth.currentUser, isNotNull);
    });
  });

  testWidgets('a deletion left pending is finished at the next start', (
    t,
  ) async {
    final auth = await _account(verified: true);
    addTearDown(auth.dispose);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        GoRoute(path: '/welcome', builder: (_, _) => const Text('welcome')),
      ],
    );
    addTearDown(router.dispose);
    final c = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(c.dispose);
    final db = c.read(appDatabaseProvider);
    await t.runAsync(
      () => db
          .into(db.meta)
          .insert(
            MetaCompanion.insert(
              key: AccountDeletion.kPending,
              value: jsonEncode({'uid': auth.currentUser!.id}),
            ),
          ),
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          theme: IsharaTheme.build(
            brightness: Brightness.light,
            isArabic: false,
          ),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => PendingDeletionResumer(child: child!),
        ),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await t.pump();
    await t.pumpAndSettle();
    expect(auth.currentUser, isNull);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/welcome');
    expect(find.text('welcome'), findsOneWidget);
    await _toastGone(t);
  });
}

/// Sign-out's view of the sync (the engine's own tests cover the real
/// flush and clear).
class _Sync implements SyncControl {
  new({required this.allSent});

  final bool allSent;
  int flushed = 0;
  int cleared = 0;

  @override
  Future<bool> flush({Duration limit = Duration.zero}) async {
    flushed++;
    return allSent;
  }

  @override
  Future<void> clearSyncedData() async => cleared++;
}
