// Firestore security rules (step 10b), every allowed and every denied case,
// in the Firestore emulator: `npm test` (firebase emulators:exec).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ishara',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const t0 = Timestamp.fromDate(new Date('2026-10-17T09:00:00Z'));
const t1 = Timestamp.fromDate(new Date('2026-10-17T09:05:00Z'));

// Alice, verified; Alice, not verified yet; Bob, verified; nobody.
const alice = () => env.authenticatedContext('alice', { email_verified: true }).firestore();
const aliceUnverified = () =>
  env.authenticatedContext('alice', { email_verified: false }).firestore();
const bob = () => env.authenticatedContext('bob', { email_verified: true }).firestore();
const nobody = () => env.unauthenticatedContext().firestore();

const profile = () => ({ displayName: 'Alice', createdAt: t0, updatedAt: t0, schemaVersion: 1 });
const settings = () => ({
  updatedAt: t1,
  uiLang: 'ar',
  theme: 'dark',
  signLanguage: 'asl',
  spokenLanguage: 'ar',
  who: 'speak',
  avatarId: 'nour',
  signSpeed: 1.5,
  subtitles: true,
  bigText: false,
  highContrast: false,
  vibrate: true,
});
const phrase = () => ({
  text: 'Where is the pharmacy?',
  lang: 'en',
  createdAt: t0,
  updatedAt: t1,
  deleted: false,
});
const quiz = () => ({
  v: 1,
  type: 'quiz',
  label: 'hello',
  moduleId: 'start',
  passed: true,
  prob: null,
  xp: 10,
  day: '2026-10-17',
  at: t0,
  deviceId: '74280c3741ad2ce24d8d33063a3b2c21',
});
const missionDone = () => ({ ...quiz(), type: 'missionDone', label: null, prob: 0.8, xp: 30 });

const paths = {
  profile: ['users/alice', profile],
  settings: ['users/alice/settings/app', settings],
  phrase: ['users/alice/phrases/a1b2c3d4e5f6a7b8c9d0', phrase],
  activity: ['users/alice/activity/e1', quiz],
};

/** Writes [data] at [path] as the rules don't apply (setup). */
const seed = (path, data) =>
  env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), path), data));

describe('the owner, verified', () => {
  for (const [name, [path, make]] of Object.entries(paths)) {
    test(`${name}: create, read, delete`, async () => {
      await assertSucceeds(setDoc(doc(alice(), path), make()));
      await assertSucceeds(getDoc(doc(alice(), path)));
      await assertSucceeds(deleteDoc(doc(alice(), path)));
    });
  }

  test('profile, settings and phrases can change (last writer wins)', async () => {
    for (const [path, make] of [paths.profile, paths.settings, paths.phrase]) {
      await seed(path, make());
      await assertSucceeds(setDoc(doc(alice(), path), { ...make(), updatedAt: t1 }));
    }
    await assertSucceeds(
      updateDoc(doc(alice(), paths.phrase[0]), { deleted: true, updatedAt: t1 }),
    );
  });

  test('settings with only some fields (the rest unset) is fine', async () => {
    await assertSucceeds(
      setDoc(doc(alice(), paths.settings[0]), { updatedAt: t1, theme: 'light' }),
    );
  });

  test('a missionDone event (no label) and a practice event with prob', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/activity/m1'), missionDone()));
    await assertSucceeds(
      setDoc(doc(alice(), 'users/alice/activity/p1'), {
        ...quiz(),
        type: 'practice',
        prob: 0.8734,
        xp: 15,
      }),
    );
    // label may also be left out entirely for missionDone
    const { label, ...noLabel } = missionDone();
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/activity/m2'), noLabel));
  });

  test('can list their own collections', async () => {
    await seed(paths.phrase[0], phrase());
    await assertSucceeds(getDocs(collection(alice(), 'users/alice/phrases')));
    await assertSucceeds(getDocs(collection(alice(), 'users/alice/activity')));
  });
});

describe('activity is append-only', () => {
  test('an existing event can never change', async () => {
    await seed(paths.activity[0], quiz());
    await assertFails(setDoc(doc(alice(), paths.activity[0]), { ...quiz(), xp: 15 }));
    await assertFails(updateDoc(doc(alice(), paths.activity[0]), { passed: false }));
  });

  test('the owner may delete events (account deletion, Q-B1)', async () => {
    await seed(paths.activity[0], quiz());
    await assertSucceeds(deleteDoc(doc(alice(), paths.activity[0])));
  });
});

describe('not verified yet (Q-B3): reads only', () => {
  for (const [name, [path, make]] of Object.entries(paths)) {
    test(`${name}: no create, update or delete; read works`, async () => {
      await assertFails(setDoc(doc(aliceUnverified(), path), make()));
      await seed(path, make());
      await assertSucceeds(getDoc(doc(aliceUnverified(), path)));
      await assertFails(setDoc(doc(aliceUnverified(), path), make()));
      await assertFails(deleteDoc(doc(aliceUnverified(), path)));
    });
  }
});

describe("another user's data", () => {
  for (const [name, [path, make]] of Object.entries(paths)) {
    test(`${name}: Bob can't read, write or delete Alice's`, async () => {
      await seed(path, make());
      await assertFails(getDoc(doc(bob(), path)));
      await assertFails(setDoc(doc(bob(), path), make()));
      await assertFails(deleteDoc(doc(bob(), path)));
    });
  }

  test("Bob can't list Alice's collections or all users", async () => {
    await assertFails(getDocs(collection(bob(), 'users/alice/phrases')));
    await assertFails(getDocs(collection(alice(), 'users')));
  });
});

