import 'package:flutter/material.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// How a module looks on the path: the prototype's `.mod .ic` colours
/// (`.c-teal`…) and icons. Start here is the prototype's; the others are
/// drafts (tools/out/step8/drafts.html). Keyed by the pack's module ids.
class ModuleLook {
  const new(this.icon, this.colors, this.title);

  final String icon;

  /// The icon tile's 135° gradient.
  final List<Color> colors;
  final String Function(AppLocalizations l) title;

  static const teal = [Color(0xFF4B5BD6), Color(0xFF3446C9)];
  static const violet = [Color(0xFF7D5A94), Color(0xFF5A3F70)];
  static const amber = [Color(0xFFFCD34D), Color(0xFFD97706)];
  static const rose = [Color(0xFFFB7185), Color(0xFFBE123C)];
  static const green = [Color(0xFF34D399), Color(0xFF059669)];
  static const blue = [Color(0xFF60A5FA), Color(0xFF1D4ED8)];

  static final Map<String, ModuleLook> byId = {
    'start': ModuleLook('star', teal, (l) => l.mStart),
    'numbers': ModuleLook('hand', violet, (l) => l.mNumbers),
    'people': ModuleLook('family', rose, (l) => l.mPeople),
    'needs': ModuleLook('drop', green, (l) => l.mNeeds),
    'watch': ModuleLook('eye', blue, (l) => l.mWatchOnly),
  };

  /// The daily challenge (prototype: `.c-amber`, `bolt`).
  static final daily = ModuleLook('bolt', amber, (l) => l.mDaily);

  /// A module of a pack this version doesn't know (never shows raw ids).
  static final unknown = ModuleLook('book', teal, (l) => l.learnTitle);

  static ModuleLook of(String id) => byId[id] ?? unknown;
}

/// The app language's words (Learn shows meanings in the UI language,
/// prototype `wlabel`).
SpokenLanguage learnLanguage(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar'
    ? SpokenLanguage.ar
    : SpokenLanguage.en;

/// A module's subtitle: the prototype's text for Start here, else its
/// signs' words from `signs.json`, in order.
String moduleSubtitle(
  BuildContext context,
  String id,
  List<String> labels,
  SignCatalogue catalogue,
) {
  final l = AppLocalizations.of(context);
  if (id == 'start') return l.mStartS;
  final lang = learnLanguage(context);
  return [
    for (final label in labels)
      catalogue.byLabel(label)?.wordsIn(lang).word ?? label,
  ].join(lang == SpokenLanguage.ar ? '، ' : ', ');
}
