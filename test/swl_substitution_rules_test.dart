import 'package:softball_world_lineup/swl_lineup_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_substitution_rules.dart';

void main() {
  const request = SwlSubstitutionRequest(
    gameId: 'game',
    teamId: 'team',
    outgoingPlayerId: 'a',
    incomingPlayerId: 'c',
    battingOrder: 1,
    expectedLineupRevision: 2,
  );
  const roster = {'a', 'b', 'c'};
  test('accepts valid distinct roster replacement', () {
    expect(
      () => request.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
      ),
      returnsNormally,
    );
  });
  test('rejects whitespace-only player identifiers', () {
    const invalid = SwlSubstitutionRequest(
      gameId: 'game',
      teamId: 'team',
      outgoingPlayerId: 'a',
      incomingPlayerId: '   ',
      battingOrder: 1,
      expectedLineupRevision: 2,
    );
    expect(
      () => invalid.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: {...roster, '   '},
        previouslyRemovedPlayerIds: {},
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('rejects whitespace-only game identifier', () {
    const invalid = SwlSubstitutionRequest(
      gameId: '  ',
      teamId: 'team',
      outgoingPlayerId: 'a',
      incomingPlayerId: 'c',
      battingOrder: 1,
      expectedLineupRevision: 2,
    );
    expect(
      () => invalid.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('rejects stale outgoing slot', () {
    expect(
      () => request.validate(
        activeOrder: {1: 'b', 2: 'a'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('rejects player already in lineup', () {
    const duplicate = SwlSubstitutionRequest(
      gameId: 'game',
      teamId: 'team',
      outgoingPlayerId: 'a',
      incomingPlayerId: 'b',
      battingOrder: 1,
      expectedLineupRevision: 2,
    );
    expect(
      () => duplicate.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('rejects player no longer on active roster', () {
    expect(
      () => request.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: {'a', 'b'},
        previouslyRemovedPlayerIds: {},
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('rejects missing batting slot', () {
    expect(
      () => request.validate(
        activeOrder: {2: 'a'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('rejects the same outgoing and incoming player', () {
    const invalid = SwlSubstitutionRequest(
      gameId: 'game',
      teamId: 'team',
      outgoingPlayerId: 'a',
      incomingPlayerId: 'a',
      battingOrder: 1,
      expectedLineupRevision: 2,
    );
    expect(
      () => invalid.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('rejects same player with padded identifier', () {
    const invalid = SwlSubstitutionRequest(
      gameId: 'game',
      teamId: 'team',
      outgoingPlayerId: ' a ',
      incomingPlayerId: 'a',
      battingOrder: 1,
      expectedLineupRevision: 2,
    );
    expect(
      () => invalid.validate(
        activeOrder: {1: 'a'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
      ),
      throwsStateError,
    );
  });
  test('rejects already active player with padded identifier', () {
    const invalid = SwlSubstitutionRequest(
      gameId: 'game',
      teamId: 'team',
      outgoingPlayerId: 'a',
      incomingPlayerId: ' b ',
      battingOrder: 1,
      expectedLineupRevision: 2,
    );
    expect(
      () => invalid.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
      ),
      throwsStateError,
    );
  });
  test('rejects reentry with padded identifier', () {
    const invalid = SwlSubstitutionRequest(
      gameId: 'game',
      teamId: 'team',
      outgoingPlayerId: 'a',
      incomingPlayerId: ' c ',
      battingOrder: 1,
      expectedLineupRevision: 2,
    );
    expect(
      () => invalid.validate(
        activeOrder: {1: 'a'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {'c'},
      ),
      throwsStateError,
    );
  });
  test('rejects missing revision', () {
    const invalid = SwlSubstitutionRequest(
      gameId: 'game',
      teamId: 'team',
      outgoingPlayerId: 'a',
      incomingPlayerId: 'c',
      battingOrder: 1,
      expectedLineupRevision: 0,
    );
    expect(
      () => invalid.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('rejects reentry until league rule is specified', () {
    expect(
      () => request.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {'c'},
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('accepts matching current lineup revision', () {
    expect(
      () => request.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
        currentLineupRevision: 2,
      ),
      returnsNormally,
    );
  });
  test('rejects outdated lineup revision before substitution', () {
    expect(
      () => request.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
        currentLineupRevision: 3,
      ),
      throwsStateError,
    );
  });
  test('rejects future lineup revision before substitution', () {
    expect(
      () => request.validate(
        activeOrder: {1: 'a', 2: 'b'},
        rosterIds: roster,
        previouslyRemovedPlayerIds: {},
        currentLineupRevision: 1,
      ),
      throwsStateError,
    );
  });

  test('sustituye el sexto turno y otro futuro sin alterar el primero', () {
    final lineup = [
      for (var order = 1; order <= 9; order++)
        {'order': order, 'player_id': 'p$order'},
    ];
    final statistics = {'p6': 1};
    final cursor = {'next_order': 6};
    final current = swlResolveBattingTurn(lineup, cursor)!;
    expect(current.playerId, 'p6');
    for (final (turn, incoming) in [
      (current.order, 'suplente'),
      (8, 'anticipado'),
    ]) {
      final order = {
        for (final slot in lineup)
          slot['order'] as int: slot['player_id'] as String,
      };
      SwlSubstitutionRequest(
        gameId: 'partido',
        teamId: 'local',
        outgoingPlayerId: order[turn]!,
        incomingPlayerId: incoming,
        battingOrder: turn,
        expectedLineupRevision: 2,
      ).validate(
        activeOrder: order,
        rosterIds: {'suplente', 'anticipado'},
        previouslyRemovedPlayerIds: {},
        currentLineupRevision: 2,
      );
      lineup[turn - 1]['player_id'] = incoming;
    }
    final batterOnNextHit = swlResolveBattingTurn(lineup, cursor)!.playerId;
    statistics.update(batterOnNextHit, (hits) => hits + 1, ifAbsent: () => 1);
    expect(lineup[0]['player_id'], 'p1');
    expect(lineup[5]['player_id'], 'suplente');
    expect(lineup[7]['player_id'], 'anticipado');
    expect(statistics, {'p6': 1, 'suplente': 1});
  });

  test('la elegibilidad usa UUID de ambos equipos y cubre pitcher con DH', () {
    final rival = swlLineupParticipantIds({
      'lineup': [
        {'player_id': 'rival-al-bate', 'order': 1},
      ],
      'defensive_positions': {'rival-defensa': 'P'},
      'pitcher_id': 'rival-defensa',
      'designated_hitter_id': 'rival-dh',
    });
    const batting = {'defensor', 'dh'};
    const defenders = {'pitcher', 'defensor'};
    bool eligible(String player, bool pitcherBats) => swlCanSelectPitcher(
      candidate: player,
      currentPitcher: 'pitcher',
      pitcherBats: pitcherBats,
      battingIds: {...batting, if (pitcherBats) 'pitcher'},
      defensiveIds: defenders,
      rivalIds: rival,
      removedIds: {'removido'},
    );
    expect(eligible('defensor', true), isTrue);
    expect(eligible('banco', true), isFalse);
    expect(eligible('banco', false), isTrue);
    for (final id in [
      'pitcher',
      'dh',
      'defensor',
      'rival-al-bate',
      'rival-defensa',
      'rival-dh',
      'removido',
    ]) {
      expect(eligible(id, false), isFalse, reason: id);
    }
  });
}
