typedef _Runner = ({
  String? pitcher,
  int stint,
  bool reachedOnError,
  bool ghost,
});
typedef _Play = Map<String, dynamic>;

/// Replays each half with the UUIDs and versions recorded by the server.
class SwlPitchRunCredit {
  final firstPitchVersion = <String, int>{};
  final charged = <String, Map<String, int>>{};
  final earned = <String, Map<String, int>>{};
  final teamEarned = <String, int>{};
  final _unknownCharge = <String>{};
  final _unknownEarned = <String, Set<String>>{};
  final _unknownTeamEarned = <String>{};

  int? runs(String team, String id) =>
      _unknownCharge.contains(team) ? null : charged[team]?[id] ?? 0;

  int? cleanRuns(String team, String id) =>
      _unknownCharge.contains(team) ||
          (_unknownEarned[team]?.contains(id) ?? false)
      ? null
      : earned[team]?[id] ?? 0;

  int? cleanTotal(String team) =>
      _unknownTeamEarned.contains(team) ? null : teamEarned[team] ?? 0;

  String runsLabel(String team, String id) =>
      _label(runs(team, id), charged[team]?[id]);

  String cleanLabel(String team, String id) =>
      _label(cleanRuns(team, id), earned[team]?[id]);

  String cleanTotalLabel(String team) =>
      _label(cleanTotal(team), teamEarned[team]);

  static String _label(int? total, int? minimum) =>
      total?.toString() ?? ((minimum ?? 0) > 0 ? '≥$minimum' : '—');

  SwlPitchRunCredit(
    _Play game,
    List<_Play> events,
    List<_Play> pitches,
    Set<int?> undone,
  ) {
    final home = game['home_team_id'];
    final away = game['away_team_id'];
    for (final row in pitches) {
      if (row['pitcher_id'] case final String id) {
        if (row['version'] case final int version) {
          firstPitchVersion.update(
            id,
            (old) => old < version ? old : version,
            ifAbsent: () => version,
          );
        }
      }
    }
    final owners = {
      for (final p in pitches)
        if (p['pitcher_id'] case final String id) p['version']: id,
    };
    final creditedOuts = {
      for (final p in pitches)
        if (p['outs'] case final num outs) p['version']: outs.toInt(),
    };
    final half = <(Object?, String), List<_Play>>{};
    for (final e in events) {
      final team = e['batting_team_id'];
      if (!undone.contains(e['version']) &&
          team is String &&
          (team == home || team == away)) {
        (half[(e['inning'], team)] ??= []).add(e);
      }
    }
    final recorded = <String, int>{};
    for (final entry in half.entries) {
      final team = (entry.key.$2 == home ? away : home) as String;
      final runs = _replayHalf(team, entry.value, owners, creditedOuts);
      recorded.update(team, (total) => total + runs, ifAbsent: () => runs);
    }
    for (final (team, goal) in [
      (home, game['away_runs']),
      (away, game['home_runs']),
    ]) {
      if (team is String && goal is num && (recorded[team] ?? 0) != goal) {
        _unknownCharge.add(team);
        _unknownTeamEarned.add(team);
      }
    }
  }

