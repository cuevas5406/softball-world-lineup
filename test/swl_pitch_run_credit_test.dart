import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_game_box_data.dart';

SwlRow play(
  int version,
  String type,
  SwlRow data, {
  String team = 'away',
  int inning = 1,
}) => {
  'version': version,
  'event_type': type,
  'batting_team_id': team,
  'inning': inning,
  'event_data': data,
};

SwlRow hit(String id, {List<String> scoring = const []}) => {
  'batter_id': id,
  'batter_base': scoring.isEmpty ? 1 : 4,
  'runs': scoring.length,
  'scoring_player_ids': scoring,
};

SwlRow pitch(int version, String id, {int? outs}) => {
  'version': version,
  'pitcher_id': id,
  if (outs != null) 'outs': outs,
};

SwlRow game(int away, {int home = 0}) => {
  'away_team_id': 'away',
  'home_team_id': 'home',
  'away_runs': away,
  'home_runs': home,
  'inning': 2,
  'is_top': true,
  'status': 'IN_PROGRESS',
};

void main() {
  test('fixture LAB: titular y relevista, HR heredado y out por error', () {
    final stats = SwlGameBoxData(
      {...game(0, home: 3), 'version': 8, 'inning': 1, 'is_top': false},
      [
        play(2, 'HIT', hit('h1'), team: 'home'),
        play(3, 'ERROR', {...hit('h2'), 'outs_added': 0}, team: 'home'),
        play(5, 'HIT', hit('h3', scoring: ['h1', 'h2', 'h3']), team: 'home'),
        play(6, 'HIT', hit('h4'), team: 'home'),
        play(7, 'ERROR', {
          ...hit('h5'),
          'outs_added': 1,
          'out_runner_ids': ['h4'],
        }, team: 'home'),
        play(8, 'SUBSTITUTION', {
          'outgoing_player_id': 'h4',
          'incoming_player_id': 'h10',
        }, team: 'home'),
      ],
      [
        {...pitch(2, 'starter'), 'hits': 1},
        pitch(3, 'starter'),
        {...pitch(5, 'relief'), 'hits': 1},
        {...pitch(6, 'relief'), 'hits': 1},
        pitch(7, 'relief', outs: 1),
      ],
      changes: [
        {
          'team_id': 'away',
          'version': 4,
          'old_pitcher_id': 'starter',
          'new_pitcher_id': 'relief',
        },
      ],
    );
    final credit = stats.runCredit;
    expect(
      [credit.runs('away', 'starter'), credit.cleanRuns('away', 'starter')],
      [2, 1],
    );
    expect(
      [credit.runs('away', 'relief'), credit.cleanRuns('away', 'relief')],
      [1, 1],
    );
    expect(credit.cleanTotal('away'), 2);
    expect(stats.pitching['away']!['starter']!.last, 2);
    expect(stats.pitching['away']!['relief']!.last, 3);
    expect(SwlGameBoxData.ip(stats.pitching['away']!['relief']!.first), '0.1');
    expect(stats.batting['home']!['h4']![3], 1);
  });

  test('un avance desconocido no afecta a otro corredor que anota', () {
    final stats = SwlGameBoxData(
      game(2),
      [
        play(1, 'HIT', hit('known')),
        play(2, 'HIT', hit('uncertain')),
        play(3, 'RUNNER_MOVE', {'runner_id': 'uncertain'}),
        play(4, 'HIT', {
          'batter_id': 'b',
          'batter_base': 1,
          'runs': 2,
          'scoring_player_ids': ['known', 'uncertain'],
        }),
      ],
      [pitch(1, 'p'), pitch(2, 'p'), pitch(4, 'p')],
    );
    expect(stats.runCredit.cleanLabel('home', 'p'), '≥1');
    expect(stats.runCredit.cleanTotalLabel('home'), '≥1');
  });

  test(
    'la causa registrada distingue robo, wild pitch y avance no clasificable',
    () {
      for (final cause in ['STEAL', 'WILD_PITCH', 'PASSED_BALL', 'UNKNOWN']) {
        final stats = SwlGameBoxData(
          game(1),
          [
            play(1, 'HIT', hit('runner')),
            play(2, 'RUNNER_MOVE', {
              'runner_id': 'runner',
              'advance_cause': cause,
              'runs': 1,
              'scoring_player_ids': ['runner'],
            }),
          ],
          [pitch(1, 'p')],
        );
        expect(stats.runCredit.runs('home', 'p'), 1);
        expect(
          stats.runCredit.cleanRuns('home', 'p'),
          ['STEAL', 'WILD_PITCH'].contains(cause) ? 1 : null,
        );
      }
    },
  );

  test('DP con carrera acredita dos outs, un pitcheo, una PA y C/CL', () {
    final stats = SwlGameBoxData(
      game(1),
      [
        play(1, 'HIT', hit('scorer')),
        play(2, 'HIT', hit('retired')),
        play(3, 'DOUBLE_PLAY', {
          'batter_id': 'batter',
          'runner_id': 'retired',
          'outs_added': 2,
          'runs': 1,
          'scoring_player_ids': ['scorer'],
          'plate_appearance_completed': true,
        }),
      ],
      [pitch(1, 'former'), pitch(2, 'current'), pitch(3, 'current', outs: 2)],
    );
    expect(stats.batting['away']!['batter']!.take(2), [1, 1]);
    final current = stats.pitching['home']!['current']!;
    expect(SwlGameBoxData.ip(current.first), '0.2');
    expect(
      current.last,
      2,
    ); // Un hit y un DP, un lanzamiento en juego cada uno.
    expect(stats.runCredit.runs('home', 'former'), 1);
    expect(stats.runCredit.cleanRuns('home', 'former'), 1);
    expect(stats.runCredit.runs('home', 'current'), 0);
    expect(stats.runCredit.cleanTotal('home'), 1);
  });

  test('LAB v28 atribuye el error sin fila y conserva C/CL anteriores', () {
    final stats = SwlGameBoxData(
      game(4),
      [
        play(23, 'HIT', hit('inherited'), inning: 2),
        play(
          26,
          'HIT',
          hit('first-hr', scoring: ['first-hr', 'inherited']),
          inning: 2,
        ),
        play(27, 'ERROR', {
          ...hit('error'),
          'scope': 'defensive_error',
          'outs_added': 0,
        }, inning: 2),
        play(
          28,
          'HIT',
          hit('second-hr', scoring: ['second-hr', 'error']),
          inning: 2,
        ),
      ],
      [pitch(23, '93'), pitch(26, '92'), pitch(28, '92')],
      changes: [
        {
          'team_id': 'home',
          'version': 25,
          'old_pitcher_id': '93',
          'new_pitcher_id': '92',
        },
      ],
    );
    expect(stats.incompletePitching, isEmpty);
    expect(stats.pitching['home']!['92']!.last, 3);
    final credit = stats.runCredit;
    expect(
      [
        for (final id in ['91', '93', '92']) credit.runs('home', id),
      ],
      [0, 1, 3],
    );
    expect(
      [
        for (final id in ['91', '93', '92']) credit.cleanRuns('home', id),
      ],
      [0, 1, 2],
    );
    expect(credit.cleanTotal('home'), 3);
  });

  test('un error heredado mantiene el cargo al relevado y no suma CL', () {
    final stats = SwlGameBoxData(
      game(2),
      [
        play(2, 'ERROR', {
          ...hit('error'),
          'scope': 'defensive_error',
          'outs_added': 0,
        }),
        play(4, 'HIT', hit('homer', scoring: ['error', 'homer'])),
      ],
      [pitch(4, 'p2')],
      changes: [
        {
          'team_id': 'home',
          'version': 1,
          'old_pitcher_id': 'p0',
          'new_pitcher_id': 'p1',
        },
        {
          'team_id': 'home',
          'version': 3,
          'old_pitcher_id': 'p1',
          'new_pitcher_id': 'p2',
        },
      ],
    );
    expect(stats.runCredit.runs('home', 'p1'), 1);
    expect(stats.runCredit.cleanRuns('home', 'p1'), 0);
    expect(stats.runCredit.cleanRuns('home', 'p2'), 1);
  });

  test('un evento sin atribución conserva los créditos confirmados', () {
    final credit = SwlGameBoxData(
      game(2),
      [
        play(1, 'HIT', hit('homer', scoring: ['homer'])),
        play(2, 'RUN', {'runs': 1}),
      ],
      [pitch(1, 'p')],
    ).runCredit;
    expect(credit.runsLabel('home', 'p'), '≥1');
    expect(credit.cleanLabel('home', 'p'), '≥1');
    expect(credit.runsLabel('home', 'other'), '—');
  });

  test('reconstruye los dos jonrones de SWL-378859 por versión', () {
    final credit = SwlGameBoxData(
      game(2, home: 1),
      [
        play(3, 'HIT', hit('first')),
        play(10, 'DOUBLE_PLAY', {'runner_id': 'first', 'outs_added': 2}),
        play(14, 'HIT', hit('solo', scoring: ['solo']), team: 'home'),
        play(23, 'HIT', hit('inherited'), inning: 2),
        play(
          26,
          'HIT',
          hit('homer', scoring: ['homer', 'inherited']),
          inning: 2,
        ),
      ],
      [
        pitch(3, 'home91'),
        pitch(10, 'home93'),
        pitch(14, 'away93'),
        pitch(23, 'home93'),
        pitch(26, 'home92'),
      ],
    ).runCredit;
    for (final (team, id, total) in [
      ('home', 'home91', 0),
      ('home', 'home93', 1),
      ('home', 'home92', 1),
      ('away', 'away93', 1),
    ]) {
      expect(credit.runs(team, id), total);
      expect(credit.cleanRuns(team, id), total);
    }
    expect(credit.cleanTotal('home'), 2);
    expect(credit.cleanTotal('away'), 1);
  });

  test(
    'transferir corredor conserva al pitcher original a través de relevos',
    () {
      final credit = SwlGameBoxData(
        game(3),
        [
          play(1, 'HIT', hit('old')),
          play(2, 'SUBSTITUTION', {
            'outgoing_player_id': 'old',
            'incoming_player_id': 'new',
          }),
          play(3, 'HIT', hit('second')),
          play(4, 'HIT', hit('homer', scoring: ['new', 'second', 'homer'])),
        ],
        [pitch(1, 'p1'), pitch(3, 'p2'), pitch(4, 'p3')],
      ).runCredit;
      for (final id in ['p1', 'p2', 'p3']) {
        expect(credit.runs('home', id), 1);
        expect(credit.cleanRuns('home', id), 1);
      }
    },
  );

  test('error tras dos outs distingue limpias individuales y colectivas', () {
    final credit = SwlGameBoxData(
      game(3),
      [
        play(1, 'OUT', {}),
        play(2, 'OUT', {}),
        play(3, 'HIT', hit('safe')),
        play(4, 'ERROR', hit('error')),
        play(5, 'HIT', hit('homer', scoring: ['safe', 'error', 'homer'])),
      ],
      [for (var i = 1; i <= 4; i++) pitch(i, 'p1'), pitch(5, 'p2')],
    ).runCredit;
    expect(credit.runs('home', 'p1'), 2);
    expect(credit.cleanRuns('home', 'p1'), 0);
    expect(credit.runs('home', 'p2'), 1);
    expect(credit.cleanRuns('home', 'p2'), 1);
    expect(credit.cleanTotal('home'), 0);
  });

  test('un avance sin causa clasificada conserva C y deja CL pendiente', () {
    final credit = SwlGameBoxData(
      game(1),
      [
        play(1, 'HIT', hit('runner')),
        play(2, 'RUNNER_MOVE', {
          'runner_id': 'runner',
          'runs': 1,
          'scoring_player_ids': ['runner'],
        }),
      ],
      [pitch(1, 'p')],
    ).runCredit;
    expect(credit.runs('home', 'p'), 1);
    expect(credit.cleanRuns('home', 'p'), isNull);
    expect(credit.cleanTotal('home'), isNull);
  });

  test('una carrera sin anotador identificado deja C y CL pendientes', () {
    final credit = SwlGameBoxData(game(1), [
      play(1, 'RUN', {'runs': 1}),
    ], []).runCredit;
    expect(credit.runs('home', 'p'), isNull);
    expect(credit.cleanRuns('home', 'p'), isNull);
    expect(credit.cleanTotal('home'), isNull);
  });
}
