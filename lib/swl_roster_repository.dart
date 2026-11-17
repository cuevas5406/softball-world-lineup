import 'package:supabase_flutter/supabase_flutter.dart';

/// Lectura de fichajes activos. No concede permisos ni altera el roster.
class SwlRosterPlayer {
  final String playerId;
  final String universalId;
  final String name;
  final String number;
  final String position;
  final bool isRefuerzo;

  const SwlRosterPlayer({required this.playerId, required this.universalId,
    required this.name, required this.number, required this.position,
    required this.isRefuerzo});

  factory SwlRosterPlayer.fromRows(Map<String, dynamic> roster,
      Map<String, dynamic> player) {
    final id = player['id']?.toString() ?? '';
    if (id.isEmpty || roster['player_id']?.toString() != id) {
      throw StateError('ROSTER_PLAYER_MISMATCH');
    }
    final name = [player['first_name'], player['last_name']]
        .map((part) => part?.toString().trim() ?? '')
        .where((part) => part.isNotEmpty).join(' ');
    return SwlRosterPlayer(playerId: id,
      universalId: player['universal_id']?.toString() ?? '',
      name: name.isEmpty ? 'Sin nombre' : name,
      number: player['jersey_number']?.toString() ?? '',
      position: player['primary_position']?.toString() ?? '',
      isRefuerzo: roster['is_refuerzo'] == true);
  }
}

class SwlRosterRepository {
  final SupabaseClient client;
  const SwlRosterRepository(this.client);

  /// Consulta separada para evitar depender de relaciones PostgREST inferidas.
  /// Solo rosters no retirados; conserva UUID para futuras alineaciones.
  Future<List<SwlRosterPlayer>> activePlayers(String teamId) async {
    if (teamId.isEmpty) throw ArgumentError('TEAM_ID_REQUIRED');
    final rosterRows = List<Map<String, dynamic>>.from(await client
        .from('rosters').select('player_id,is_refuerzo')
        .eq('team_id', teamId).isFilter('removed_at', null));
    final ids = rosterRows.map((r) => r['player_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return [];
    final players = List<Map<String, dynamic>>.from(await client
        .from('players')
        .select('id,universal_id,first_name,last_name,jersey_number,primary_position')
        .inFilter('id', ids));
    final byId = {for (final player in players) player['id'].toString(): player};
    final result = <SwlRosterPlayer>[];
    final seen = <String>{};
    for (final roster in rosterRows) {
      final id = roster['player_id']?.toString();
      if (id == null || !seen.add(id)) continue;
      final player = byId[id];
      if (player == null) continue;
      result.add(SwlRosterPlayer.fromRows(roster, player));
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }
}
