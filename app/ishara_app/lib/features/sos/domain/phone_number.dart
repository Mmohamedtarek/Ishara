/// Emergency contact numbers (Q-T4 phase 1): Egyptian numbers as people
/// write them (`01x…`, `+20…`, `0020…`) and other international numbers in
/// `+` form, stored in E.164 (`+201012345678`).
abstract final class PhoneNumber {
  /// Egyptian mobile networks: 010, 011, 012, 015.
  static final _egMobile = RegExp(r'^1[0125]\d{8}$');

  /// Egyptian landlines after +20: an area code (2 = Cairo, 3 =
  /// Alexandria, or a two-digit one) and the number, 9 digits in all.
  static final _egLandline = RegExp(r'^[2-9]\d{7,8}$');

  /// E.164: a country code (no leading 0) and at most 15 digits in all.
  static final _international = RegExp(r'^[1-9]\d{7,14}$');

  static final _spacing = RegExp(r'[\s\-().]');

  /// The number in E.164, or null when it isn't a number we accept.
  static String? toE164(String input) {
    var s = _westernDigits(input.trim()).replaceAll(_spacing, '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    if (s.startsWith('+')) {
      final digits = s.substring(1);
      if (digits.startsWith('20')) {
        final national = digits.substring(2);
        return _egMobile.hasMatch(national) || _egLandline.hasMatch(national)
            ? '+20$national'
            : null;
      }
      return _international.hasMatch(digits) ? '+$digits' : null;
    }
    // a local Egyptian mobile: 01x xxxx xxxx
    if (s.startsWith('0') && _egMobile.hasMatch(s.substring(1))) {
      return '+20${s.substring(1)}';
    }
    return null;
  }

  static bool isValid(String input) => toE164(input) != null;

  /// Arabic-Indic and Eastern Arabic-Indic digits → 0-9 (an Arabic
  /// keyboard types them).
  static String _westernDigits(String s) => String.fromCharCodes([
    for (final r in s.runes)
      if (r >= 0x0660 && r <= 0x0669)
        0x30 + r - 0x0660
      else if (r >= 0x06F0 && r <= 0x06F9)
        0x30 + r - 0x06F0
      else
        r,
  ]);

  /// For wa.me links: the digits only (no +).
  static String waDigits(String e164) => e164.replaceAll('+', '');
}
