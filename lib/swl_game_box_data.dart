typedef SwlRow = Map<String, dynamic>;

int swlStat(Object? value) => value is num ? value.toInt() : 0;

class SwlGameBoxData {
  final Map<String, Map<String, List<int>>> batting = {};
  final Map<String, Map<String, List<int>>> pitching = {};
  final Map<String, List<int?>> innings = {};
  final Set<String> incompletePitching = {};
  final Set<String> incompleteRuns = {};
  final Set<String> incompleteRbi = {};

  static const battingLabels = [
    'PA',
    'VB',
    'CA',
    'H',
    '2B',
    '3B',
    'HR',
    'CE',
    'BB',
    'K',
    'SF',
    'AVE',
  ];
  static const pitchingLabels = [
    'IP',
    'H',
    'C',
    'CL',
    'BB',
    'K',
    'HR',
    'B',
    'S',
    'P',
  ];
  static const contact = {
    'HIT',
    'OUT',
    'SACRIFICE_FLY',
    'DOUBLE_PLAY',
    'ERROR',
  };

  SwlGameBoxData(SwlRow game, List<SwlRow> events, List<SwlRow> pitches) {
    final home = game['home_team_id'];
    final away = game['away_team_id'];
    final versions = {for (final e in events) e['version']: e};
    final undone = {
      for (final e in events)
        if (e['event_type'] == 'UNDO_OUT' && e['event_data'] is Map)
          int.tryParse('${e['event_data']['reverts_version']}'),
    };
    final credited = {for (final p in pitches) p['version']};
    for (final (team, side) in [(home, 'home'), (away, 'away')]) {
      if (team is! String) continue;
      final inning = swlStat(game['inning']);
      final played = game['status'] == 'SCHEDULED'
          ? 0
          : side == 'home' && game['is_top'] == true
          ? inning - 1
          : inning;
      innings[team] = List<int?>.filled(played < 0 ? 0 : played, 0);
    }
    for (final event in events) {
      if (undone.contains(event['version'])) continue;
      final team = event['batting_team_id'];
      if (team is! String || (team != home && team != away)) continue;
      final defense = (team == home ? away : home) as String;
      final type = event['event_type'];
      final d = event['event_data'];
      if (d is! Map) continue;
      final complete = d['plate_appearance_completed'] == true;
      final hit = type == 'HIT';
      final walk = type == 'BALL' && complete;
      final k = type == 'STRIKE' && complete;
      final sf = type == 'SACRIFICE_FLY';
      final vb =
          hit || k || const {'OUT', 'DOUBLE_PLAY', 'ERROR'}.contains(type);
      final scorers = d['scoring_player_ids'];
      final identifiedRuns = scorers is List
          ? scorers.whereType<String>().length
          : 0;
      final runs = d['runs'] is num
          ? swlStat(d['runs'])
          : type == 'RUN'
          ? 1
          : identifiedRuns;
      final half = swlStat(event['inning']) - 1;
      final cells = innings[team]!;
      if (half >= 0 && half < cells.length) cells[half] = cells[half]! + runs;
      if (scorers is List) {
        for (final id in scorers.whereType<String>()) {
          _row(batting, team, id, 11)[2]++;
        }
      }
      if (runs != identifiedRuns) {
        incompleteRuns.add(team);
      }
      if (runs > 0 && (hit || walk || sf) && d['rbi'] is! num) {
        incompleteRbi.add(team);
      }
      if (d['batter_id'] case final String id when vb || walk || sf) {
        final row = _row(batting, team, id, 11);
        row[0]++;
        if (vb) row[1]++;
        if (hit) {
          row[3]++;
          final bases = swlStat(d['batter_base']);
          if (bases >= 2 && bases <= 4) row[bases + 2]++;
        }
        row[7] += swlStat(d['rbi']);
        if (walk) row[8]++;
        if (k) row[9]++;
        if (sf) row[10]++;
      }
      if ((contact.contains(type) ||
              const {'BALL', 'STRIKE', 'FOUL'}.contains(type)) &&
          !credited.contains(event['version'])) {
        incompletePitching.add(defense);
      }
    }
    for (final p in pitches) {
      if (undone.contains(p['version'])) continue;
      final e = versions[p['version']];
      final offense = e?['batting_team_id'];
      final id = p['pitcher_id'];
      if (id is! String || (offense != home && offense != away)) continue;
      final team = (offense == home ? away : home) as String;
      final row = _row(pitching, team, id, 10);
      row[0] += swlStat(p['outs']);
      row[1] += swlStat(p['hits']);
      row[4] += swlStat(p['walks']);
      row[5] += swlStat(p['strikes_out']);
      final type = e?['event_type'];
      final d = e?['event_data'];
      if (type == 'HIT' && d is Map && d['batter_base'] == 4) row[6]++;
      if (p['pitch_count'] is num &&
          p['pitch_balls'] is num &&
          p['pitch_strikes'] is num &&
          p['pitch_in_play'] is num &&
          p['pitch_count'] ==
              swlStat(p['pitch_balls']) +
                  swlStat(p['pitch_strikes']) +
                  swlStat(p['pitch_in_play'])) {
        row[7] += swlStat(p['pitch_balls']);
        row[8] += swlStat(p['pitch_strikes']);
        row[9] += swlStat(p['pitch_count']);
      } else if (type == 'BALL') {
        row[7]++;
        row[9]++;
      } else if (type == 'STRIKE' || type == 'FOUL') {
        row[8]++;
        row[9]++;
      } else if (contact.contains(type)) {
        row[9]++;
      }
    }
    for (final (team, side) in [(home, 'home'), (away, 'away')]) {
      if (team is! String) continue;
      final runs = swlStat(game['${side}_runs']);
      final cells = innings[team]!;
      final stored = game['${side}_innings'];
      final storedValid =
          stored is List &&
          stored.isNotEmpty &&
          stored.every((v) => v is int && v >= 0) &&
          stored.fold<int>(0, (sum, v) => sum + swlStat(v)) == runs;
      if (storedValid) {
        for (var i = 0; i < cells.length && i < stored.length; i++) {
          cells[i] = swlStat(stored[i]);
        }
        for (var i = stored.length; i < cells.length; i++) {
          cells[i] = 0;
        }
      } else if (cells.fold<int>(0, (sum, n) => sum + (n ?? 0)) != runs) {
        innings[team] = List<int?>.filled(cells.length, null);
      }
      final individual = batting[team]?.values ?? const <List<int>>[];
      if (individual.fold<int>(0, (sum, row) => sum + row[2]) != runs) {
        incompleteRuns.add(team);
        if (cells.any((cell) => cell == null)) incompleteRbi.add(team);
      }
    }
  }

  static List<int> _row(
    Map<String, Map<String, List<int>>> data,
    String team,
    String id,
    int size,
  ) => (data[team] ??= {}).putIfAbsent(id, () => List<int>.filled(size, 0));

  static List<int> total(Iterable<List<int>> rows, int size) {
    final sum = List<int>.filled(size, 0);
    for (final row in rows) {
      for (var i = 0; i < size; i++) {
        sum[i] += row[i];
      }
    }
    return sum;
  }

  static String ip(int outs) => '${outs ~/ 3}.${outs % 3}';
  static String average(List<int> row) =>
      row[1] == 0 ? '—' : (row[3] / row[1]).toStringAsFixed(3);
}
