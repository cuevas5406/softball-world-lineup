import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_play_rules.dart';
import '../lib/swl_special_play.dart';

void main() {
  const state = SwlPlayState(
    balls: 0,
    strikes: 0,
    outs: 1,
    inning: 6,
    homeRuns: 0,
    awayRuns: 0,
    isTop: false,
    first: true,
    second: false,
    third: true,
  );
  test('Avance, regreso, permanencia y carrera', () {
    expect(
      swlPreviewSpecial(state, 'RUNNER_MOVE', source: 1, destination: 2).second,
      isTrue,
    );
    expect(
      () => swlPreviewSpecial(state, 'RUNNER_MOVE', source: 3, destination: 2),
      throwsStateError,
    );
    expect(
      () => swlPreviewSpecial(state, 'RUNNER_MOVE', source: 3, destination: 3),
      throwsStateError,
    );
    expect(
      swlPreviewSpecial(
        state,
        'RUNNER_MOVE',
        source: 3,
        destination: 0,
      ).homeRuns,
      1,
    );
    expect(
      () => swlPreviewSpecial(state, 'RUNNER_MOVE', source: 1, destination: 0),
      throwsStateError,
    );
  });
  test('Out en home no acredita carreras y exige destino válido', () {
    final out = swlPreviewSpecial(state, 'RUNNER_OUT', source: 3, destination: 0);
    expect(out.homeRuns, 0);
    expect(out.awayRuns, 0);
    expect(out.third, false);
    expect(() => swlPreviewSpecial(state, 'RUNNER_OUT', source: 3), throwsStateError);
    expect(() => swlPreviewSpecial(state, 'RUNNER_OUT', source: 3, destination: 2), throwsStateError);
    expect(() => swlPreviewSpecial(state, 'RUNNER_OUT', source: 2, destination: 0), throwsStateError);
  });
  test('Sacrificio y doble play contextual', () {
    final sf = swlPreviewSpecial(
      state,
      'SACRIFICE_FLY',
      firstTo: 2,
      thirdTo: 0,
    );
    expect((sf.homeRuns, sf.outs, sf.second), (1, 2, true));
    expect(
      () => swlPreviewSpecial(state, 'SACRIFICE_FLY', firstTo: 1, thirdTo: 3),
      throwsStateError,
    );
    final dp = swlPreviewSpecial(state, 'DOUBLE_PLAY', source: 1);
    expect((dp.inning, dp.isTop, dp.third), (7, true, false));
  });
  test('Sacrificio rechaza corredores que se rebasan o comparten base', () {
    final loaded = state.copy(second: true);
    expect(() => swlPreviewSpecial(loaded, 'SACRIFICE_FLY',
      firstTo: 3, secondTo: 2, thirdTo: 0), throwsStateError);
    expect(() => swlPreviewSpecial(loaded, 'SACRIFICE_FLY',
      firstTo: 2, secondTo: 2, thirdTo: 0), throwsStateError);
    final legal = swlPreviewSpecial(loaded, 'SACRIFICE_FLY',
      firstTo: 2, secondTo: 3, thirdTo: 0);
    expect((legal.homeRuns, legal.outs, legal.first, legal.second, legal.third),
      (1, 2, false, true, true));
  });
  test('Jugadas especiales rechazan estados de partido inválidos', () {
    expect(() => swlPreviewSpecial(state.copy(outs: 3),
      'RUNNER_MOVE', source: 1, destination: 2), throwsStateError);
    expect(() => swlPreviewSpecial(state.copy(balls: 4),
      'RUNNER_OUT', source: 3, destination: 0), throwsStateError);
    expect(() => swlPreviewSpecial(state.copy(strikes: 3),
      'SACRIFICE_FLY', firstTo: 2, thirdTo: 0), throwsStateError);
    expect(() => swlPreviewSpecial(state.copy(inning: 0),
      'DOUBLE_PLAY', source: 1), throwsStateError);
  });
  test('Tercer out de corredor cierra media entrada sin carrera', () {
    final before = state.copy(outs: 2, inning: 6, isTop: true,
      homeRuns: 2, awayRuns: 2);
    final after = swlPreviewSpecial(before, 'RUNNER_OUT',
      source: 3, destination: 0);
    expect((after.inning, after.isTop, after.outs), (6, false, 0));
    expect((after.homeRuns, after.awayRuns), (2, 2));
    expect((after.first, after.second, after.third),
      (false, false, false));
    expect((after.balls, after.strikes), (0, 0));
  });
  test('Doble play con cero outs deja dos y conserva otros corredores', () {
    final before = state.copy(outs: 0);
    final after = swlPreviewSpecial(before, 'DOUBLE_PLAY', source: 1);
    expect((after.inning, after.isTop, after.outs), (6, false, 2));
    expect((after.first, after.third), (false, true));
    expect((after.homeRuns, after.awayRuns), (0, 0));
  });
  test('Doble play con dos outs se rechaza sin anotar cuarto out', () {
    expect(() => swlPreviewSpecial(state.copy(outs: 2),
      'DOUBLE_PLAY', source: 1), throwsStateError);
  });
  test('Fantasma solo en extras empatados al inicio con bases vacías', () {
    expect(
      () => swlPreviewSpecial(state.copy(inning: 5), 'GHOST_RUNNER'),
      throwsStateError,
    );
    expect(() => swlPreviewSpecial(state, 'GHOST_RUNNER'), throwsStateError);
    final extra = state.copy(inning: 7, outs: 0, first: false, third: false);
    final ghost = swlPreviewSpecial(extra, 'GHOST_RUNNER');
    expect((ghost.second, ghost.homeRuns, ghost.outs), (true, 0, 0));
    expect(() => swlPreviewSpecial(ghost, 'GHOST_RUNNER'), throwsStateError);
    expect(() => swlPreviewSpecial(extra.copy(balls: 1), 'GHOST_RUNNER'), throwsStateError);
    expect(() => swlPreviewSpecial(extra.copy(strikes: 1), 'GHOST_RUNNER'), throwsStateError);
    expect(() => swlPreviewSpecial(extra, 'GHOST_RUNNER', regulationInnings: 7), throwsStateError);
    expect(swlPreviewSpecial(extra, 'GHOST_RUNNER', regulationInnings: 5).second, isTrue);
    expect(() => swlPreviewSpecial(extra, 'GHOST_RUNNER', regulationInnings: 0), throwsStateError);
  });
}
