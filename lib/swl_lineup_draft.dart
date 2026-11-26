const swlDefensivePositions = [
  'P',
  'C',
  '1B',
  '2B',
  '3B',
  'SS',
  'LF',
  'CF',
  'RF',
  'SF',
];

class SwlLineupDraft {
  /// Batting candidates in order; defensive-only players live in [positions].
  final List<String> selected;
  final Map<String, String> positions;
  bool pitcherBats;
  String? designatedId;

  SwlLineupDraft(
    this.selected,
    this.positions, {
    this.pitcherBats = true,
    this.designatedId,
  });

  Map<String, dynamic> toLocalJson() => {
    'selected': List<String>.of(selected),
    'positions': Map<String, String>.of(positions),
    'pitcherBats': pitcherBats,
    'designatedId': designatedId,
  };

  factory SwlLineupDraft.fromLocalJson(
    Map<String, dynamic> json,
    Set<String> activeIds,
  ) {
    final selected = (json['selected'] as List)
        .whereType<String>()
        .where(activeIds.contains)
        .toSet()
        .take(13)
        .toList();
    final positions = <String, String>{};
    for (final entry in (json['positions'] as Map).entries) {
      final id = entry.key;
      final position = entry.value;
      if (id is String &&
          activeIds.contains(id) &&
          position is String &&
          swlDefensivePositions.contains(position) &&
          !positions.containsValue(position)) {
        positions[id] = position;
      }
    }
    final pitcherBats =
        json['pitcherBats'] != false || !positions.containsValue('P');
    if (!pitcherBats) {
      selected.remove(
        positions.entries.firstWhere((entry) => entry.value == 'P').key,
      );
    }
    final designated = json['designatedId'];
    return SwlLineupDraft(
      selected,
      positions,
      pitcherBats: pitcherBats,
      designatedId:
          !pitcherBats &&
              designated is String &&
              selected.contains(designated) &&
              !positions.containsKey(designated)
          ? designated
          : null,
    );
  }

  String? get pitcherId {
    for (final entry in positions.entries) {
      if (entry.value == 'P') return entry.key;
    }
    return null;
  }

  List<String> get batting =>
      selected.where((id) => pitcherBats || id != pitcherId).toList();

  void remove(String id) {
    selected.remove(id);
    assign(id, null);
  }

  bool replaceParticipant(String outgoing, String incoming) {
    if (selected.contains(incoming) ||
        positions.containsKey(incoming) || designatedId == incoming) {
      return false;
    }
    final index = selected.indexOf(outgoing);
    final position = positions[outgoing];
    if (index < 0 && position == null) return false;
    if (index >= 0) selected[index] = incoming;
    if (position != null) {
      positions.remove(outgoing);
      positions[incoming] = position;
    }
    if (designatedId == outgoing) designatedId = incoming;
    return true;
  }

  void setBatting(String id, bool bats) {
    if (bats && !selected.contains(id)) selected.add(id);
    if (!bats) selected.remove(id);
  }

  void assign(String id, String? position) {
    final previousPitcher = pitcherId;
    final previous = positions[id];
    final occupant = positions.entries
        .where((entry) => entry.value == position)
        .firstOrNull
        ?.key;
    if (occupant == id) return;
    // Keep batting order independent of defense, except when a new
    // defense-only pitcher would otherwise remain in the batting order.
    positions.remove(id);
    if (occupant != null) {
      positions.remove(occupant);
      if (previous != null) positions[occupant] = previous;
    }
    if (position != null) positions[id] = position;
    final newPitcher = pitcherId;
    if (newPitcher == null) pitcherBats = true;
    if (!pitcherBats && newPitcher != previousPitcher) {
      selected.remove(newPitcher);
    }
    if (pitcherBats ||
        positions.containsKey(designatedId) ||
        !selected.contains(designatedId))
      designatedId = null;
  }

  void moveBatter(int index, int offset) {
    final order = batting;
    final target = index + offset;
    if (index < 0 ||
        index >= order.length ||
        target < 0 ||
        target >= order.length) {
      return;
    }
    final first = selected.indexOf(order[index]);
    final second = selected.indexOf(order[target]);
    selected[first] = order[target];
    selected[second] = order[index];
  }

  String? validate({bool requireDefense = true}) {
    final order = batting;
    if (order.length < 9 || order.length > 13) {
      return 'El orden al bate debe tener entre 9 y 13 peloteros.';
    }
    if (selected.toSet().length != selected.length) {
      return 'Hay un pelotero repetido en la alineación.';
    }
    if (positions.values.any((pos) => !swlDefensivePositions.contains(pos)) ||
        positions.values.toSet().length != positions.length) {
      return 'Cada posición defensiva debe ser válida y tener un solo pelotero seleccionado.';
    }
    // LAB swl_v56_save_lineup requires a pitcher and 9-10 defensive
    // assignments. Reject incomplete drafts before invoking the RPC.
    if (requireDefense && pitcherId == null) {
      return 'Asigna un pitcher titular en la posición P.';
    }
    if (requireDefense && (positions.length < 9 || positions.length > 10)) {
      return 'Asigna entre 9 y 10 posiciones defensivas antes de guardar.';
    }
    // LAB only accepts batting players and the pitcher as defenders.
    if (requireDefense &&
        positions.keys.any((id) => id != pitcherId && !order.contains(id))) {
      return 'Cada defensor debe estar en el orden al bate, salvo el pitcher que no batea.';
    }
    if (requireDefense && pitcherBats && !order.contains(pitcherId)) {
      return 'El pitcher debe estar en el orden solo cuando batea.';
    }
    if (requireDefense && !pitcherBats && selected.contains(pitcherId)) {
      return 'Si el pitcher no batea, retíralo del orden al bate.';
    }
    if (requireDefense &&
        (pitcherBats
            ? designatedId != null
            : designatedId == null ||
                  !order.contains(designatedId) ||
                  positions.containsKey(designatedId) ||
                  designatedId == pitcherId)) {
      return 'Elige un bateador designado del orden al bate sin posición defensiva.';
    }
    return null;
  }

  Map<String, dynamic> saveParameters({
    required String gameId,
    required String teamId,
    required int revision,
    required bool extended,
  }) {
    final error = validate(requireDefense: extended);
    if (error != null) throw StateError(error);
    if (!extended && positions.isNotEmpty) {
      throw StateError('El guardado de la defensa requiere la RPC extendida.');
    }
    return {
      'p_game_id': gameId,
      'p_team_id': teamId,
      'p_player_ids': batting,
      'p_expected_revision': revision,
      if (extended) 'p_pitcher_id': pitcherId,
      if (extended) 'p_pitcher_bats': pitcherBats,
      if (extended) 'p_designated_hitter_id': designatedId,
      if (extended) 'p_defensive_positions': Map<String, String>.of(positions),
    };
  }
}
