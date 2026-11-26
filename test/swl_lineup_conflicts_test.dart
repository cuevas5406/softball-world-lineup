import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_lineup_conflicts.dart';
import '../lib/swl_lineup_draft.dart';

void main() {
  test('reports all readable matches by UUID and deduplicates memberships', () {
    final conflicts = swlFindLineupConflicts(
      gameId: 'game',
      teamId: 'own',
      candidates: {'pitcher', 'dh', 'replaced', 'own-player', 'hidden'},
      visibleGames: {'game': 'SWL-123456', 'active': 'SWL-234567'},
      lineups: [
        {'game_id': 'game', 'team_id': 'own', 'pitcher_id': 'own-player'},
        {'game_id': 'game', 'team_id': 'rival', 'pitcher_id': 'pitcher'},
        {'game_id': 'active', 'team_id': 'other', 'designated_hitter_id': 'dh'},
        {'game_id': 'unreadable', 'team_id': 'other', 'pitcher_id': 'hidden'},
      ],
      substitutions: [
        {
          'game_id': 'active',
          'batting_team_id': 'other',
          'event_data': {'outgoing_player_id': 'replaced', 'incoming_player_id': 'dh'},
        },
      ],
      pitcherChanges: [
        {'game_id': 'game', 'team_id': 'rival', 'new_pitcher_id': 'pitcher'},
      ],
    );
    expect(conflicts.keys, unorderedEquals(['pitcher', 'dh', 'replaced']));
    expect(conflicts['pitcher']!.single.rival, isTrue);
    expect(conflicts['dh']!.single.rival, isFalse);
    expect(conflicts['dh']!.single.pin, 'SWL-234567');
    expect(conflicts['replaced']!.single.teamId, 'other');
  });

  test('replaces in place, retaining the other slots, defense and DH mode', () {
    final draft = SwlLineupDraft(
      ['first', 'second', 'dh', 'fourth', 'fifth', 'sixth'],
      {'pitcher': 'P', 'first': '1B', 'sixth': 'CF'},
      pitcherBats: false,
      designatedId: 'dh',
    );
    expect(draft.replaceParticipant('sixth', 'first'), isFalse);
    expect(draft.replaceParticipant('sixth', 'new-sixth'), isTrue);
    expect(draft.replaceParticipant('pitcher', 'new-pitcher'), isTrue);
    expect(draft.replaceParticipant('dh', 'new-dh'), isTrue);
    final restored = SwlLineupDraft.fromLocalJson(draft.toLocalJson(), {
      'first', 'second', 'new-dh', 'fourth', 'fifth', 'new-sixth', 'new-pitcher',
    });
    expect(restored.batting, [
      'first', 'second', 'new-dh', 'fourth', 'fifth', 'new-sixth',
    ]);
    expect(restored.positions, {'first': '1B', 'new-sixth': 'CF', 'new-pitcher': 'P'});
    expect(restored.designatedId, 'new-dh');
    expect(restored.pitcherBats, isFalse);
  });
}