  int _replayHalf(
    String team,
    List<_Play> plays,
    Map<Object?, String> owners,
    Map<Object?, int> creditedOuts,
  ) {
    plays.sort((a, b) => (a['version'] as num).compareTo(b['version'] as num));
    final bases = <String, _Runner>{};
    final stintMisses = <int, int>{};
    final stintUnknownOuts = <int, int>{};
    var stint = 0;
    var actualOuts = 0;
    var missedOuts = 0;
    var unknownOuts = 0;
    var recorded = 0;
    var uncertainErrorAdvance = false;
    final uncertainRunners = <String>{};
    var unidentifiedAdvance = false;
    String? activePitcher;
    for (final play in plays) {
      final data = play['event_data'];
      if (data is! Map) continue;
      final type = play['event_type'];
      final pitcher = owners[play['version']];
      if (pitcher != null && pitcher != activePitcher) {
        activePitcher = pitcher;
        stintMisses[++stint] = missedOuts;
        stintUnknownOuts[stint] = unknownOuts;
      }
      if (type == 'SUBSTITUTION') {
        final runner = bases.remove(data['outgoing_player_id']);
        final incoming = data['incoming_player_id'];
        if (runner != null && incoming is String) {
          bases[incoming] = runner;
          if (uncertainRunners.remove(data['outgoing_player_id'])) {
            uncertainRunners.add(incoming);
          }
        }
        continue;
      }
      if (type == 'RUNNER_REPLACE' && data['outgoing_player_id'] is String) {
        final runner = bases.remove(data['outgoing_player_id']);
        final incoming = data['incoming_player_id'] ?? data['runner_id'];
        if (runner != null && incoming is String) {
          bases[incoming] = runner;
          if (uncertainRunners.remove(data['outgoing_player_id'])) {
            uncertainRunners.add(incoming);
          }
        }
        continue;
      }
      if (type == 'GHOST_RUNNER') {
        final id = data['runner_id'] ?? data['player_id'];
        if (id is String) {
          bases[id] = (
            pitcher: null,
            stint: stint,
            reachedOnError: false,
            ghost: true,
          );
        }
      }

      final batter = data['batter_id'];
      final homer = type == 'HIT' && data['batter_base'] == 4;
      final completed = data['plate_appearance_completed'] == true;
      final error = type == 'ERROR';
      final reached =
          type == 'HIT' ||
          (error && (data['batter_base'] as num? ?? 0) > 0) ||
          (type == 'BALL' && completed);
      if (reached && batter is String) {
        uncertainRunners.remove(batter);
        bases[batter] = (
          pitcher: pitcher,
          stint: stint,
          reachedOnError: error,
          ghost: false,
        );
      }
      if (error) {
        if (reached) {
          missedOuts++;
        } else {
          unknownOuts++;
        }
        uncertainErrorAdvance = true;
      }
      if (type == 'RUNNER_MOVE' &&
          !const {'STEAL', 'WILD_PITCH'}.contains(data['advance_cause'])) {
        if (data['runner_id'] case final String id) {
          uncertainRunners.add(id);
        } else {
          unidentifiedAdvance = true;
        }
      }
      final scorers = data['scoring_player_ids'];
      final ids = scorers is List
          ? scorers.whereType<String>().toSet()
          : <String>{};
      final runs =
          (data['runs'] as num?)?.toInt() ?? (type == 'RUN' ? 1 : ids.length);
      recorded += runs;
      if (runs != ids.length) {
        _unknownCharge.add(team);
        _unknownTeamEarned.add(team);
      }
      for (final id in ids) {
        final runner = bases.remove(id);
        final uncertainAdvance =
            uncertainRunners.remove(id) ||
            unidentifiedAdvance ||
            uncertainErrorAdvance;
        final owner = runner?.pitcher;
        if (runner == null || (owner == null && !runner.ghost)) {
          _unknownCharge.add(team);
          _unknownTeamEarned.add(team);
          continue;
        }
        if (runner.ghost) {
          _unknownTeamEarned.add(team);
          continue;
        }
        (charged[team] ??= {}).update(owner!, (n) => n + 1, ifAbsent: () => 1);
        final projected = actualOuts + missedOuts;
        final pitcherOuts = projected - (stintMisses[runner.stint] ?? 0);
        if (!runner.reachedOnError && pitcherOuts < 3) {
          if ((uncertainAdvance && !homer) ||
              pitcherOuts +
                      unknownOuts -
                      (stintUnknownOuts[runner.stint] ?? 0) >=
                  3) {
            (_unknownEarned[team] ??= {}).add(owner);
          } else {
            (earned[team] ??= {}).update(
              owner,
              (n) => n + 1,
              ifAbsent: () => 1,
            );
          }
        }
        if (!runner.reachedOnError && projected < 3) {
          if ((uncertainAdvance && !homer) || projected + unknownOuts >= 3) {
            _unknownTeamEarned.add(team);
          } else {
            teamEarned.update(team, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      }
      if (type == 'ERROR') {
        final retired = data['out_runner_ids'];
        final ids = retired is List
            ? retired.whereType<String>()
            : [data['out_runner_id']].whereType<String>();
        for (final id in ids) {
          bases.remove(id);
          uncertainRunners.remove(id);
        }
      }
      if (type == 'RUNNER_OUT' || type == 'DOUBLE_PLAY' || type == 'HIT') {
        if (type != 'HIT' || data['runner_id'] != null)
          bases.remove(data['runner_id']);
        uncertainRunners.remove(data['runner_id']);

        // Legacy hit events may encode outs by destination without an ID.
        // The runner cannot score unless a later official play identifies them.
      }
      actualOuts +=
          creditedOuts[play['version']] ??
          ((data['outs_added'] ?? data['outs']) as num?)?.toInt() ??
          (switch (type) {
            'DOUBLE_PLAY' => 2,
            'OUT' || 'SACRIFICE_FLY' || 'RUNNER_OUT' => 1,
            'STRIKE' when completed => 1,
            _ => 0,
          });
    }
    return recorded;
  }
}
