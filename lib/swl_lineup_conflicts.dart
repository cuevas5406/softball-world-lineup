import 'package:supabase_flutter/supabase_flutter.dart';

import 'swl_substitution_rules.dart';

typedef SwlLineupConflict = ({
  bool rival,
  String gameId,
  String teamId,
  String? pin,
});

bool swlIsLineupConflict(Object error) =>
    error is PostgrestException &&
    const {
      'PELOTERO_EN_AMBOS_EQUIPOS',
      'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO',
    }.contains(error.message);

Map<String, Set<SwlLineupConflict>> swlFindLineupConflicts({
  required String gameId,
  required String teamId,
  required Set<String> candidates,
  required Map<String, String?> visibleGames,
  required Iterable<Map<String, dynamic>> lineups,
  required Iterable<Map<String, dynamic>> substitutions,
  required Iterable<Map<String, dynamic>> pitcherChanges,
}) {
  final result = <String, Set<SwlLineupConflict>>{};
  void add(Map<String, dynamic> row, String teamKey, Iterable<String> players) {
    final match = row['game_id'];
    final team = row[teamKey];
    if (match is! String ||
        team is! String ||
        !visibleGames.containsKey(match) ||
        (match == gameId && team == teamId)) {
      return;
    }
    for (final id in players.where(candidates.contains)) {
      (result[id] ??= {}).add((
        rival: match == gameId,
        gameId: match,
        teamId: team,
        pin: visibleGames[match],
      ));
    }
  }

  for (final row in lineups) {
    add(row, 'team_id', swlLineupParticipantIds(row));
  }
  for (final row in substitutions) {
    final data = row['event_data'];
    if (data is Map) {
      add(row, 'batting_team_id', [
        data['outgoing_player_id'],
        data['incoming_player_id'],
      ].whereType<String>());
    }
  }
  for (final row in pitcherChanges) {
    add(row, 'team_id', [
      row['old_pitcher_id'],
      row['new_pitcher_id'],
    ].whereType<String>());
  }
  return result;
}

Future<Map<String, Set<SwlLineupConflict>>> swlReadLineupConflicts(
  SupabaseClient client, {
  required String gameId,
  required String teamId,
  required String managerId,
  required Set<String> candidates,
}) async {
  Future<List<Map<String, dynamic>>> pages(
    Future<List<Map<String, dynamic>>> Function(int, int) read,
  ) async {
    const pageSize = 100;
    final rows = <Map<String, dynamic>>[];
    for (var start = 0; ; start += pageSize) {
      final page = await read(start, start + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) return rows;
    }
  }

  final games = await pages((from, to) => client
      .from('swl_live_games')
      .select('id,game_pin')
      .or('home_manager_id.eq.$managerId,away_manager_id.eq.$managerId')
      .inFilter('status', ['IN_PROGRESS', 'FINAL'])
      .order('id')
      .range(from, to));
  final current = await client.from('swl_live_games')
      .select('id,game_pin').eq('id', gameId).maybeSingle();
  final visible = <String, String?>{
    for (final game in [...games, if (current != null) current])
      game['id'] as String: game['game_pin'] as String?,
  };
  final ids = visible.keys.toList();
  final lineups = <Map<String, dynamic>>[];
  final substitutions = <Map<String, dynamic>>[];
  final pitcherChanges = <Map<String, dynamic>>[];
  for (var start = 0; start < ids.length; start += 25) {
    final batch = ids.skip(start).take(25).toList();
    final rows = await Future.wait([
      pages((from, to) => client.from('swl_game_lineups')
          .select('game_id,team_id,lineup,pitcher_id,designated_hitter_id,defensive_positions')
          .inFilter('game_id', batch).order('game_id').order('team_id')
          .range(from, to)),
      pages((from, to) => client.from('swl_game_events')
          .select('game_id,batting_team_id,event_data')
          .inFilter('game_id', batch).eq('event_type', 'SUBSTITUTION')
          .order('id').range(from, to)),
      pages((from, to) => client.from('swl_v56_pitcher_changes')
          .select('game_id,team_id,old_pitcher_id,new_pitcher_id')
          .inFilter('game_id', batch).order('game_id').order('version')
          .order('team_id').range(from, to)),
    ]);
    lineups.addAll(rows[0]);
    substitutions.addAll(rows[1]);
    pitcherChanges.addAll(rows[2]);
  }
  return swlFindLineupConflicts(
    gameId: gameId, teamId: teamId, candidates: candidates,
    visibleGames: visible, lineups: lineups,
    substitutions: substitutions, pitcherChanges: pitcherChanges,
  );
}
