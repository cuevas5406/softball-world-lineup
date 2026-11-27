import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_game_box_data.dart';

SwlRow game({int awayRuns = 0}) => {
  'home_team_id': 'home',
  'away_team_id': 'away',
  'inning': 1,
  'is_top': false,
  'status': 'IN_PROGRESS',
  'home_runs': 0,
  'away_runs': awayRuns,
  'home_innings': [],
  'away_innings': [],
};

SwlRow play(int version, String type, SwlRow data) => {
  'version': version,
  'event_type': type,
  'batting_team_id': 'away',
  'inning': 1,
  'event_data': data,
};

SwlRow pitch(int version, String id, {int outs = 0, int hits = 0, int k = 0}) =>
    {
      'version': version,
      'pitcher_id': id,
      'outs': outs,
      'hits': hits,
      'strikes_out': k,
    };

void main() {
  test('atribuye el hit del suplente y el relevo por versión de LAB', () {
    final stats = SwlGameBoxData(
      game(),
      [
        play(2, 'SUBSTITUTION', {
          'outgoing_player_id': 'starter',
          'incoming_player_id': 'sub',
        }),
        play(3, 'HIT', {'batter_id': 'sub', 'batter_base': 1, 'runs': 0}),
        play(6, 'BALL', {'batter_id': 'second'}),
        play(7, 'STRIKE', {'batter_id': 'second'}),
        play(8, 'STRIKE', {'batter_id': 'second'}),
        play(9, 'STRIKE', {
          'batter_id': 'second',
          'plate_appearance_completed': true,
        }),
        play(10, 'DOUBLE_PLAY', {'batter_id': 'third', 'runner_id': 'sub'}),
      ],
      [
        pitch(3, 'starter-p', hits: 1),
        for (final version in [6, 7, 8]) pitch(version, 'relief'),
        pitch(9, 'relief', outs: 1, k: 1),
        pitch(10, 'relief', outs: 2),
      ],
    );
    final bats = stats.batting['away']!;
    expect(bats['starter'], isNull);
    expect(bats['sub']![3], 1);
    expect(bats['second']![9], 1);
    expect(bats['third']!.take(2), [1, 1]);
    expect(stats.pitching['home']!['starter-p']!.last, 1);
    expect(stats.pitching['home']!['relief'], [3, 0, 0, 0, 0, 1, 0, 1, 3, 5]);
    expect(stats.pitching['away'], isNull);
    expect(stats.innings['away'], [0]);
  });

  test('concilia CA y CE sin contar movimientos ni repetir el boleto', () {
    final stats = SwlGameBoxData(
      game(awayRuns: 1),
      [
        play(1, 'BALL', {
          'batter_id': 'batter',
          'plate_appearance_completed': true,
          'scoring_player_ids': ['scorer'],
          'rbi': 1,
        }),
        play(2, 'RUNNER_OUT', {'runner_id': 'batter'}),
        play(3, 'OUT', {'batter_id': 'next'}),
        play(4, 'UNDO_OUT', {'reverts_version': 3}),
      ],
      [pitch(1, 'p'), pitch(2, 'p', outs: 1), pitch(3, 'p', outs: 1)],
    );
    expect(stats.innings['away'], [1]);
    expect(stats.batting['away']!['scorer']![2], 1);
    expect(stats.batting['away']!['batter'], [1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0]);
    expect(stats.batting['away']!['next'], isNull);
    expect(stats.pitching['home']!['p']!.first, 1);
    expect(stats.pitching['home']!['p']!.last, 1);
  });

  test('deja pendiente la mitad que no concilia y señala crédito de pitcher faltante', () {
    final stats = SwlGameBoxData(game(awayRuns: 2), [
      play(1, 'HIT', {'batter_id': 'batter', 'batter_base': 2}),
    ], []);
    expect(stats.innings['away'], [null]);
    expect(stats.incompleteRuns, {'away'});
    expect(stats.incompletePitching, {'home'});
  });
}
