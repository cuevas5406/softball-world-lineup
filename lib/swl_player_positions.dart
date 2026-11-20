import 'swl_lineup_draft.dart';

String swlPositionLabel(Object? primary, Object? secondary) => [
  primary?.toString().trim() ?? '',
  secondary?.toString().trim() ?? '',
].where((position) => position.isNotEmpty).join(' / ');

String? swlValidatePlayerPositions(String primary, String secondary) {
  if (secondary.isEmpty) return null;
  if (primary.isEmpty) return 'Indica primero la posición principal.';
  if (!swlDefensivePositions.contains(secondary)) {
    return 'Usa una posición secundaria válida: ${swlDefensivePositions.join(', ')}.';
  }
  if (primary.toUpperCase() == secondary) {
    return 'La posición secundaria debe ser diferente de la principal.';
  }
  return null;
}
