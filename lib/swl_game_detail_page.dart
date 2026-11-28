import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'swl_game_box_data.dart';
import 'swl_lineup_identity.dart';
import 'swl_lineup_draft.dart';
import 'swl_official_box_score.dart';
import 'swl_substitution_rules.dart';
import 'swl_team_lookup.dart';

class SwlGameDetailPage extends StatefulWidget {
  const SwlGameDetailPage({
    super.key,
    required this.gameId,
    required this.boxScore,
    required this.teamName,
    required this.teamLogo,
    this.teamColor,
    this.substitute,
    this.changePitcher,
  });

  final String gameId;
  final bool boxScore;
  final String Function(String) teamName;
  final String? Function(String) teamLogo;
  final String? Function(String)? teamColor;
  final Future<void> Function(BuildContext, String)? substitute;
  final Future<void> Function(String)? changePitcher;

  @override
  State<SwlGameDetailPage> createState() => _SwlGameDetailPageState();
}

class _SwlGameDetailPageState extends State<SwlGameDetailPage> {
  final _client = Supabase.instance.client;
  final _offsets = <String, double>{};
  final _players = <String, SwlRow>{};
  SwlRow? _game;
  List<SwlRow> _lineups = [], _events = [], _changes = [], _turns = [];
  SwlGameBoxData? _stats;
  Timer? _timer;
  RealtimeChannel? _channel;
  bool _showLandscapeScore = false;
  int _failedReads = 0;
  bool _loading = false, _queued = false, _failed = false, _changing = false;

