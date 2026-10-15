import 'package:intl/intl.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// The SOS message in the app language (draft O14 / O15): the map link,
/// the accuracy and the fix's time, or that there is no location.
String sosMessage(AppLocalizations l, SosLocation where, String locale) {
  final f = where.fix;
  if (f == null) return l.sosMessageNone;
  return l.sosMessage(
    SosLocator.mapLink(f),
    SosLocator.accuracy(f),
    (DateFormat.Hm(locale)..useNativeDigits = false).format(f.at),
  );
}
