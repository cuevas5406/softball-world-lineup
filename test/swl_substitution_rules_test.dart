import 'package:flutter_test/flutter_test.dart';
import '../lib/swl_substitution_rules.dart';

void main() {
  const request = SwlSubstitutionRequest(
    gameId: 'game', teamId: 'team', outgoingPlayerId: 'a',
    incomingPlayerId: 'c', battingOrder: 1, expectedLineupRevision: 2);
  const roster = {'a', 'b', 'c'};
  test('accepts valid distinct roster replacement', () {
    expect(() => request.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {}), returnsNormally);
  });
  test('rejects whitespace-only player identifiers', () {
    const invalid = SwlSubstitutionRequest(gameId: 'game', teamId: 'team',
      outgoingPlayerId: 'a', incomingPlayerId: '   ',
      battingOrder: 1, expectedLineupRevision: 2);
    expect(() => invalid.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: {...roster, '   '}, previouslyRemovedPlayerIds: {}),
      throwsA(isA<StateError>()));
  });
  test('rejects whitespace-only game identifier', () {
    const invalid = SwlSubstitutionRequest(gameId: '  ', teamId: 'team',
      outgoingPlayerId: 'a', incomingPlayerId: 'c',
      battingOrder: 1, expectedLineupRevision: 2);
    expect(() => invalid.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {}),
      throwsA(isA<StateError>()));
  });
  test('rejects stale outgoing slot', () {
    expect(() => request.validate(activeOrder: {1: 'b', 2: 'a'},
      rosterIds: roster, previouslyRemovedPlayerIds: {}),
      throwsA(isA<StateError>()));
  });
  test('rejects player already in lineup', () {
    const duplicate = SwlSubstitutionRequest(gameId: 'game', teamId: 'team',
      outgoingPlayerId: 'a', incomingPlayerId: 'b',
      battingOrder: 1, expectedLineupRevision: 2);
    expect(() => duplicate.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {}),
      throwsA(isA<StateError>()));
  });
  test('rejects player no longer on active roster', () {
    expect(() => request.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: {'a', 'b'}, previouslyRemovedPlayerIds: {}),
      throwsA(isA<StateError>()));
  });
  test('rejects missing batting slot', () {
    expect(() => request.validate(activeOrder: {2: 'a'},
      rosterIds: roster, previouslyRemovedPlayerIds: {}),
      throwsA(isA<StateError>()));
  });
  test('rejects the same outgoing and incoming player', () {
    const invalid = SwlSubstitutionRequest(gameId: 'game', teamId: 'team',
      outgoingPlayerId: 'a', incomingPlayerId: 'a',
      battingOrder: 1, expectedLineupRevision: 2);
    expect(() => invalid.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {}),
      throwsA(isA<StateError>()));
  });
  test('rejects same player with padded identifier', () {
    const invalid = SwlSubstitutionRequest(gameId: 'game', teamId: 'team',
      outgoingPlayerId: ' a ', incomingPlayerId: 'a',
      battingOrder: 1, expectedLineupRevision: 2);
    expect(() => invalid.validate(activeOrder: {1: 'a'},
      rosterIds: roster, previouslyRemovedPlayerIds: {}), throwsStateError);
  });
  test('rejects already active player with padded identifier', () {
    const invalid = SwlSubstitutionRequest(gameId: 'game', teamId: 'team',
      outgoingPlayerId: 'a', incomingPlayerId: ' b ',
      battingOrder: 1, expectedLineupRevision: 2);
    expect(() => invalid.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {}), throwsStateError);
  });
  test('rejects reentry with padded identifier', () {
    const invalid = SwlSubstitutionRequest(gameId: 'game', teamId: 'team',
      outgoingPlayerId: 'a', incomingPlayerId: ' c ',
      battingOrder: 1, expectedLineupRevision: 2);
    expect(() => invalid.validate(activeOrder: {1: 'a'},
      rosterIds: roster, previouslyRemovedPlayerIds: {'c'}), throwsStateError);
  });
  test('rejects missing revision', () {
    const invalid = SwlSubstitutionRequest(gameId: 'game', teamId: 'team',
      outgoingPlayerId: 'a', incomingPlayerId: 'c',
      battingOrder: 1, expectedLineupRevision: 0);
    expect(() => invalid.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {}),
      throwsA(isA<StateError>()));
  });
  test('rejects reentry until league rule is specified', () {
    expect(() => request.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {'c'}),
      throwsA(isA<StateError>()));
  });
  test('accepts matching current lineup revision', () {
    expect(() => request.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {},
      currentLineupRevision: 2), returnsNormally);
  });
  test('rejects outdated lineup revision before substitution', () {
    expect(() => request.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {},
      currentLineupRevision: 3), throwsStateError);
  });
  test('rejects future lineup revision before substitution', () {
    expect(() => request.validate(activeOrder: {1: 'a', 2: 'b'},
      rosterIds: roster, previouslyRemovedPlayerIds: {},
      currentLineupRevision: 1), throwsStateError);
  });

}
