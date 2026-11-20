import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_game_finish.dart';

void main() {
  const rules = SwlGameFinishRules();
  SwlFinishReason? end(
    int inning,
    int home,
    int away, {
    bool top = false,
    bool complete = true,
  }) => rules.afterPlay(
    inning: inning,
    top: top,
    halfEnded: complete,
    home: home,
    away: away,
  );
  test('Seis entradas, empate y ganador visitante', () {
    expect(end(6, 5, 4), SwlFinishReason.normal);
    expect(end(6, 4, 4), isNull);
    expect(end(6, 4, 5, top: true), isNull);
    expect(end(6, 4, 5, complete: false), isNull);
    expect(end(6, 4, 5), SwlFinishReason.normal);
  });
  test('Gana el local sin outs innecesarios y se impide la octava', () {
    expect(end(6, 5, 4, top: true), SwlFinishReason.normal);
    expect(end(7, 10, 9, complete: false), SwlFinishReason.normal);
    expect(end(7, 9, 10), SwlFinishReason.normal);
  });
  test('Umbrales inclusivos y oportunidad del local', () {
    expect(end(3, 0, 15, top: true), isNull);
    expect(end(3, 1, 15), isNull);
    expect(end(3, 0, 15), SwlFinishReason.superKnockout);
    expect(end(3, 15, 0, top: true), SwlFinishReason.superKnockout);
    expect(end(4, 0, 10, top: true), isNull);
    expect(end(4, 1, 10), isNull);
    expect(end(4, 0, 10), SwlFinishReason.knockout);
    expect(end(4, 10, 0, complete: false), SwlFinishReason.knockout);
  });
  test('Los umbrales 15 y 10 respetan todas las oportunidades de bateo', () {
    for (final (inning, threshold, reason) in [
      (3, 15, SwlFinishReason.superKnockout),
      (4, 10, SwlFinishReason.knockout),
    ]) {
      expect(end(inning, 3, 3 + threshold, top: true, complete: false), isNull);
      expect(end(inning, 3, 3 + threshold, top: true), isNull);
      expect(end(inning, 3, 3 + threshold, complete: false), isNull);
      expect(end(inning, 4, 3 + threshold), isNull);
      expect(end(inning, 3, 3 + threshold), reason);
      expect(end(inning, 3 + threshold, 3, top: true, complete: false), isNull);
      expect(end(inning, 2 + threshold, 3, top: true), isNull);
      expect(end(inning, 3 + threshold, 3, top: true), reason);
      expect(end(inning, 3 + threshold, 3, complete: false), reason);
    }
  });

  test('En extras el empate continúa y el visitante debe cerrar la baja', () {
    expect(end(7, 9, 9), isNull);
    expect(end(8, 9, 10, top: true), isNull);
    expect(end(8, 9, 10, complete: false), isNull);
    expect(end(8, 9, 10), SwlFinishReason.normal);
    expect(end(8, 11, 10, complete: false), SwlFinishReason.normal);
  });

  test('Duración y umbrales configurables', () {
    const custom = SwlGameFinishRules(
      regulation: 5,
      superMargin: null,
      knockoutMargin: null,
    );
    expect(
      custom.afterPlay(
        inning: 3,
        top: false,
        halfEnded: true,
        home: 15,
        away: 0,
      ),
      isNull,
    );
    expect(
      custom.afterPlay(
        inning: 5,
        top: false,
        halfEnded: true,
        home: 2,
        away: 1,
      ),
      SwlFinishReason.normal,
    );
  });
  test('Ceros inmediatos y baja omitida', () {
    expect(swlDisplayInnings([2, 0], inning: 5, top: true, home: true), [
      2,
      0,
      0,
      0,
      null,
    ]);
    expect(
      swlDisplayInnings([], inning: 6, top: true, home: false, halfEnded: true),
      [0, 0, 0, 0, 0, 0],
    );
    expect(
      swlDisplayInnings([], inning: 6, top: true, home: true, halfEnded: true),
      [0, 0, 0, 0, 0, null],
    );
  });
}
