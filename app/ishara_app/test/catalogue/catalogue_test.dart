@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/catalogue/speech_to_sign.dart';
import 'package:ishara_app/core/catalogue/word_normalizer.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';

import '../support/kit.dart';

const _catalogue = 'assets/packs/asl/signs.json';

void main() {
  late Labels labels;
  late SignCatalogue cat;

  setUpAll(() {
    labels = Labels.parse(readText('assets/packs/asl/kit/model/labels.txt'));
    cat = SignCatalogue.parse(readText(_catalogue), labels: labels);
  });

  group('catalogue vs model', () {
    test(
      'every model sign (labels minus rest/other) has exactly one entry',
      () {
        expect(cat.language, SignLanguage.asl);
        for (final l in labels.signs) {
          expect(cat.byLabel(l), isNotNull, reason: l);
        }
        expect(labels.signs, hasLength(20));
      },
    );

    test('glove: true exactly for the model labels', () {
      expect(cat.gloveSigns.map((s) => s.label).toSet(), labels.signs.toSet());
      for (final s in cat.signs.where((s) => !s.glove)) {
        expect(labels.indexOf(s.label), isNull, reason: s.label);
      }
    });

    test('practice candidates are glove signs only (sign rule 3)', () {
      expect(cat.gloveSigns.every((s) => s.glove), isTrue);
      expect(
        cat.gloveSigns.map((s) => s.label),
        isNot(containsAll(['coffee', 'doctor', 'home', 'family', 'help'])),
      );
    });

    test('every avatar: true sign exists in the avatar library', () {
      final library = AvatarLibrary.parse(
        readText('assets/packs/asl/avatar/library.json'),
        language: SignLanguage.asl,
      ).labels;
      final avatar = cat.avatarSigns.map((s) => s.label).toSet();
      expect(
        library.containsAll(avatar),
        isTrue,
        reason: 'missing: ${avatar.difference(library)}',
      );
      expect(
        library.difference({for (final s in cat.signs) s.label}),
        isEmpty,
        reason: 'the library only animates catalogue signs',
      );
      // Sign rule 2: every animated sign is approved (the 10 new signs on
      // 2026-10-10, after their front + side review).
      expect(library.difference(avatar), isEmpty);
    });

    test('every entry has words in both languages and a description', () {
      expect(cat.signs, hasLength(25));
      for (final s in cat.signs) {
        for (final l in SpokenLanguage.values) {
          final w = s.wordsIn(l);
          expect([w.word, w.spoken], everyElement(isNotEmpty), reason: s.label);
          expect(w.variants, isNotEmpty, reason: s.label);
        }
        expect(s.description, isNotEmpty);
      }
    });

    test('English spoken text follows AI-SPEC §6', () {
      expect(
        cat.byLabel('thanks')!.wordsIn(SpokenLanguage.en).spoken,
        'thank you',
      );
      expect(
        cat.byLabel('iloveyou')!.wordsIn(SpokenLanguage.en).spoken,
        'I love you',
      );
      for (final l in labels.signs.where(
        (l) => l != 'thanks' && l != 'iloveyou',
      )) {
        expect(cat.byLabel(l)!.wordsIn(SpokenLanguage.en).spoken, l);
      }
    });

    test('unverified: only the 4 avatar-only signs outside vocabulary v2', () {
      expect(cat.signs.where((s) => !s.verified).map((s) => s.label).toSet(), {
        'coffee',
        'doctor',
        'family',
        'help',
      });
    });
  });

  group('speech → sign normalization (sign rule 7)', () {
    test('no normalized word or phrase leads to two signs', () {
      for (final l in SpokenLanguage.values) {
        final seen = <String, String>{};
        for (final s in cat.signs) {
          for (final v in s.wordsIn(l).variants) {
            final k = WordNormalizer.normalize(v);
            expect(seen[k] ?? s.label, s.label, reason: '"$v" ($l)');
            seen[k] = s.label;
          }
        }
      }
    });

    test('a catalogue with a collision is refused', () {
      final j = jsonDecode(readText(_catalogue)) as Map<String, dynamic>;
      final signs = j['signs'] as List<dynamic>;
      final yes = signs.firstWhere((x) => (x as Map)['label'] == 'yes') as Map;
      (yes['en'] as Map)['variants'] = ['yes', 'hello']; // "hello" → two signs
      expect(
        () => SignCatalogue.parse(jsonEncode(j), labels: labels),
        throwsA(isA<ParseFailure>()),
      );
    });

    test('Q-T5 / Q-A5: only the approved aliases exist', () {
      String? en(String w) =>
          cat.labelFor(WordNormalizer.normalize(w), SpokenLanguage.en);
      String? ar(String w) =>
          cat.labelFor(WordNormalizer.normalize(w), SpokenLanguage.ar);
      // kept
      expect(
        [en('hi'), en('hey'), en('i'), en('thank'), en('doctors')],
        ['hello', 'hello', 'me', 'thanks', 'doctor'],
      );
      expect([ar('السلام عليكم'), ar('من فضلك')], ['hello', 'please']);
      // removed (wrong-sign aliases)
      for (final w in [
        'my',
        'your',
        'house',
        'sure',
        'ok',
        'okay',
        'yeah',
        'nope',
      ]) {
        expect(en(w), isNull, reason: w);
      }
      for (final w in ['أكيد', 'اكيد', 'السلام', 'فضلك', 'من']) {
        expect(ar(w), isNull, reason: w);
      }
    });

    test('WordNormalizer folds case, diacritics, hamza/alef, ة/ه, ى/ي', () {
      expect(WordNormalizer.normalize('Hello'), 'hello');
      expect(
        WordNormalizer.normalize('شكراً'),
        WordNormalizer.normalize('شكرا'),
      );
      expect(WordNormalizer.normalize('أهلاً'), 'اهلا');
      expect(WordNormalizer.normalize('إنت'), 'انت');
      expect(WordNormalizer.normalize('آسف'), 'اسف');
      expect(WordNormalizer.normalize('ٱلبيت'), 'البيت');
      expect(WordNormalizer.normalize('مسؤول'), 'مسوول');
      expect(WordNormalizer.normalize('سائل'), 'سايل');
      expect(WordNormalizer.normalize('جعانة'), 'جعانه');
      expect(WordNormalizer.normalize('على'), 'علي');
      expect(WordNormalizer.normalize('مـــية'), 'ميه'); // tatweel
      expect(WordNormalizer.normalize("I'm"), 'im');
      expect(WordNormalizer.normalize('  thank-you!! '), 'thank you');
      expect(WordNormalizer.normalize('...'), '');
    });

    List<(String, String?)> m(String s, SpokenLanguage l) => [
      for (final seg in SpeechToSign.match(s, cat, l)) (seg.text, seg.label),
    ];

    test('English sentences', () {
      const en = SpokenLanguage.en;
      expect(m('Thank you very much', en), [
        ('Thank you', 'thanks'),
        ('very', null),
        ('much', null),
      ]);
      expect(m('I love you', en), [('I love you', 'iloveyou')]);
      expect(m("I'm hungry", en), [("I'm", null), ('hungry', 'hungry')]);
      expect(m('Hello, you!', en), [('Hello,', 'hello'), ('you!', 'you')]);
      expect(m('My house, okay?', en), [
        ('My', null),
        ('house,', null),
        ('okay?', null),
      ]);
      expect(m('I want water please', en), [
        ('I', 'me'),
        ('want', null),
        ('water', 'water'),
        ('please', 'please'),
      ]);
      expect(m('', en), isEmpty);
      expect(m('— —', en), [('—', null), ('—', null)]);
    });

    test('Arabic sentences', () {
      const ar = SpokenLanguage.ar;
      expect(m('السلام عليكم يا دكتور', ar), [
        ('السلام عليكم', 'hello'),
        ('يا', null),
        ('دكتور', 'doctor'),
      ]);
      expect(m('انا جعانه', ar), [('انا', 'me'), ('جعانه', 'hungry')]);
      expect(m('مية من فضلك', ar), [('مية', 'water'), ('من فضلك', 'please')]);
      expect(m('السلام', ar), [('السلام', null)]);
      expect(m('أكيد', ar), [('أكيد', null)]);
    });

    test('languages are matched separately', () {
      expect(m('water', SpokenLanguage.ar), [('water', null)]);
      expect(m('مية', SpokenLanguage.en), [('مية', null)]);
    });

    test('SignSegment value semantics', () {
      const a = SignSegment(['thank', 'you'], 'thanks');
      expect(a, const SignSegment(['thank', 'you'], 'thanks'));
      expect(
        a.hashCode,
        const SignSegment(['thank', 'you'], 'thanks').hashCode,
      );
      expect(a.toString(), '"thank you" → thanks');
      expect(const SignSegment(['x'], null).toString(), '"x" → -');
    });
  });

  group('broken catalogues are refused', () {
    Map<String, dynamic> base() =>
        jsonDecode(readText(_catalogue)) as Map<String, dynamic>;
    List<dynamic> signs(Map<String, dynamic> j) => j['signs'] as List<dynamic>;

    final cases = <String, void Function(Map<String, dynamic>)>{
      'unknown language': (j) => j['language'] = 'xyz',
      'signs not a list': (j) => j['signs'] = <String, Object?>{},
      'sign not an object': (j) => signs(j)[0] = 1,
      'duplicate label': (j) => signs(j).add(signs(j)[0]),
      'non-word': (j) => (signs(j)[0] as Map)['label'] = 'rest',
      'glove true but not in model': (j) =>
          (signs(j).last as Map)['glove'] = true,
      'glove false but in model': (j) => (signs(j)[0] as Map)['glove'] = false,
      'model label missing': (j) => signs(j).removeAt(0),
      'missing ar words': (j) => (signs(j)[0] as Map).remove('ar'),
      'empty variants': (j) =>
          ((signs(j)[0] as Map)['en'] as Map)['variants'] = <String>[],
      'blank variant': (j) =>
          ((signs(j)[0] as Map)['en'] as Map)['variants'] = ['!!'],
      'blank word': (j) => ((signs(j)[0] as Map)['en'] as Map)['word'] = ' ',
      'flag not bool': (j) => (signs(j)[0] as Map)['verified'] = 'yes',
      'missing description': (j) => (signs(j)[0] as Map).remove('description'),
    };
    for (final MapEntry(key: name, value: edit) in cases.entries) {
      test(name, () {
        final j = base();
        edit(j);
        expect(
          () => SignCatalogue.parse(jsonEncode(j), labels: labels),
          throwsA(isA<ParseFailure>()),
        );
      });
    }
    test('not JSON / not an object', () {
      for (final t in ['nope', '[]']) {
        expect(
          () => SignCatalogue.parse(t, labels: labels),
          throwsA(isA<ParseFailure>()),
        );
      }
    });
  });

  group('review regressions', () {
    List<(String, String?)> m(String s, SpokenLanguage l) => [
      for (final seg in SpeechToSign.match(s, cat, l)) (seg.text, seg.label),
    ];

    test('a sign the avatar cannot perform gives no sign (ready pose)', () {
      // every catalogue sign is animated now: take one away to test the rule
      final j = jsonDecode(readText(_catalogue)) as Map<String, dynamic>;
      for (final s in j['signs'] as List<dynamic>) {
        if ((s as Map<String, dynamic>)['label'] == 'hungry') {
          s['avatar'] = false;
        }
      }
      final noHungry = SignCatalogue.parse(jsonEncode(j), labels: labels);
      List<(String, String?)> m2(String t) => [
        for (final seg in SpeechToSign.match(t, noHungry, SpokenLanguage.en))
          (seg.text, seg.label),
      ];
      expect(m2('bye hungry'), [('bye', 'bye'), ('hungry', null)]);
      expect(m('bye hungry', SpokenLanguage.en), [
        ('bye', 'bye'),
        ('hungry', 'hungry'),
      ]);
    });

    test('draft variants are not matched until approved', () {
      final j = jsonDecode(readText(_catalogue)) as Map<String, dynamic>;
      final call = (j['signs'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((s) => s['label'] == 'call');
      call['draft'] = ['en.variants:phone', 'ar.variants'];
      final drafted = SignCatalogue.parse(jsonEncode(j), labels: labels);
      expect(drafted.labelFor('phone', SpokenLanguage.en), isNull);
      expect(drafted.labelFor('call', SpokenLanguage.en), 'call');
      expect(
        drafted.labelFor(WordNormalizer.normalize('تليفون'), SpokenLanguage.ar),
        isNull,
      );
      expect(
        drafted.byLabel('call')!.isDraftVariant(SpokenLanguage.en, 'phone'),
        isTrue,
      );
      expect(
        drafted.byLabel('call')!.isDraftVariant(SpokenLanguage.en, 'call'),
        isFalse,
      );
    });

    test('approved variants (step 4 approvals) are matched', () {
      expect(cat.labelFor('phone', SpokenLanguage.en), 'call');
      expect(cat.labelFor('goodbye', SpokenLanguage.en), 'bye');
      const ar = {
        'لو سمحت': 'please',
        'آسفة': 'sorry',
        'واحد': 'one',
        'تليفون': 'call',
        'اثنين': 'two',
        'باي': 'bye',
      };
      for (final MapEntry(:key, :value) in ar.entries) {
        expect(
          cat.labelFor(WordNormalizer.normalize(key), SpokenLanguage.ar),
          value,
          reason: key,
        );
      }
    });

    test('a phrase never spans sentence punctuation', () {
      expect(m('Thank. You', SpokenLanguage.en), [
        ('Thank.', 'thanks'),
        ('You', 'you'),
      ]);
      expect(m('thank , you', SpokenLanguage.en), [
        ('thank', 'thanks'),
        (',', null),
        ('you', 'you'),
      ]);
      expect(m('من، فضلك', SpokenLanguage.ar), [('من،', null), ('فضلك', null)]);
    });

    test('words glued by punctuation are split', () {
      expect(m('hello,you', SpokenLanguage.en), [
        ('hello,', 'hello'),
        ('you', 'you'),
      ]);
      expect(m('yes/no', SpokenLanguage.en), [('yes/', 'yes'), ('no', 'no')]);
      expect(m("I'm", SpokenLanguage.en), [("I'm", null)]);
    });

    test('"language" that is not text is a ParseFailure (not a TypeError)', () {
      final j = jsonDecode(readText(_catalogue)) as Map<String, dynamic>;
      j['language'] = 1;
      expect(
        () => SignCatalogue.parse(jsonEncode(j), labels: labels),
        throwsA(isA<ParseFailure>()),
      );
    });
  });

  test('the shipped catalogue has no unapproved drafts', () {
    for (final s in cat.signs) {
      expect(s.draft, isEmpty, reason: s.label);
    }
  });

  test('vocabulary v2.2 forms: WATER at the mouth, COME one arc', () {
    expect(cat.byLabel('water')!.description, contains('taps the mouth'));
    expect(cat.byLabel('water')!.description, isNot(contains('chin')));
    expect(cat.byLabel('come')!.description, contains('one quick arc'));
    expect(cat.byLabel('come')!.description, isNot(contains('beckon')));
  });
}
