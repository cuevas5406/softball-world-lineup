import 'package:flutter/services.dart';

const swlCodePrefix = 'SWL-';

String swlCodeSuffix(String value) {
  final normalized = value.trim().toUpperCase();
  return normalized.startsWith(swlCodePrefix)
      ? normalized.substring(swlCodePrefix.length)
      : normalized;
}

String swlCode(String value) => '$swlCodePrefix${swlCodeSuffix(value)}';

class SwlCodeInputFormatter extends TextInputFormatter {
  const SwlCodeInputFormatter({
    this.allowLegacyLetters = false,
    this.maxDigits,
  });

  final bool allowLegacyLetters;
  final int? maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final suffix = swlCodeSuffix(newValue.text);
    final valid = allowLegacyLetters
        ? RegExp(r'^[A-Z0-9]*$')
        : RegExp(r'^[0-9]*$');
    final limit = maxDigits;
    if (!valid.hasMatch(suffix) || (limit != null && suffix.length > limit)) {
      return oldValue;
    }
    if (suffix == newValue.text) return newValue;
    return TextEditingValue(
      text: suffix,
      selection: TextSelection.collapsed(offset: suffix.length),
    );
  }
}
