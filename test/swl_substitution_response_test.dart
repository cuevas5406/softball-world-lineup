import 'package:flutter_test/flutter_test.dart';
import '../lib/swl_substitution_rules.dart';

void main() {
  test('rechazos explícitos y resultados inciertos', () {
    expect(swlIsExplicitSubstitutionRejection('400'), isTrue);
    expect(swlIsExplicitSubstitutionRejection('409'), isTrue);
    expect(swlIsExplicitSubstitutionRejection('PGRST116'), isTrue);
    expect(swlIsExplicitSubstitutionRejection('23505'), isTrue);
    expect(swlIsExplicitSubstitutionRejection(null), isFalse);
    expect(swlIsExplicitSubstitutionRejection(''), isFalse);
    expect(swlIsExplicitSubstitutionRejection('500'), isFalse);
    expect(swlIsExplicitSubstitutionRejection('08006'), isFalse);
    expect(swlIsExplicitSubstitutionRejection('XX000'), isFalse);
  });
}
