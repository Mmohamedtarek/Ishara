@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/catalogue/speech_to_sign.dart';
import 'package:ishara_app/core/catalogue/word_normalizer.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:path/path.dart' as p;

import '../support/kit.dart';

const _catalogue = 'assets/packs/asl/signs.json';

/// The avatar engine's sign library in the prototype (`var SIGNS = {...}`),
/// with the Q-A4 rename love → iloveyou. Replaced by the ported engine
/// library in the avatar step.
Set<String> _prototypeAvatarSigns() {
  final html = File(
    p.join(Directory.current.path, '..', '..', 'design', 'prototype.html'),
  ).readAsStringSync();
  final start = html.indexOf('var SIGNS = {');
  final end = html.indexOf('// ---------- skeleton name aliases', start);
  final keys =
      RegExp(
          r'^    (\w+): \{',
          multiLine: true,
        ).allMatches(html.substring(start, end)).map((m) => m.group(1)!).toSet()
        ..remove('rest');
  // Q-A4: the prototype's `love` is the model's `iloveyou`.
  const renamed = {'love': 'iloveyou'};
  return {for (final k in keys) renamed[k] ?? k};
}

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
      final library = _prototypeAvatarSigns();
      expect(library, hasLength(15));
      expect(
        cat.avatarSigns.map((s) => s.label).toSet(),
        library,
        reason: 'avatar: true must be exactly what the engine can perform',
      );
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
      expect(m("I'm hungry", en), [
        ("I'm", null),
        ('hungry', null),
      ]); // no avatar animation yet
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
      expect(m('انا جعانه', ar), [
        ('انا', 'me'),
        ('جعانه', null),
      ]); // no animation yet
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
      expect(m('bye hungry', SpokenLanguage.en), [
        ('bye', null),
        ('hungry', null),
      ]);
      expect(m('hello', SpokenLanguage.en), [('hello', 'hello')]);
    });

    test('draft variants are not matched until approved', () {
      for (final w in ['phone', 'goodbye']) {
        expect(cat.labelFor(w, SpokenLanguage.en), isNull, reason: w);
      }
      for (final w in ['لو سمحت', 'آسفة', 'واحد', 'تليفون', 'اثنين']) {
        expect(
          cat.labelFor(WordNormalizer.normalize(w), SpokenLanguage.ar),
          isNull,
          reason: w,
        );
      }
      expect(
        cat.byLabel('call')!.isDraftVariant(SpokenLanguage.en, 'phone'),
        isTrue,
      );
      expect(
        cat.byLabel('call')!.isDraftVariant(SpokenLanguage.en, 'call'),
        isFalse,
      );
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

  test('drafts are marked: Arabic spoken text needs approval (Q-T5)', () {
    for (final s in cat.signs) {
      expect(s.draft, contains('ar.spoken'), reason: s.label);
    }
  });
}
