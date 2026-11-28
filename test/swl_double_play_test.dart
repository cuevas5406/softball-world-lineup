import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_double_play.dart';

void main() {
  test('las ocho ocupaciones con cero, uno y dos outs', () {
    for (var mask = 0; mask < 8; mask++) {
      final bases = {
        for (var b = 1; b <= 3; b++)
          if (mask & (1 << (b - 1)) != 0) b,
      };
      for (var outs = 0; outs <= 2; outs++) {
        expect(swlCanDoublePlay(bases, outs), mask != 0 && outs < 2);
        for (var source = 1; source <= 3; source++) {
          expect(
            swlDoublePlayError(bases, outs, source, {}, timePlay: false) ==
                null,
            bases.contains(source) && outs < 2,
            reason: 'bases=$bases, outs=$outs, corredor=$source',
          );
        }
      }
    }
  });
  test('valida avances, colisión, rebase, carrera y tercer out', () {
    String? validate(
      int outs,
      int source,
      Map<int, int> moves, {
      bool time = false,
    }) => swlDoublePlayError({1, 2, 3}, outs, source, moves, timePlay: time);
    expect(validate(0, 1, {2: 3}), isNotNull);
    expect(validate(0, 2, {1: 0}), isNotNull);
    expect(validate(0, 1, {2: 1}), isNotNull);
    expect(validate(0, 1, {1: 2}), isNotNull);
    expect(validate(0, 1, {2: 3, 3: 0}), isNull);
    expect(validate(0, 1, {2: 0, 3: 0}), isNull);
    expect(validate(1, 1, {2: 0, 3: 0}), isNotNull);
    expect(validate(1, 1, {2: 0, 3: 0}, time: true), isNull);
    expect(validate(1, 2, {1: 0, 3: 0}, time: true), isNotNull);
  });
}
