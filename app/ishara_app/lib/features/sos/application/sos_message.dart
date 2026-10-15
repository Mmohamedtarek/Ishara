import 'package:clock/clock.dart';
import 'package:intl/intl.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// The SOS message in the app language (draft O14 / O15): the map link,
/// the accuracy and the fix's time, or that there is no location. A fix
/// from another day ([now]'s date) carries its date too, so an old last
/// known position never reads as today's.
String sosMessage(
  AppLocalizations l,
  SosLocation where,
  String locale, {
  DateTime? now,
}) {
  final f = where.fix;
  if (f == null) return l.sosMessageNone;
  final today = now ?? clock.now();
  final sameDay =
      f.at.year == today.year &&
      f.at.month == today.month &&
      f.at.day == today.day;
  String fmt(DateFormat d) => (d..useNativeDigits = false).format(f.at);
  final time = fmt(DateFormat.Hm(locale));
  final when = sameDay
      ? time
      : '${fmt(DateFormat.MMMd(locale))}'
            '${locale.startsWith('ar') ? '، ' : ', '}$time';
  return l.sosMessage(SosLocator.mapLink(f), SosLocator.accuracy(f), when);
}
