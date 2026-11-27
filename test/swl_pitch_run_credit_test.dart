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
