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
  }) {
    if (gameId.isEmpty || teamId.isEmpty) throw StateError('GAME_OR_TEAM_REQUIRED');
    if (battingOrder < 1 || battingOrder > 13 ||
        !activeOrder.containsKey(battingOrder)) {
      throw StateError('INVALID_BATTING_SLOT');
    }
    if (expectedLineupRevision < 1) throw StateError('REVISION_REQUIRED');
    if (outgoingPlayerId.isEmpty || incomingPlayerId.isEmpty ||
        outgoingPlayerId == incomingPlayerId) {
      throw StateError('INVALID_PLAYER_REPLACEMENT');
    }
    if (activeOrder[battingOrder] != outgoingPlayerId) {
      throw StateError('OUTGOING_PLAYER_NOT_IN_SLOT');
    }
    if (!rosterIds.contains(incomingPlayerId)) {
      throw StateError('INCOMING_PLAYER_NOT_ON_ACTIVE_ROSTER');
    }
    if (activeOrder.values.contains(incomingPlayerId)) {
      throw StateError('INCOMING_PLAYER_ALREADY_IN_LINEUP');
    }
    if (previouslyRemovedPlayerIds.contains(incomingPlayerId)) {
      throw StateError('REENTRY_REQUIRES_EXPLICIT_RULE');
    }
  }
}
