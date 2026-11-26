/// Validación pura de sustituciones. No modifica alineaciones ni marcador.
/// La activación requiere una RPC transaccional y un historial persistente.
class SwlSubstitutionRequest {
  final String gameId;
  final String teamId;
  final String outgoingPlayerId;
  final String incomingPlayerId;
  final int battingOrder;
  final int expectedLineupRevision;

  const SwlSubstitutionRequest({
    required this.gameId,
    required this.teamId,
    required this.outgoingPlayerId,
    required this.incomingPlayerId,
    required this.battingOrder,
    required this.expectedLineupRevision,
  });

  /// [activeOrder] is the CURRENT slot-to-player map, not the original lineup.
  /// [rosterIds] includes only currently active team roster members.
  void validate({
    required Map<int, String> activeOrder,
    required Set<String> rosterIds,
    required Set<String> previouslyRemovedPlayerIds,
    int? currentLineupRevision,
  }) {
    if (gameId.trim().isEmpty || teamId.trim().isEmpty)
      throw StateError('GAME_OR_TEAM_REQUIRED');
    if (battingOrder < 1 ||
        battingOrder > 13 ||
        !activeOrder.containsKey(battingOrder)) {
      throw StateError('INVALID_BATTING_SLOT');
    }
    if (expectedLineupRevision < 1) throw StateError('REVISION_REQUIRED');
    // Comparar contra la revisión leída del servidor antes de enviar la RPC.
    // La RPC debe repetir esta comparación de forma atómica.
    if (currentLineupRevision != null &&
        expectedLineupRevision != currentLineupRevision) {
      throw StateError('STALE_LINEUP_REVISION');
    }
    final outgoing = outgoingPlayerId.trim();
    final incoming = incomingPlayerId.trim();
    if (outgoing.isEmpty || incoming.isEmpty || outgoing == incoming) {
      throw StateError('INVALID_PLAYER_REPLACEMENT');
    }
    if (activeOrder[battingOrder]?.trim() != outgoing) {
      throw StateError('OUTGOING_PLAYER_NOT_IN_SLOT');
    }
    if (!rosterIds.any((id) => id.trim() == incoming)) {
      throw StateError('INCOMING_PLAYER_NOT_ON_ACTIVE_ROSTER');
    }
    if (activeOrder.values.any((id) => id.trim() == incoming)) {
      throw StateError('INCOMING_PLAYER_ALREADY_IN_LINEUP');
    }
    if (previouslyRemovedPlayerIds.any((id) => id.trim() == incoming)) {
      throw StateError('REENTRY_REQUIRES_EXPLICIT_RULE');
    }
  }
}

/// Distingue un rechazo explícito del servidor de un resultado incierto.
/// Sin código, errores de red (08xxx) y errores HTTP 5xx no se consideran
/// rechazo confirmado: la RPC podría haberse aplicado antes de perder respuesta.
bool swlIsExplicitSubstitutionRejection(String? code) {
  final value = code?.trim().toUpperCase() ?? '';
  if (value.isEmpty) return false;
  // Los codigos HTTP tienen exactamente tres digitos. SQLSTATE 23505
  // representa un rechazo explicito, no un codigo HTTP.
  if (RegExp(r'^[0-9]{3}$').hasMatch(value)) {
    final http = int.parse(value);
    return http >= 400 && http < 500;
  }
  if (value.startsWith('PGRST')) return true;
  if (RegExp(r'^[0-9A-Z]{5}$').hasMatch(value)) {
    return !value.startsWith('08') &&
        !value.startsWith('58') &&
        !value.startsWith('XX');
  }
  return false;
}

/// Identidades que ya ocupan un rol en una alineación confirmada.
Set<String> swlLineupParticipantIds(Map<String, dynamic> lineup) => {
  if (lineup['lineup'] case final List slots)
    for (final slot in slots.whereType<Map>())
      if (slot['player_id'] case final String id) id,
  if (lineup['defensive_positions'] case final Map positions)
    ...positions.keys.whereType<String>(),
  if (lineup['pitcher_id'] case final String id) id,
  if (lineup['designated_hitter_id'] case final String id) id,
};

bool swlCanSelectPitcher({
  required String candidate,
  required String currentPitcher,
  required bool pitcherBats,
  required Set<String> battingIds,
  required Set<String> defensiveIds,
  required Set<String> rivalIds,
  required Set<String> removedIds,
}) {
  if (candidate == currentPitcher ||
      rivalIds.contains(candidate) ||
      removedIds.contains(candidate))
    return false;
  if (pitcherBats) {
    return battingIds.contains(currentPitcher) &&
        battingIds.contains(candidate) &&
        defensiveIds.contains(candidate);
  }
  return !battingIds.contains(currentPitcher) &&
      !battingIds.contains(candidate) &&
      !defensiveIds.contains(candidate);
}
