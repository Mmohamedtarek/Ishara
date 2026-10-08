// The ARB files are generated from the prototype by app/tools/extract_strings.py.
// These checks catch a broken regeneration or a hand edit.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _messages(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// Placeholder names: `{x}` and `{x, select, ...}`, but not the text of a
/// select branch (`female{...}`, `other{...}`).
Set<String> _placeholders(String s) => {
  for (final m in RegExp(
    r'(?<!female)(?<!other)\{(\w+)(\}|, select,)',
  ).allMatches(s))
    m.group(1)!,
};

void main() {
  final en = _arb('en');
  final ar = _arb('ar');

  test('en and ar have exactly the same messages', () {
    expect(_messages(ar), _messages(en));
    expect(_messages(en).length, greaterThan(200));
  });

  test('every message uses the same placeholders in both languages', () {
    for (final k in _messages(en)) {
      expect(
        _placeholders(ar[k] as String),
        _placeholders(en[k] as String),
        reason: k,
      );
      final declared =
          ((en['@$k'] as Map?)?['placeholders'] as Map?)?.keys.toSet() ?? {};
      expect(declared, _placeholders(en[k] as String), reason: '@$k');
    }
  });

  test('no message is empty, and none keeps the avatar name "Nour"', () {
    for (final arb in [en, ar]) {
      for (final k in _messages(arb)) {
        final v = arb[k] as String;
        if (k.startsWith('@@')) continue;
        expect(v.trim(), isNotEmpty, reason: k);
        expect(v.contains('Nour') || v.contains('نور'), isFalse, reason: k);
      }
    }
  });

  test('strings removed by user decisions are absent', () {
    const removed = [
      'google', 'phoneLogin', 'remember', 'lblId', // Q-B2
      'sUnsure', 'unsure', // Q-T1
      'sSos', 'toastSOS', // Q-T4
      'accuracy', 'pose3s', 'c2', 'pairLead', 'tip1', 'tip2', // Q-K2..K5
      'tipIndex', 'okMatch', 'shareMedal', 'mDoctor', // Q-L1, L3, L6
      'avHair', 'avSkin', // Q-A2
      'h1', 'st1', 'today', // fake data
    ];
    for (final k in removed) {
      expect(en.containsKey(k), isFalse, reason: k);
    }
  });

  testWidgets('feminine Arabic forms follow the avatar gender', (t) async {
    late AppLocalizations l;
    await t.pumpWidget(
      Localizations(
        locale: const Locale('ar'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            l = AppLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(l.avSigning('male'), 'بيعمل الإشارة');
    expect(l.avSigning('female'), 'بتعمل الإشارة');
    expect(l.signed('سارة', 'female'), 'سارة عملت الإشارة');
    expect(l.hiNour('نور'), 'أهلاً، أنا نور!');
    expect(l.stepOf(2), 'خطوة 2 من 3');
  });

  testWidgets('English ignores gender and fills the name', (t) async {
    late AppLocalizations l;
    await t.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            l = AppLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(l.signed('Sara', 'female'), 'Signed by Sara');
    expect(l.signed('Nour', 'male'), 'Signed by Nour');
    expect(l.continueLabel, 'Continue');
    expect(l.qSayDeaf, 'I am deaf. I use this app to talk.');
  });
}
