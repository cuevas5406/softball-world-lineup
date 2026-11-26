/// Identidad persistente para vincular estadísticas con peloteros reales.
/// Un nombre o número de uniforme nunca identifica por sí solo a un pelotero.
class SwlLineupEntry {
  final String? playerId;
  final String name;
  final String number;
  final String role;
  final String position;

  const SwlLineupEntry({required this.playerId, required this.name,
    required this.number, required this.role, required this.position});

  Map<String, dynamic> toJson() => {
    'player_id': playerId,
    'name': name,
    'number': number,
    'batting_role': role,
    'defensive_position': position,
  };

  static SwlLineupEntry fromJson(Map<String, dynamic> json) => SwlLineupEntry(
    playerId: json['player_id'] as String?,
    name: json['name'] as String,
    number: json['number'] as String,
    role: json['batting_role'] as String,
    position: json['defensive_position'] as String,
  );
}

class SwlLineupIdentity {
  static const positions = {'SIN','P','C','1B','2B','3B','SS','LF','CF','RF'};
  static const roles = {'REGULAR','DH','AH'};

  /// Validación estricta antes de enviar alineaciones al servidor.
  /// [requireIds] debe ser true al activar estadísticas individuales reales.
  static void validate(List<SwlLineupEntry> lineup, {bool requireIds = false}) {
    if (lineup.length < 9 || lineup.length > 13) {
      throw StateError('LINEUP_SIZE_INVALID');
    }
    final ids = <String>{};
    final names = <String>{};
    final numbers = <String>{};
    final defense = <String>{};
    var dh = 0;
    for (final entry in lineup) {
      if (entry.name.trim().isEmpty) throw StateError('PLAYER_NAME_REQUIRED');
      if (!names.add(entry.name.trim().toLowerCase())) throw StateError('DUPLICATE_NAME');
      if (!roles.contains(entry.role)) throw StateError('INVALID_ROLE');
      if (!positions.contains(entry.position)) throw StateError('INVALID_POSITION');
      if (entry.role == 'DH') dh++;
      if (entry.role != 'REGULAR' && entry.position != 'SIN') {
        throw StateError('OFFENSE_ONLY_POSITION');
      }
      if (entry.position != 'SIN' && !defense.add(entry.position)) {
        throw StateError('DUPLICATE_DEFENSIVE_POSITION');
      }
      if (entry.number.trim().isNotEmpty && entry.number != '-' &&
          !numbers.add(entry.number.trim())) throw StateError('DUPLICATE_NUMBER');
      final id = entry.playerId;
      if (requireIds && (id == null || id.isEmpty)) throw StateError('PLAYER_ID_REQUIRED');
      if (id != null && (id.isEmpty || !ids.add(id))) throw StateError('DUPLICATE_OR_EMPTY_ID');
    }
    if (dh > 1) throw StateError('MULTIPLE_DH');
    if (dh == 1 && defense.contains('P')) throw StateError('DH_WITH_BATTING_PITCHER');
  }

  static List<Map<String, dynamic>> payload(List<SwlLineupEntry> lineup,
      {bool requireIds = true}) {
    validate(lineup, requireIds: requireIds);
    return [for (var i = 0; i < lineup.length; i++)
      {'batting_order': i + 1, ...lineup[i].toJson()}];
  }
}

/// Comprueba el orden declarado por el servidor antes de atribuir una jugada.
List<Map> swlConfirmedBattingSlots(Object? raw) {
  if (raw is! List || raw.isEmpty) return const [];
  final byOrder = <int, Map>{};
  final ids = <String>{};
  for (final slot in raw) {
    if (slot is! Map) return const [];
    final order = slot['order'] ?? slot['batting_order'];
    final id = slot['player_id']?.toString();
    if (order is! int || order < 1 || order > raw.length ||
        byOrder.containsKey(order) || id == null || id.isEmpty || !ids.add(id)) {
      return const [];
    }
    byOrder[order] = slot;
  }
  return [for (var order = 1; order <= byOrder.length; order++) byOrder[order]!];
}

/// The first turn is implicit until the server creates a cursor for this team.
int? swlBattingOrder(Map? cursor, int lineupLength) {
  final order = cursor == null ? 1 : int.tryParse('${cursor['next_order']}');
  return order != null && order >= 1 && order <= lineupLength ? order : null;
}

({String playerId, int order})? swlResolveBattingTurn(Object? lineup, Map? cursor) {
  final slots = swlConfirmedBattingSlots(lineup);
  final order = swlBattingOrder(cursor, slots.length);
  if (order == null) return null;
  return (playerId: slots[order - 1]['player_id'].toString(), order: order);
}
