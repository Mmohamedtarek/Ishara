import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/sync/outbox.dart';
import 'package:ishara_app/core/sync/remote_store.dart';
import 'package:ishara_app/core/sync/sync_engine.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';
import 'package:logging/logging.dart';

import 'sync_test_support.dart';

void main() {
  late FakeRemoteServer server;
  setUp(() => server = FakeRemoteServer());
  tearDown(() => server.dispose());

  Map<String, Object?>? at(String path) => server.docs[path];

  group('the verification gate (Q-B3)', () {
    test('a guest or an unverified account syncs nothing; verified, the '
        "phone's data goes up once", () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.phrases.star('Where is the pharmacy?');
      await p.activity.append(p.event('hello'));
      await p.prefs.setString('settings.theme', 'dark');
      await p.settle();
      expect(server.writes, isEmpty);
      expect(p.engine.state.value, SyncState.off);

      await p.signIn(aliceUnverified);
      expect(server.writes, isEmpty);
      expect(p.engine.state.value, SyncState.off);

      await p.signIn(alice);
      final id = p.phrases.phrases.single.id;
      expect(at('users/alice')?['displayName'], 'Alice');
      expect(at('users/alice/phrases/$id')?['text'], 'Where is the pharmacy?');
      expect(at('users/alice/activity/a-e1')?['label'], 'hello');
      expect(at('users/alice/activity/a-e1')?.containsKey('id'), isFalse);
      expect(at('users/alice/settings/app')?['theme'], 'dark');
      expect(await p.outboxCount(), 0);
      expect(p.engine.state.value, SyncState.synced);
    });
  });

  group('what syncs (Q-B4)', () {
    test('never conversations, emergency contacts, the glove or developer '
        'mode', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      final talk = LocalConversationRepository(
        p.db,
        MemoryKeyValueStore(),
        gap: () => const Duration(minutes: 10),
      );
      addTearDown(talk.dispose);
      await talk.add(
        TalkMessage(side: MessageSide.me, text: 'secret', at: DateTime(2026)),
      );
      final sos = LocalEmergencyContactsRepository(p.db);
      addTearDown(sos.dispose);
      await sos.add(const EmergencyContact(name: 'M', phone: '+2010'));
      await p.prefs.setString('glove.id', 'AA:BB');
      await p.prefs.setBool('settings.developer', value: true);
      await p.prefs.setBool('settings.vibrate', value: true);
      await p.signIn(alice);
      expect(server.docs.keys.toSet(), {
        'users/alice',
        'users/alice/settings/app',
      });
      expect(at('users/alice/settings/app')!.keys.toSet(), {
        'updatedAt',
        'vibrate',
      });
    });
  });

  group('two phones on one account', () {
    test(
      'both offline, then online: phrases and Learn merge with no loss',
      () async {
        final a = await Phone(server, deviceId: 'a').boot();
        final b = await Phone(server, deviceId: 'b').boot();
        await a.signIn(alice);
        await b.signIn(alice);
        a.fakeRemote.offline = true;
        b.fakeRemote.offline = true;
        await a.phrases.star('from A');
        await a.activity.append(a.event('hello'));
        await a.activity.append(a.event('thanks'));
        await b.phrases.star('from B');
        await b.activity.append(b.event('yes'));
        await a.settle();
        await b.settle();
        expect(await a.outboxCount(), 3);
        expect(a.engine.state.value, SyncState.pending);
        a.fakeRemote.offline = false;
        b.fakeRemote.offline = false;
        await a.engine.flush();
        await b.engine.flush();
        await a.settle();
        await b.settle();
        for (final p in [a, b]) {
          expect(p.phrases.phrases.map((x) => x.text).toSet(), {
            'from A',
            'from B',
          });
          expect(p.activity.events.map((e) => e.label).toSet(), {
            'hello',
            'thanks',
            'yes',
          });
          expect(await p.outboxCount(), 0);
        }
      },
    );

    test('the same phrase changed on both: the later change wins; a delete '
        'made offline is not brought back', () async {
      var t = DateTime.utc(2026, 10, 17, 9);
      DateTime tick() => t = t.add(const Duration(minutes: 1));
      final a = await Phone(server, deviceId: 'a', now: tick).boot();
      final b = await Phone(server, deviceId: 'b', now: tick).boot();
      await a.signIn(alice);
      await b.signIn(alice);
      await a.phrases.star('hello there');
      await a.settle();
      await b.settle();
      expect(b.phrases.find('hello there'), isNotNull);
      // B (offline) unstars at 09:03; A stars it again... no: A changes
      // nothing; B's tombstone is newer and wins when it arrives
      b.fakeRemote.offline = true;
      await b.phrases.unstar('hello there');
      b.fakeRemote.offline = false;
      await b.engine.flush();
      await a.settle();
      await b.settle();
      expect(a.phrases.find('hello there'), isNull);
      // an older copy arriving later doesn't revive it
      final id = a.phrases.all.single.id;
      await a.phrases.applyRemote([
        a.phrases.all.single.copyWith(
          deleted: false,
          at: DateTime.utc(2026, 10, 17, 9, 1, 30),
        ),
      ]);
      expect(a.phrases.find('hello there'), isNull);
      expect(server.docs['users/alice/phrases/$id']?['deleted'], isTrue);
    });

    test('settings: last writer wins for the whole document', () async {
      final a = await Phone(server, deviceId: 'a').boot();
      final b = await Phone(server, deviceId: 'b').boot();
      await a.signIn(alice);
      await b.signIn(alice);
      await withClock(Clock.fixed(DateTime.utc(2026, 10, 17, 10)), () async {
        await a.prefs.setString('settings.theme', 'dark');
      });
      await withClock(Clock.fixed(DateTime.utc(2026, 10, 17, 11)), () async {
        await b.prefs.setString('settings.theme', 'light');
        await b.prefs.setBool('settings.bigText', value: true);
      });
      await a.engine.flush();
      await b.engine.flush();
      await a.settle();
      await b.settle();
      for (final p in [a, b]) {
        expect(p.prefs.getString('settings.theme'), 'light');
        expect(p.prefs.getBool('settings.bigText'), isTrue);
      }
      expect(a.settingsApplied, greaterThan(0));
      expect(at('users/alice/settings/app')?['theme'], 'light');
    });

    test('the same text starred on both phones while offline is kept once, '
        'the same on both', () async {
      final a = await Phone(server, deviceId: 'a').boot();
      final b = await Phone(server, deviceId: 'b').boot();
      await a.signIn(alice);
      await b.signIn(alice);
      a.fakeRemote.offline = true;
      b.fakeRemote.offline = true;
      await a.phrases.star('I need help');
      await b.phrases.star('I need help');
      a.fakeRemote.offline = false;
      b.fakeRemote.offline = false;
      for (var i = 0; i < 2; i++) {
        await a.engine.flush();
        await b.engine.flush();
        await a.settle();
        await b.settle();
      }
      expect(a.phrases.phrases.single.id, b.phrases.phrases.single.id);
      final live = server.docs.entries.where(
        (e) => e.key.contains('/phrases/') && e.value['deleted'] == false,
      );
      expect(live, hasLength(1));
    });
  });

  group('signing in to an existing account on a phone with guest data '
      '(S10-5: merge, account settings win)', () {
    test('guest phrases and Learn join the account; the account settings '
        "replace the guest's", () async {
      final a = await Phone(server, deviceId: 'a').boot();
      await a.signIn(alice);
      await a.prefs.setString('settings.theme', 'dark');
      await a.phrases.star('account phrase');
      await a.activity.append(a.event('hello'));
      await a.settle();

      final guest = await Phone(server, deviceId: 'g').boot();
      await guest.prefs.setString('settings.theme', 'light');
      await guest.phrases.star('guest phrase');
      await guest.phrases.star('account phrase');
      await guest.activity.append(guest.event('yes'));
      await guest.signIn(alice);
      await guest.engine.flush();
      await guest.settle();
      await a.settle();
      expect(guest.prefs.getString('settings.theme'), 'dark');
      expect(at('users/alice/settings/app')?['theme'], 'dark');
      for (final p in [a, guest]) {
        expect(p.phrases.phrases.map((x) => x.text).toList()..sort(), [
          'account phrase',
          'guest phrase',
        ]);
        expect(p.activity.events.map((e) => e.label).toSet(), {'hello', 'yes'});
      }
    });

    test('a new account (no settings yet) takes the phone settings', () async {
      final g = await Phone(server, deviceId: 'g').boot();
      await g.prefs.setString('settings.language', 'ar');
      await g.signIn(alice);
      expect(at('users/alice/settings/app')?['uiLang'], 'ar');
      expect(g.prefs.getString('settings.language'), 'ar');
    });
  });

  group('the outbox', () {
    test('offline: retried with growing backoff; online again: sent', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.signIn(alice);
      p.fakeRemote.offline = true;
      await p.phrases.star('x');
      await p.settle();
      var row = (await p.db.select(p.db.outbox).get()).single;
      expect(row.attempts, 1);
      expect(row.lastError, 'network');
      final first = row.nextAttemptUs - row.queuedAtUs;
      // (offline, nothing goes before the retry time; flush tries now)
      expect(await p.engine.flush(limit: const Duration(seconds: 2)), isFalse);
      row = (await p.db.select(p.db.outbox).get()).single;
      expect(row.attempts, 2);
      expect(row.nextAttemptUs - row.queuedAtUs, greaterThan(first));
      p.fakeRemote.offline = false;
      expect(await p.engine.flush(), isTrue);
      expect(
        server.docs.keys.where((k) => k.contains('/phrases/')),
        isNotEmpty,
      );
    });

    test('a change made while its document is being sent goes again', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.signIn(alice);
      await p.phrases.star('x');
      await p.phrases.unstar('x');
      await p.engine.flush();
      final id = p.phrases.all.single.id;
      expect(at('users/alice/phrases/$id')?['deleted'], isTrue);
    });

    test(
      'a Learn event already up (its answer was lost) counts as sent',
      () async {
        final p = await Phone(server, deviceId: 'a').boot();
        await p.signIn(alice);
        final e = p.event('hello');
        server.docs['users/alice/activity/${e.id}'] = {'v': 1};
        await p.activity.append(e);
        expect(await p.engine.flush(), isTrue);
        expect(server.docs['users/alice/activity/${e.id}'], {'v': 1});
      },
    );

    test(
      'a refusal (not the network) is retried later, the rest goes on',
      () async {
        final p = await Phone(server, deviceId: 'a').boot();
        await p.signIn(alice);
        p.fakeRemote
          ..failNext = RemoteProblem.denied
          ..failCount = 1;
        await p.phrases.star('first');
        await p.phrases.star('second');
        await p.settle();
        final rows = await p.db.select(p.db.outbox).get();
        expect(rows, hasLength(1));
        expect(rows.single.lastError, 'denied');
      },
    );
  });

  group('review fixes', () {
    test(
      'a write refused three times is parked: kept on the phone, shown, '
      'logged with its path and code; tried again at the next start',
      () async {
        final logs = <LogRecord>[];
        final sub = Logger.root.onRecord.listen(logs.add);
        addTearDown(sub.cancel);
        final p = await Phone(server, deviceId: 'a').boot();
        await p.signIn(alice);
        p.fakeRemote
          ..failNext = RemoteProblem.denied
          ..failCount = 3;
        await p.phrases.star('refused');
        final id = p.phrases.all.single.id;
        for (var i = 0; i < 3; i++) {
          await p.db
              .update(p.db.outbox)
              .write(const OutboxCompanion(nextAttemptUs: Value(0)));
          await p.engine.push();
        }
        final row = (await p.db.select(p.db.outbox).get()).single;
        expect(row.nextAttemptUs, SyncEngine.parkedUs);
        expect(row.attempts, 3);
        await p.settle();
        expect(p.engine.state.value, SyncState.parked);
        expect(p.phrases.find('refused'), isNotNull); // never dropped
        final parked = logs.where(
          (r) =>
              r.object is LogEvent &&
              (r.object! as LogEvent).event == 'write_parked',
        );
        expect(parked, hasLength(1));
        final fields = (parked.single.object! as LogEvent).toJson();
        expect(fields['path'], 'users/{uid}/phrases/$id');
        expect('$fields', isNot(contains('alice'))); // no account id
        expect(fields['code'], isNotNull);
        expect('$fields', isNot(contains('refused'))); // no content logged
        // flush leaves it parked and says not all is sent
        expect(await p.engine.flush(), isFalse);
        // the next start tries it again (the account accepts it now)
        await p.engine.dispose();
        final again = SyncEngine(
          db: p.db,
          remote: p.remote,
          auth: p.auth,
          phrases: p.phrases,
          activity: p.activity,
          prefs: p.prefs,
          onSettingsApplied: () {},
          debounce: Duration.zero,
        )..start();
        addTearDown(again.dispose);
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        await again.push();
        expect(at('users/alice/phrases/$id')?['text'], 'refused');
        expect(await p.outboxCount(), 0);
      },
    );

    test('offline: one try, then nothing until the retry time (not every '
        'row in turn)', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.signIn(alice);
      p.fakeRemote.offline = true;
      var tries = 0;
      p.fakeRemote.onCall = () => tries++;
      await p.phrases.star('a');
      await p.phrases.star('b');
      await p.phrases.star('c');
      await p.settle();
      await p.engine.push();
      await p.engine.push();
      expect(tries, 1);
      final rows = await p.db.select(p.db.outbox).get();
      expect(rows.where((r) => r.attempts > 0), hasLength(1));
      // online again: flush sends everything at once
      p.fakeRemote.offline = false;
      expect(await p.engine.flush(), isTrue);
    });

    test('flush waits for a push already under way', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.signIn(alice);
      final slow = Completer<void>();
      p.fakeRemote.beforeSet = () => slow.future;
      await p.phrases.star('slow');
      final running = p.engine.push();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final flushed = p.engine.flush();
      slow.complete();
      await running;
      expect(await flushed, isTrue);
    });

    test('a name over 100 characters is cut in the profile; a refused '
        'profile never stops the sync', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.phrases.star('x');
      await p.signIn(
        AuthUser(
          id: 'alice',
          email: 'a@b.co',
          name: 'N' * 150,
          emailVerified: true,
        ),
      );
      expect(at('users/alice')?['displayName'], 'N' * 100);

      final q = await Phone(server, deviceId: 'b').boot();
      q.fakeRemote.refuse = (path) => path == 'users/bob';
      await q.phrases.star('y');
      await q.signIn(bob);
      expect(q.engine.state.value, SyncState.synced);
      expect(
        server.docs.keys.where((k) => k.startsWith('users/bob/phrases/')),
        hasLength(1),
      );
    });

    test(
      'a clock set back: updatedAt goes up no earlier than createdAt',
      () async {
        var t = DateTime.utc(2026, 10, 17, 12);
        final p = await Phone(server, deviceId: 'a', now: () => t).boot();
        await p.signIn(alice);
        await p.phrases.star('x');
        t = DateTime.utc(2026, 10, 17, 11); // clock went back
        await p.phrases.unstar('x');
        await p.engine.flush();
        final doc = at('users/alice/phrases/${p.phrases.all.single.id}')!;
        expect(
          (doc['updatedAt']! as DateTime).isBefore(
            doc['createdAt']! as DateTime,
          ),
          isFalse,
        );
        expect(doc['deleted'], isTrue);
      },
    );

    test(
      'a live listener that fails starts again (with a fresh download)',
      () async {
        final a = await Phone(server, deviceId: 'a').boot();
        final b = await Phone(server, deviceId: 'b').boot();
        await a.signIn(alice);
        await b.signIn(alice);
        a.fakeRemote.breakListeners();
        await b.phrases.star('after the break');
        await b.engine.flush();
        // the retry waits a backoff (2 s and a bit); let it pass
        await Future<void>.delayed(const Duration(seconds: 3));
        await a.settle();
        expect(a.phrases.find('after the break'), isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test(
      'a pull retry survives a push that ends meanwhile (two timers)',
      () async {
        final a = await Phone(server, deviceId: 'a').boot();
        final b = await Phone(server, deviceId: 'b').boot();
        await a.signIn(alice);
        await b.signIn(alice);
        // a push is under way and held...
        final gate = Completer<void>();
        a.fakeRemote.beforeSet = () => gate.future;
        await a.phrases.star('held');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // ...when the listeners fail (a pull retry is set)
        a.fakeRemote.breakListeners();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // the push then fails offline, so it sets its own retry time
        a.fakeRemote
          ..beforeSet = null
          ..failNext = RemoteProblem.network;
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await b.phrases.star('after the break');
        await b.engine.flush();
        // the pull retry (2 s and a bit) must still come
        await Future<void>.delayed(const Duration(seconds: 3));
        await a.settle();
        expect(a.phrases.find('after the break'), isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test('suspend waits for a write under way, so none lands after the '
        "deletion's deletes; resume follows the user again", () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.signIn(alice);
      final gate = Completer<void>();
      p.fakeRemote.beforeSet = () => gate.future;
      await p.phrases.star('in flight');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      var suspended = false;
      final s = p.engine.suspend().then((_) => suspended = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(suspended, isFalse); // the write hasn't landed yet
      p.fakeRemote.beforeSet = null;
      gate.complete();
      await s;
      final landed = server.docs.keys
          .where((k) => k.startsWith('users/alice/phrases/'))
          .toList();
      expect(landed, hasLength(1)); // landed before suspend returned
      // a new account after the deletion syncs (no restart needed)
      p.auth.setUser(null);
      await p.engine.resume();
      await p.signIn(bob);
      await p.phrases.star('bob after');
      await p.settle();
      expect(
        server.docs.keys.where((k) => k.startsWith('users/bob/phrases/')),
        hasLength(1), // only bob's: alice's phrase never goes up into his
      );
      expect(p.phrases.find('bob after'), isNotNull);
    });

    test('a push error that is not the server answer backs off, never '
        'escapes; the write goes later', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.signIn(alice);
      var throws = 1;
      p.fakeRemote.beforeSet = () async {
        if (throws-- > 0) throw StateError('encoding');
      };
      await p.phrases.star('later');
      await p.settle(); // (an escaped error would fail this test)
      expect(server.docs.keys.where((k) => k.contains('/phrases/')), isEmpty);
      expect(await p.engine.flush(), isTrue); // flush makes it due at once
      expect(
        server.docs.keys.where((k) => k.contains('/phrases/')),
        hasLength(1),
      );
    });

    test('suspended (account deletion): nothing more goes up', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.signIn(alice);
      await p.engine.suspend();
      await p.phrases.star('after');
      await p.settle();
      expect(server.docs.keys.where((k) => k.contains('/phrases/')), isEmpty);
      expect(p.engine.state.value, SyncState.off);
    });
  });

  group('phrases over 500 characters stay on the phone (user 2026-11-27)', () {
    test("the 500 is the rules' own, counted like String.length", () {
      final rules = File('../../firebase/firestore.rules').readAsStringSync();
      expect(rules, contains('isText(data().text, ${Synced.phraseMaxLength})'));
      expect(Synced.phraseFits('x' * 500), isTrue);
      expect(Synced.phraseFits('x' * 501), isFalse);
      expect(Synced.phraseFits('ش' * 500), isTrue);
      expect(Synced.phraseFits('\u{1F44B}' * 250), isTrue); // 500 units
      expect(Synced.phraseFits('\u{1F44B}' * 251), isFalse);
    });

    test('starred and kept, never queued or sent; sign-out has nothing '
        'waiting; 500 still syncs', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.signIn(alice);
      final long = 'a' * 501;
      final arabic = 'ش' * 500;
      await p.phrases.star(long);
      await p.phrases.star(arabic);
      await p.settle();
      expect(p.phrases.find(long), isNotNull);
      final sent = [
        for (final e in server.docs.entries)
          if (e.key.startsWith('users/alice/phrases/')) e.value['text'],
      ];
      expect(sent, [arabic]);
      expect(await p.outboxCount(), 0);
      expect(await p.engine.flush(), isTrue); // no "not uploaded" warning
      expect(p.engine.state.value, SyncState.synced);
      // unstarring it is local too
      await p.phrases.unstar(long);
      expect(await p.outboxCount(), 0);
    });

    test("a guest's long phrase doesn't join the account; a row queued "
        'before this check is dropped, not sent', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      final long = 'b' * 600;
      await p.phrases.star(long);
      await p.phrases.star('short');
      final id = p.phrases.find(long)!.id;
      await enqueue(p.db, Synced.phrases, id); // as an older version did
      await p.signIn(alice);
      await p.settle();
      final texts = [
        for (final e in server.docs.entries)
          if (e.key.startsWith('users/alice/phrases/')) e.value['text'],
      ];
      expect(texts, ['short']);
      expect(await p.outboxCount(), 0);
      expect(p.engine.state.value, SyncState.synced); // never parked
      expect(p.phrases.find(long), isNotNull);
    });
  });

  group('sign-out and other accounts (S10-6)', () {
    test("clearing removes the account's phrases and Learn, keeps settings "
        'and the rest', () async {
      final p = await Phone(server, deviceId: 'a').boot();
      await p.signIn(alice);
      await p.phrases.star('x');
      await p.activity.append(p.event('hello'));
      await p.prefs.setString('settings.theme', 'dark');
      await p.engine.flush();
      await p.signIn(null);
      await p.engine.clearSyncedData();
      expect(p.phrases.all, isEmpty);
      expect(p.activity.events, isEmpty);
      expect(await p.db.select(p.db.phrases).get(), isEmpty);
      expect(await p.db.select(p.db.activityEntries).get(), isEmpty);
      expect(await p.outboxCount(), 0);
      expect(p.prefs.getString('settings.theme'), 'dark');
      // the account still has everything
      expect(
        server.docs.keys.where((k) => k.contains('/activity/')),
        hasLength(1),
      );
    });

    test('sign-out: a snapshot that arrives before the clear runs never '
        "brings the account's phrases back", () async {
      final a = await Phone(server, deviceId: 'a').boot();
      final b = await Phone(server, deviceId: 'b').boot();
      await a.signIn(alice);
      await b.signIn(alice);
      // a's queue is busy (a slow job), sign-out's clear waits behind it
      final hold = Completer<void>();
      unawaited(a.engine.runSerial(() => hold.future));
      await a.auth.signOut();
      final cleared = a.engine.clearSyncedData();
      // meanwhile the account changes: a's listener queues the snapshot
      await b.phrases.star('from the other phone');
      await b.engine.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      hold.complete();
      await cleared;
      await a.settle();
      expect(a.phrases.all, isEmpty);
      expect(await a.outboxCount(), 0);
    });

    test(
      "another account's data on the phone never goes up into this one",
      () async {
        final p = await Phone(server, deviceId: 'a').boot();
        await p.signIn(alice);
        await p.phrases.star('alice only');
        await p.engine.flush();
        // (sign-out would have cleared it; here it wasn't)
        p.auth.setUser(null);
        await p.settle();
        await p.signIn(bob);
        expect(
          server.docs.keys.where((k) => k.startsWith('users/bob/phrases')),
          isEmpty,
        );
        expect(p.phrases.all, isEmpty);
      },
    );
  });
}
