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
      swlPreviewSpecial(state, 'RUNNER_MOVE', source: 3, destination: 2).third,
      isFalse,
    );
    expect(
      swlPreviewSpecial(state, 'RUNNER_MOVE', source: 3, destination: 3),
      same(state),
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
  test('Fantasma solo desde sexta, sin asignar carrera ni out', () {
    expect(
      () => swlPreviewSpecial(state.copy(inning: 5), 'GHOST_RUNNER'),
      throwsStateError,
    );
    final ghost = swlPreviewSpecial(state, 'GHOST_RUNNER');
    expect((ghost.second, ghost.homeRuns, ghost.outs), (true, 0, 1));
    expect(() => swlPreviewSpecial(ghost, 'GHOST_RUNNER'), throwsStateError);
  });
}