  @override
  void initState() {
    super.initState();
    final channel = _client.channel(
      'swl-detail-${widget.gameId}-${identityHashCode(this)}',
    );
    for (final table in ['swl_live_games', 'swl_game_lineups']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: table == 'swl_live_games' ? 'id' : 'game_id',
          value: widget.gameId,
        ),
        callback: (_) => unawaited(_read()),
      );
    }
    _channel = channel.subscribe();
    _timer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(_read()),
    );
    unawaited(_read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_channel case final channel?) unawaited(_client.removeChannel(channel));
    super.dispose();
  }

  Future<List<SwlRow>> _versionedRows(
    String table,
    int version,
    String tie,
  ) async {
    const size = 250;
    final rows = <SwlRow>[];
    for (var start = 0; ; start += size) {
      final page = await _client
          .from(table)
          .select()
          .eq('game_id', widget.gameId)
          .lte('version', version)
          .order('version')
          .order(tie)
          .range(start, start + size - 1)
          .timeout(const Duration(seconds: 10));
      rows.addAll(page);
      if (page.length < size) return rows;
    }
  }

  Future<void> _read() async {
    if (_loading) {
      _queued = true;
      return;
    }
    _loading = true;
    final failuresBefore = _failedReads;
    try {
      final game = await _client
          .from('swl_live_games')
          .select()
          .eq('id', widget.gameId)
          .single()
          .timeout(const Duration(seconds: 10));
      final version = swlStat(game['version']);
      final rows = await Future.wait<List<SwlRow>>([
        _client
            .from('swl_game_lineups')
            .select()
            .eq('game_id', widget.gameId)
            .timeout(const Duration(seconds: 10)),
        _versionedRows('swl_game_events', version, 'id'),
        _versionedRows('swl_v56_pitcher_changes', version, 'team_id'),
        if (widget.boxScore)
          _versionedRows('swl_v56_pitching_events', version, 'pitcher_id')
        else
          _client
              .from('swl_game_batting_turns')
              .select()
              .eq('game_id', widget.gameId)
              .timeout(const Duration(seconds: 10)),
      ]);
      final stats = widget.boxScore
          ? SwlGameBoxData(
              game,
              rows[1],
              rows[3],
              changes: rows[2],
              lineups: rows[0],
            )
          : null;
      final ids = <String>{
        for (final row in rows[0]) ...swlLineupParticipantIds(row),
        for (final row in rows[1])
          if (row['event_data'] case final Map event)
            ...[
              event['incoming_player_id'],
              event['outgoing_player_id'],
            ].whereType<String>(),
        for (final row in rows[2])
          ...[row['old_pitcher_id'], row['new_pitcher_id']].whereType<String>(),
        for (final team in stats?.batting.values ?? <Map<String, List<int>>>[])
          ...team.keys,
        for (final team in stats?.pitching.values ?? <Map<String, List<int>>>[])
          ...team.keys,
      }.where((id) => !_players.containsKey(id)).toList();
      for (var start = 0; start < ids.length; start += 50) {
        final people = await _client
            .from('players')
            .select('id,first_name,last_name,jersey_number,universal_id')
            .inFilter('id', ids.skip(start).take(50).toList())
            .timeout(const Duration(seconds: 10));
        for (final person in people) {
          _players[person['id'] as String] = person;
        }
      }
      final latest = await _client
          .from('swl_live_games')
          .select('version')
          .eq('id', widget.gameId)
          .single()
          .timeout(const Duration(seconds: 10));
      if (latest['version'] != game['version']) {
        _queued = true;
        return;
      }
      if (!mounted) return;
      _failedReads = 0;
      setState(() {
        _game = game;
        _lineups = rows[0];
        _events = rows[1];
        _changes = rows[2];
        _turns = widget.boxScore ? [] : rows[3];
        _stats = stats;
        _failed = false;
      });
    } catch (_) {
      _failedReads++;
      if (mounted && !_failed && (_game == null || failuresBefore > 0)) {
        setState(() => _failed = true);
      }
    } finally {
      _loading = false;
      if (mounted && _queued) {
        _queued = false;
        unawaited(_read());
      }
    }
  }

  String _name(String id) {
    final player = _players[id];
    if (player == null) return 'Pelotero';
    final name = [
      player['first_name'],
      player['last_name'],
    ].whereType<String>().join(' ');
    return '${name.isEmpty ? "Pelotero" : name}${player['jersey_number'] == null ? "" : " · #${player['jersey_number']}"}';
  }

  List<SwlRow> _substitutions(String team) => _events
      .where(
        (e) =>
            e['batting_team_id'] == team &&
            e['event_type'] == 'SUBSTITUTION' &&
            e['event_data'] is Map,
      )
      .map((e) => Map<String, dynamic>.from(e['event_data'] as Map))
      .toList();

  Set<String> _byId(Iterable<SwlRow> rows, String key) =>
      rows.map((r) => r[key]).whereType<String>().toSet();

  SwlRow _lineup(String team) =>
      _lineups.firstWhere((l) => l['team_id'] == team, orElse: () => {});

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      title,
      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
    ),
  );

  Future<void> _change(Future<void> Function() action) async {
    setState(() => _changing = true);
    try {
      await action();
      await _read();
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Widget _alignment(SwlRow game, String team) {
    final lineup = _lineup(team);
    final slots = swlConfirmedBattingSlots(lineup['lineup']);
    final substitutions = _substitutions(team);
    final changes = _changes.where((row) => row['team_id'] == team);
    final active = swlLineupParticipantIds(lineup);
    final entrants = {
      ..._byId(substitutions, 'incoming_player_id'),
      ..._byId(changes, 'new_pitcher_id'),
    };
    final retired = {
      ..._byId(substitutions, 'outgoing_player_id'),
      ..._byId(changes, 'old_pitcher_id'),
    }.difference(active);
    final pitcher = lineup['pitcher_id'];
    final dh = lineup['designated_hitter_id'];
    final defense = lineup['defensive_positions'];
    final defenseRows = defense is Map ? defense : const {};
    final defenders = <String, List<String>>{};
    for (final entry in defenseRows.entries) {
      if (entry.key is String && entry.value is String) {
        (defenders[entry.value as String] ??= []).add(entry.key as String);
      }
    }
    final cursor = _turns.where((row) => row['team_id'] == team).firstOrNull;
    final turn = swlResolveBattingTurn(lineup['lineup'], cursor)?.order;
    final live = game['status'] == 'IN_PROGRESS';
    final battingTeam =
        game[game['is_top'] == true ? 'away_team_id' : 'home_team_id'];
    final own = _client.auth.currentUser?.id;
    final manager =
        game[team == game['home_team_id']
            ? 'home_manager_id'
            : 'away_manager_id'];
    final canManage = live && own != null && own == manager;
    return ListView(
      key: PageStorageKey('lineup-$team'),
      padding: const EdgeInsets.all(16),
      children: [
        if (pitcher is String) Text('Pitcher actual · ${_name(pitcher)}'),
        if (dh is String) Text('DH · ${_name(dh)}'),
        _section('Orden al bate'),
        if (slots.isEmpty) const Text('Alineación pendiente'),
        for (var i = 0; i < slots.length; i++)
          ListTile(
            dense: true,
            minTileHeight: 38,
            minVerticalPadding: 0,
            visualDensity: VisualDensity.compact,
            leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
            title: Text(_name(slots[i]['player_id'] as String)),
            subtitle: Text(
              [
                if (slots[i]['player_id'] == dh)
                  'DH'
                else if (defenseRows[slots[i]['player_id']]
                    case final String role)
                  role
                else
                  'Sin posición defensiva',
                entrants.contains(slots[i]['player_id'])
                    ? 'Sustituto'
                    : 'Titular',
                if (live && turn != null)
                  if (i + 1 == turn)
                    team == battingTeam ? 'Bateador actual' : 'Próximo turno'
                  else if (i == turn % slots.length)
                    'En espera'
                  else if (i == (turn + 1) % slots.length)
                    'En el círculo siguiente',
              ].join(' · '),
            ),
          ),
        _section('Defensa'),
        for (final role in {...swlDefensivePositions, ...defenders.keys})
          if (defenders[role] case final List<String> players)
            for (final id in players)
              Text(
                '$role · ${_name(id)} · ${entrants.contains(id) ? "Sustituto" : "Titular"}',
              )
          else if (role == 'C' && lineup.isNotEmpty)
            const Text('C · Sin receptor asignado'),
        if (retired.isNotEmpty) _section('Jugadores retirados'),
        for (final id in retired) Text(_name(id)),
        if (canManage && widget.substitute != null)
          TextButton(
            onPressed: _changing
                ? null
                : () => _change(() => widget.substitute!(context, team)),
            child: const Text('Sustituir bateador'),
          ),
        if (canManage &&
            widget.changePitcher != null &&
            battingTeam != team &&
            game['balls'] == 0 &&
            game['strikes'] == 0)
          TextButton(
            onPressed: _changing
                ? null
                : () => _change(() => widget.changePitcher!(team)),
            child: const Text('Cambiar pitcher'),
          ),
      ],
    );
  }

  String _jerseyFirst(String name) {
    final split = name.lastIndexOf(' · #');
    return split < 0
        ? name
        : '${name.substring(split + 3)} · ${name.substring(0, split)}';
  }

  Widget _statRow(
    String team,
    String name,
    List<String> values, {
    bool header = false,
  }) {
    const cellWidth = 44.0;
    final style = header
        ? const TextStyle(
            color: Colors.amber,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          )
        : const TextStyle(fontSize: 12);
    return ColoredBox(
      color: header ? const Color(0xFF172334) : const Color(0xFF080D14),
      child: SizedBox(
        height: header ? 31 : 27,
        child: Row(
          children: [
            Expanded(
              flex: MediaQuery.sizeOf(context).width >= 600 ? 1 : 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Tooltip(
                  message: name,
                  child: Text(
                    _jerseyFirst(name),
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: MediaQuery.sizeOf(context).width >= 600 ? 2 : 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maximum =
                      (values.length * cellWidth - constraints.maxWidth)
                          .clamp(0.0, double.infinity)
                          .toDouble();
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: maximum == 0
                        ? null
                        : (event) {
                            setState(
                              () => _offsets[team] =
                                  ((_offsets[team] ?? 0).clamp(0.0, maximum) -
                                          event.delta.dx)
                                      .clamp(0.0, maximum)
                                      .toDouble(),
                            );
                          },
                    child: ClipRect(
                      child: Stack(
                        children: [
                          Positioned(
                            left: -(_offsets[team] ?? 0)
                                .clamp(0.0, maximum)
                                .toDouble(),
                            top: 0,
                            bottom: 0,
                            child: Row(
                              children: [
                                for (final value in values)
                                  SizedBox(
                                    width: cellWidth,
                                    child: Center(
                                      child: Text(value, style: style),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<SwlReportTable> _reportTables(SwlRow game, String team) {
    final stats = _stats!;
    final lineup = _lineup(team);
    final bats = stats.batting[team] ?? {};
    final throws = stats.pitching[team] ?? {};
    final batters = {
      for (final slot in swlConfirmedBattingSlots(lineup['lineup']))
        slot['player_id'] as String,
      ..._byId(_substitutions(team), 'outgoing_player_id'),
      ..._byId(_substitutions(team), 'incoming_player_id'),
      ...bats.keys,
    };
    final changes = _changes.where((row) => row['team_id'] == team);
    final pitchers = {
      for (final change in changes)
        ...[
          change['old_pitcher_id'],
          change['new_pitcher_id'],
        ].whereType<String>(),
      ...throws.keys,
      if (lineup['pitcher_id'] case final String id) id,
    };
    final firstAppearance = <String, int>{...stats.runCredit.firstPitchVersion};
    for (final change in changes) {
      final version = swlStat(change['version']);
      if (change['old_pitcher_id'] case final String id) {
        firstAppearance.putIfAbsent(id, () => version - 1);
      }
      if (change['new_pitcher_id'] case final String id) {
        firstAppearance.update(
          id,
          (old) => old < version ? old : version,
          ifAbsent: () => version,
        );
      }
    }
    final orderedPitchers = pitchers.toList()
      ..sort(
        (a, b) => (firstAppearance[a] ?? 0x7fffffff).compareTo(
          firstAppearance[b] ?? 0x7fffffff,
        ),
      );
    final isHome = team == game['home_team_id'];
    final runsAllowed = swlStat(game[isHome ? 'away_runs' : 'home_runs']);
    final runs = swlStat(game[isHome ? 'home_runs' : 'away_runs']);
    final bTotal = SwlGameBoxData.total(bats.values, 11);
    bTotal[2] = runs;
    final pTotal = SwlGameBoxData.total(throws.values, 10);
    List<String> battingLine(List<int> row, {bool total = false}) => [
      for (var i = 0; i < row.length; i++)
        if ((i == 2 && !total && stats.incompleteRuns.contains(team)) ||
            (i == 7 && stats.incompleteRbi.contains(team)))
          '—'
        else
          '${row[i]}',
      SwlGameBoxData.average(row),
    ];
    List<String> pitchingLine(List<int> row, {String? pitcher}) => [
      SwlGameBoxData.ip(row[0]),
      '${row[1]}',
      pitcher == null
          ? '$runsAllowed'
          : stats.runCredit.runsLabel(team, pitcher),
      pitcher == null
          ? stats.runCredit.cleanTotalLabel(team)
          : stats.runCredit.cleanLabel(team, pitcher),
      for (final n in row.skip(4)) '$n',
    ];
    final positions = lineup['defensive_positions'];
    final substitutions = _substitutions(team);
    final entrants = _byId(substitutions, 'incoming_player_id');
    final departed = _byId(substitutions, 'outgoing_player_id');
    String role(String id) =>
        departed.contains(id) && !swlLineupParticipantIds(lineup).contains(id)
        ? 'Retirado'
        : entrants.contains(id)
        ? 'Sustituto'
        : 'Titular';
    return [
      (
        title: 'Bateo',
        labels: SwlGameBoxData.battingLabels,
        rows: [
          for (final id in batters)
            (_name(id), battingLine(bats[id] ?? List.filled(11, 0))),
          ('Total', battingLine(bTotal, total: true)),
        ],
      ),
      (
        title: 'Pitcheo',
        labels: SwlGameBoxData.pitchingLabels,
        rows: [
          for (final id in orderedPitchers)
            (
              _name(id),
              pitchingLine(throws[id] ?? List.filled(10, 0), pitcher: id),
            ),
          ('Total', pitchingLine(pTotal)),
        ],
      ),
      (
        title: 'Defensa registrada',
        labels: const ['POS', 'Participación'],
        rows: [
          if (positions is Map)
            for (final entry in positions.entries)
              (
                _name(entry.key.toString()),
                [entry.value.toString(), role(entry.key.toString())],
              ),
          for (final id in departed.difference(swlLineupParticipantIds(lineup)))
            (_name(id), ['—', 'Retirado']),
          (
            'Equipo',
            ['—', 'E: ${game[isHome ? 'home_errors' : 'away_errors'] ?? '—'}'],
          ),
        ],
      ),
    ];
  }

  SwlOfficialBoxScore _export(SwlRow game) {
    SwlRow side(String side) {
      final id = game['${side}_team_id'] as String;
      return {
        'id': id,
        'name': widget.teamName(id),
        'logo_url': widget.teamLogo(id),
        'primary_color': widget.teamColor?.call(id),
        'innings': _stats!.innings[id],
        for (final field in ['runs', 'hits', 'errors'])
          field: game['${side}_$field'],
      };
    }

    return SwlOfficialBoxScore(
      {
        'code': game['game_pin'],
        'date': game['created_at'],
        'status': game['status'],
        'finish': game['swl_finish_reason'],
        'inning': game['inning'],
        'away': side('away'),
        'home': side('home'),
      },
      reports: {
        for (final id in [
          game['away_team_id'] as String,
          game['home_team_id'] as String,
        ])
          id: _reportTables(game, id),
      },
    );
  }

  Widget _box(SwlRow game, String team) {
    final stats = _stats!;
    final reports = _reportTables(game, team);
    final uid = _client.auth.currentUser?.id;
    final ownTeam = uid == null
        ? null
        : uid == game['home_manager_id']
        ? game['home_team_id'] as String
        : uid == game['away_manager_id']
        ? game['away_team_id'] as String
        : null;
    Widget table(
      String title,
      List<String> labels,
      List<(String, List<String>)> rows,
    ) => SliverMainAxisGroup(
      slivers: [
        PinnedHeaderSliver(
          child: _statRow(team, '$title · Pelotero', labels, header: true),
        ),
        SliverList.list(
          children: [
            for (final (name, stats) in rows) _statRow(team, name, stats),
          ],
        ),
      ],
    );
    return CustomScrollView(
      key: PageStorageKey('box-$team'),
      slivers: [
        if (stats.incompleteRuns.contains(team) ||
            stats.incompleteRbi.contains(team) ||
            reports.first.rows.last.$2[3] !=
                '${game[team == game['home_team_id'] ? 'home_hits' : 'away_hits'] ?? 0}')
          const SliverToBoxAdapter(
            child: Text(
              'El historial no permite atribuir todos los resultados a peloteros individuales.',
            ),
          ),
        table(reports.first.title, reports.first.labels, reports.first.rows),
        if (stats.incompletePitching.contains(team))
          const SliverToBoxAdapter(
            child: Text('Conteo parcial · hay jugadas sin pitcher acreditado.'),
          ),
        if (stats.runCredit.cleanTotal(team) == null ||
            (stats.pitching[team]?.keys ?? const <String>[]).any(
              (id) => stats.runCredit.cleanRuns(team, id) == null,
            ))
          const SliverToBoxAdapter(
            child: Text(
              'CL parcial · ≥ indica el mínimo confirmado por el historial.',
            ),
          ),
        for (final report in reports.skip(1))
          table(report.title, report.labels, report.rows),
        if (game['status'] == 'OFFICIAL')
          SliverToBoxAdapter(
            child: SwlShareBoxScoreButton(
              gameId: widget.gameId,
              loadScore: () async => _export(game),
              ownTeam: ownTeam,
            ),
          ),
      ],
    );
  }

  Widget _score(SwlRow game, List<String> teams) {
    final innings = _stats!.innings;
    final regulation = (game['swl_regulation_innings'] as int?) ?? 6;
    final count = [
      regulation,
      ...teams.map((team) => innings[team]?.length ?? 0),
    ].reduce((a, b) => a > b ? a : b);
    String entry(String team, int i, int side) {
      final cells = innings[team] ?? const [];
      if (i >= cells.length) return '·';
      final value = cells[i];
      if (value == null) return '?';
      final activeHalf =
          game['status'] == 'IN_PROGRESS' &&
          i + 1 == game['inning'] &&
          (game['is_top'] == true ? side == 0 : side == 1);
      return activeHalf && value == 0 ? '0*' : '$value';
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 12,
        headingRowHeight: 34,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columns: [
          const DataColumn(label: Text('Equipo')),
          for (var n = 1; n <= count; n++) DataColumn(label: Text('$n')),
          for (final label in ['C', 'H', 'E']) DataColumn(label: Text(label)),
        ],
        rows: [
          for (final (index, team) in teams.indexed)
            DataRow(
              cells: [
                DataCell(Text(widget.teamName(team))),
                for (var i = 0; i < count; i++)
                  DataCell(Text(entry(team, i, index))),
                for (final field in ['runs', 'hits', 'errors'])
                  DataCell(
                    Text(
                      '${game['${index == 0 ? "away" : "home"}_$field'] ?? "—"}',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final title = widget.boxScore ? 'Box Score' : 'Alineaciones';
    if (game == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: _failed
              ? TextButton(
                  onPressed: _read,
                  child: const Text('Reintentar la consulta'),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    final teams = [
      game['away_team_id'] as String,
      game['home_team_id'] as String,
    ];
    final size = MediaQuery.sizeOf(context);
    final compact =
        widget.boxScore && size.width > size.height && size.height < 500;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF080D14),
        appBar: AppBar(
          toolbarHeight: compact ? 44 : null,
          title: Text('$title · ${game['game_pin']}'),
          actions: [
            IconButton(
              onPressed: _read,
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            tabs: [
              for (final team in teams)
                Tab(
                  icon: compact
                      ? null
                      : SwlTeamBadge(url: widget.teamLogo(team)),
                  text: widget.teamName(team),
                ),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_failed)
              const Text(
                'No se pudo actualizar. Se muestra la última lectura confirmada.',
              ),
            if (game['status'] == 'CANCELLED')
              const Text('Partido cancelado · registro para consulta'),
            if (compact)
              TextButton(
                onPressed: () =>
                    setState(() => _showLandscapeScore = !_showLandscapeScore),
                child: Text(
                  '${game['away_runs']} – ${game['home_runs']} · '
                  '${_showLandscapeScore ? "Ocultar pizarra" : "Ver pizarra por entradas"}',
                ),
              ),
            if (widget.boxScore && (!compact || _showLandscapeScore)) ...[
              _score(game, teams),
              const Text('· Sin jugar   0* En curso   ? Sin desglose'),
            ],
            Expanded(
              child: TabBarView(
                children: [
                  for (final team in teams)
                    widget.boxScore ? _box(game, team) : _alignment(game, team),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
