import 'package:flutter_test/flutter_test.dart';
import 'package:softball_world_lineup/swl_lineup_draft.dart';
import 'package:softball_world_lineup/swl_player_positions.dart';
import 'package:softball_world_lineup/swl_roster_repository.dart';

void main() {
  final ids = List.generate(9, (index) => 'b${index + 1}');
  final fullDefense = {
    for (var i = 0; i < 9; i++) ids[i]: swlDefensivePositions[i],
  };

  Map<String, dynamic> payload(SwlLineupDraft draft, {bool extended = true}) =>
      draft.saveParameters(
        gameId: 'game',
        teamId: 'team',
        revision: 2,
        extended: extended,
      );

  test('SF adicional no sustituye a C y se identifican duplicados', () {
    final positions = {
      for (final p in swlDefensivePositions.where((p) => p != 'C')) p: p,
    };
    expect(swlDefenseIssue(positions), contains('C.'));
    positions['C'] = 'C';
    expect(swlDefenseIssue(positions), isNull);
    expect(
      swlDefenseIssue({...positions, 'otro': 'C'}),
      'Posición duplicada: C.',
    );
  });

  test('V5.6 save requires a pitcher and a complete defense', () {
    final draft = SwlLineupDraft([...ids], {});
    expect(draft.validate(), contains('pitcher titular'));
    expect(() => payload(draft), throwsStateError);
  });

  test('extended lineup cannot save an incomplete defense', () {
    final draft = SwlLineupDraft([...ids], {'b1': 'P'});
    expect(draft.validate(), contains('Faltan posiciones defensivas'));
    expect(() => payload(draft), throwsStateError);
  });

  test('pitcher who bats occupies P and appears exactly once in order', () {
    final draft = SwlLineupDraft([...ids], {...fullDefense});
    draft.assign('b3', 'P');
    final request = payload(draft);
    expect(request['p_pitcher_id'], 'b3');
    expect(request['p_pitcher_bats'], isTrue);
    expect(request['p_player_ids'], ids);
    expect(request['p_defensive_positions']?.length, 9);
    expect(request['p_defensive_positions']?['b3'], 'P');
    expect(request['p_expected_revision'], 2);
  });

  test('pitcher with BD is defensive only and BD keeps its offensive slot', () {
    final draft = SwlLineupDraft(
      [...ids],
      {
        for (var i = 0; i < 8; i++) ids[i]: swlDefensivePositions[i + 1],
        'starter': 'P',
      },
      pitcherBats: false,
      designatedId: 'b9',
    );
    draft.moveBatter(1, -1);
    final request = payload(draft);
    expect(request['p_pitcher_id'], 'starter');
    expect(request['p_designated_hitter_id'], 'b9');
    expect(request['p_player_ids'], ['b2', 'b1', ...ids.skip(2)]);
    expect(request['p_defensive_positions']?.length, 9);
    expect(request['p_defensive_positions']?['starter'], 'P');
    expect(request['p_pitcher_bats'], isFalse);
  });

  test('an eligible player can pitch regardless of both profile positions', () {
    final player = SwlRosterPlayer.fromRows(
      {'player_id': 'b3'},
      {'id': 'b3', 'primary_position': 'LF', 'secondary_position': '1B'},
    );
    expect(player.positionLabel, 'LF / 1B');
    final draft = SwlLineupDraft([...ids], {...fullDefense});
    draft.assign(player.playerId, 'P');
    expect(draft.validate(), isNull);
    expect(payload(draft)['p_pitcher_id'], 'b3');
  });

  test(
    'assigning a new pitcher swaps the vacated position and keeps order',
    () {
      final draft = SwlLineupDraft([...ids], {'b1': 'P', 'b2': '1B'});
      draft.assign('b2', 'P');
      expect(draft.positions, {'b2': 'P', 'b1': '1B'});
      expect(draft.batting, ids);
      draft.assign('b3', '1B');
      expect(draft.positions, {'b2': 'P', 'b3': '1B'});
      draft.remove('b2');
      expect(draft.pitcherId, isNull);
      expect(draft.pitcherBats, isTrue);
    },
  );

  test(
    'swapping two occupied non-pitcher positions preserves batting order',
    () {
      final draft = SwlLineupDraft([...ids], {...fullDefense});
      final original = List<String>.of(draft.batting);
      final first = draft.positions.entries
          .firstWhere((e) => e.value == '1B')
          .key;
      final second = draft.positions.entries
          .firstWhere((e) => e.value == '2B')
          .key;
      draft.assign(first, '2B');
      expect(draft.positions[first], '2B');
      expect(draft.positions[second], '1B');
      expect(draft.batting, original);
      expect(draft.validate(), isNull);
    },
  );

  test('unlisted non-pitcher defender is rejected before the RPC', () {
    final defense = {...fullDefense};
    defense.remove('b2');
    defense['extra-defender'] = 'C';
    final draft = SwlLineupDraft([...ids], defense);
    expect(draft.validate(), contains('Cada defensor'));
    expect(() => payload(draft), throwsStateError);
  });

  test('cannot send a missing or defensively assigned BD', () {
    final draft = SwlLineupDraft(
      [...ids],
      {
        'starter': 'P',
        for (var i = 0; i < 8; i++) ids[i]: swlDefensivePositions[i + 1],
      },
      pitcherBats: false,
      designatedId: 'b1',
    );
    // The defense is complete and unique: the rejection must be about the DH.
    expect(draft.validate(), contains('designado'));
    expect(() => payload(draft), throwsStateError);
    draft.designatedId = 'b9';
    expect(draft.validate(), isNull);
    draft.assign('b9', 'C');
    expect(draft.designatedId, isNull);
    expect(draft.validate(), contains('designado'));
  });

  test(
    'invalid duplicate positions or extra player never reach save payload',
    () {
      final draft = SwlLineupDraft([...ids], {'b1': 'P', 'b2': 'P'});
      expect(() => payload(draft), throwsStateError);
      draft.positions.remove('b2');
      draft.positions['outside'] = 'C';
      // An unlisted defender and an incomplete defense must not be sent to LAB.
      expect(() => payload(draft), throwsStateError);
    },
  );

  test(
    'old lineups can save just the batting order using the legacy contract',
    () {
      final draft = SwlLineupDraft([...ids], {});
      expect(payload(draft, extended: false).keys.toSet(), {
        'p_game_id',
        'p_team_id',
        'p_player_ids',
        'p_expected_revision',
      });
      expect(() => payload(draft), throwsStateError);
    },
  );

  test(
    'secondary position is optional, standard and distinct from primary',
    () {
      expect(swlValidatePlayerPositions('P', '1B'), isNull);
      expect(swlValidatePlayerPositions('P', ''), isNull);
      expect(swlValidatePlayerPositions('', 'P'), isNotNull);
      expect(swlValidatePlayerPositions('p', 'P'), isNotNull);
      expect(swlValidatePlayerPositions('P', 'BD'), isNotNull);
    },
  );
  test('borrador recupera los turnos 12 y 13 con pitcher defensivo y DH', () {
    final batting = List.generate(13, (i) => 'b${i + 1}');
    final draft = SwlLineupDraft(
      batting,
      {
        'pitcher': 'P',
        for (var i = 0; i < 8; i++) batting[i]: swlDefensivePositions[i + 1],
      },
      pitcherBats: false,
      designatedId: 'b13',
    );
    draft.moveBatter(12, -1);

    final recovered = SwlLineupDraft.fromLocalJson(draft.toLocalJson(), {
      ...batting,
      'pitcher',
    });
    expect(recovered.batting.sublist(11), ['b13', 'b12']);
    expect(recovered.pitcherId, 'pitcher');
    expect(recovered.pitcherBats, false);
    expect(recovered.designatedId, 'b13');
    expect(payload(recovered)['p_player_ids'], recovered.batting);

    final withoutRemoved = SwlLineupDraft.fromLocalJson(
      draft.toLocalJson(),
      {...batting, 'pitcher'}..remove('b13'),
    );
    expect(withoutRemoved.batting.length, 12);
    expect(withoutRemoved.designatedId, isNull);
  });
}