describe('signed out: nothing', () => {
  for (const [name, [path, make]] of Object.entries(paths)) {
    test(`${name}`, async () => {
      await seed(path, make());
      await assertFails(getDoc(doc(nobody(), path)));
      await assertFails(setDoc(doc(nobody(), path), make()));
      await assertFails(deleteDoc(doc(nobody(), path)));
    });
  }
});

describe('paths outside the model are denied', () => {
  test('other collections and documents', async () => {
    await assertFails(setDoc(doc(alice(), 'things/x'), { a: 1 }));
    await assertFails(getDoc(doc(alice(), 'things/x')));
    await assertFails(setDoc(doc(alice(), 'users/alice/messages/m1'), { text: 'hi' }));
    await assertFails(setDoc(doc(alice(), 'users/alice/contacts/c1'), { phone: '+20' }));
    await assertFails(setDoc(doc(alice(), 'users/alice/settings/other'), settings()));
  });
});

describe('bad fields', () => {
  const bad = (path, data) => assertFails(setDoc(doc(alice(), path), data));

  test('profile', async () => {
    const p = paths.profile[0];
    await bad(p, { ...profile(), extra: 1 });
    const { displayName, ...noName } = profile();
    await bad(p, noName);
    await bad(p, { ...profile(), displayName: 'x'.repeat(101) });
    await bad(p, { ...profile(), displayName: 5 });
    await bad(p, { ...profile(), schemaVersion: 2 });
    await bad(p, { ...profile(), createdAt: '2026-10-17' });
  });

  test('settings', async () => {
    const p = paths.settings[0];
    await bad(p, { ...settings(), signLanguage: 'arsl' });
    await bad(p, { ...settings(), uiLang: 'fr' });
    await bad(p, { ...settings(), theme: 'blue' });
    await bad(p, { ...settings(), spokenLanguage: 'de' });
    await bad(p, { ...settings(), who: 'both' });
    await bad(p, { ...settings(), signSpeed: 2 });
    await bad(p, { ...settings(), subtitles: 'yes' });
    await bad(p, { ...settings(), avatarId: 'x'.repeat(41) });
    await bad(p, { ...settings(), analyticsOptIn: true });
    const { updatedAt, ...noTime } = settings();
    await bad(p, noTime);
    await bad(p, { ...settings(), updatedAt: 5 });
  });

  test('phrases', async () => {
    const p = paths.phrase[0];
    await assertSucceeds(setDoc(doc(alice(), p), { ...phrase(), text: 'x'.repeat(500) }));
    await bad(p, { ...phrase(), text: 'x'.repeat(501) });
    await bad(p, { ...phrase(), text: '' });
    await bad(p, { ...phrase(), text: 7 });
    await bad(p, { ...phrase(), lang: 'fr' });
    await bad(p, { ...phrase(), deleted: 'no' });
    await bad(p, { ...phrase(), createdAt: t1, updatedAt: t0 });
    await bad(p, { ...phrase(), extra: true });
    const { lang, ...noLang } = phrase();
    await bad(p, noLang);
    await bad('users/alice/phrases/NOT-HEX', phrase());
  });

  // What the 500 counts: UTF-16 units, the same as Dart's String.length,
  // so the app's check (Synced.phraseFits) agrees exactly; longer phrases
  // stay on the phone.
  test('phrases: the 500 counts UTF-16 units (Arabic 500; emoji 250)', async () => {
    const p = paths.phrase[0];
    const arabic = 'ش';
    const emoji = '\u{1F44B}'; // two UTF-16 units
    await assertSucceeds(setDoc(doc(alice(), p), { ...phrase(), lang: 'ar', text: arabic.repeat(500) }));
    await bad(p, { ...phrase(), lang: 'ar', text: arabic.repeat(501) });
    await assertSucceeds(setDoc(doc(alice(), p), { ...phrase(), text: emoji.repeat(250) }));
    await bad(p, { ...phrase(), text: emoji.repeat(251) });
  });

  test('activity', async () => {
    const p = 'users/alice/activity/e9';
    await bad(p, { ...quiz(), v: 2 });
    await bad(p, { ...quiz(), type: 'cheat' });
    await bad(p, { ...quiz(), xp: 101 });
    await bad(p, { ...quiz(), xp: -1 });
    await bad(p, { ...quiz(), xp: 1.5 });
    await bad(p, { ...quiz(), prob: 1.5 });
    await bad(p, { ...quiz(), prob: 'high' });
    await bad(p, { ...quiz(), day: '17/10/2026' });
    await bad(p, { ...quiz(), at: '2026-10-17T09:00:00Z' });
    await bad(p, { ...quiz(), deviceId: 'phone' });
    await bad(p, { ...quiz(), moduleId: '' });
    await bad(p, { ...quiz(), label: null }); // quiz needs its sign
    const { label, ...noLabel } = quiz();
    await bad(p, noLabel);
    await bad(p, { ...missionDone(), label: 'hello' }); // missionDone has none
    await bad(p, { ...quiz(), extra: 1 });
    await bad('users/alice/activity/bad id!', quiz());
  });
});
