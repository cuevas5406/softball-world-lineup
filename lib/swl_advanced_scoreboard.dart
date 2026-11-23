import 'swl_history_events.dart';
import 'swl_roster_repository.dart';
import 'swl_special_play.dart';
import 'swl_game_finish.dart';
import 'swl_lineup_identity.dart';
import 'swl_pitching_stats.dart';
import 'swl_team_lookup.dart';
import 'swl_live_scoreboard_snapshot.dart';
import 'dart:math';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

// Modelo de Bateador con su historial turno por turno del juego
class SwlScorePlayer {
  final String name;
  final String number;
  // UUID persistente del pelotero. null indica entrada local sin identidad verificada.
  final String? playerId;
  final String battingRole; // REGULAR, DH o AH
  final String defensivePosition; // P, C, 1B, 2B, 3B, SS, LF, CF, RF o SIN
  int ab;   // Turnos oficiales
  int hits; // Hits
  int bb;   // Boletos
  int rbi;  // Carreras empujadas
  int sacrifices;
  List<String> gameLog; // Turno por turno del día

  SwlScorePlayer({
    required this.name,
    required this.number,
    this.playerId,
    this.battingRole = 'REGULAR',
    this.defensivePosition = 'SIN',
    this.ab = 0,
    this.hits = 0,
    this.bb = 0,
    this.rbi = 0,
    this.sacrifices = 0,
    List<String>? gameLog,
  }) : gameLog = gameLog ?? [];

  // Cálculo del Promedio de Bateo (AVG)
  String get battingAverage {
    if (ab == 0) return ".---";
    final double avg = hits / ab;
    if (avg >= 1.0) return "1.000";
    return avg.toStringAsFixed(3).replaceFirst("0.", ".");
  }

  SwlScorePlayer copy() => SwlScorePlayer(
        name: name,
        number: number,
        playerId: playerId,
        battingRole: battingRole,
        defensivePosition: defensivePosition,
        ab: ab,
        hits: hits,
        bb: bb,
        rbi: rbi,
        sacrifices: sacrifices,
        gameLog: List.from(gameLog),
      );
}

// Modelo del SwlScorePitcher (Lanzador)
class SwlScorePitcher {
  final String name;
  final String number;
  final String teamName;
  final String? pitchLine;
  int outsRecorded; // Se guarda en outs y se muestra como IP (ej. 4 outs = 1.1 IP)
  int strikeouts;   // Ponches (K)
  int walks;        // Bases por bolas (BB)
  int hitsAllowed;  // Hits permitidos
  int runsAllowed;  // Carreras permitidas

  SwlScorePitcher({
    required this.name,
    required this.number,
    required this.teamName,
    this.pitchLine,
    this.outsRecorded = 0,
    this.strikeouts = 0,
    this.walks = 0,
    this.hitsAllowed = 0,
    this.runsAllowed = 0,
  });

  // Entradas lanzadas en formato oficial (ej. 5 outs = 1.2 IP)
  String get ip {
    final int fullInnings = outsRecorded ~/ 3;
    final int remainderOuts = outsRecorded % 3;
    return "$fullInnings.$remainderOuts";
  }

  SwlScorePitcher copy() => SwlScorePitcher(
        name: name,
        number: number,
        teamName: teamName,
        pitchLine: pitchLine,
        outsRecorded: outsRecorded,
        strikeouts: strikeouts,
        walks: walks,
        hitsAllowed: hitsAllowed,
        runsAllowed: runsAllowed,
      );
}

class SwlScorePlayRecord {
  final int inning;
  final bool isTopInning;
  final String description;
  final String notation;
  final String batterName;

  SwlScorePlayRecord({
    required this.inning,
    required this.isTopInning,
    required this.description,
    required this.notation,
    required this.batterName,
  });
}

class SwlScoreGameSnapshot {
  final int balls;
  final int strikes;
  final int outs;
  final int inning;
  final bool isTopInning;
  final bool on1B;
  final bool on2B;
  final bool on3B;
  final List<int?> visitorInningRuns;
  final List<int?> homeInningRuns;
  final int visitorHits;
  final int homeHits;
  final int visitorErrors;
  final int homeErrors;
  final int visitorLineupIndex;
  final int homeLineupIndex;
  final List<SwlScorePlayer> visitorLineup;
  final List<SwlScorePlayer> homeLineup;
  final SwlScorePitcher visitorPitcher;
  final SwlScorePitcher homePitcher;
  final List<SwlScorePlayRecord> plays;

  SwlScoreGameSnapshot({
    required this.balls,
    required this.strikes,
    required this.outs,
    required this.inning,
    required this.isTopInning,
    required this.on1B,
    required this.on2B,
    required this.on3B,
    required this.visitorInningRuns,
    required this.homeInningRuns,
    required this.visitorHits,
    required this.homeHits,
    required this.visitorErrors,
    required this.homeErrors,
    required this.visitorLineupIndex,
    required this.homeLineupIndex,
    required this.visitorLineup,
    required this.homeLineup,
    required this.visitorPitcher,
    required this.homePitcher,
    required this.plays,
  });
}

class SwlAdvancedScoreboard extends StatefulWidget {
  const SwlAdvancedScoreboard({super.key, required this.gamePin, required this.homeTeam, required this.awayTeam, this.liveSnapshot, this.onLiveAction, this.onLiveDetails, this.onLiveSubstitute, this.onLivePitcher, this.onMatchDecision, this.homeLogo, this.awayLogo});
  final String? homeLogo;
  final String? awayLogo;
  final VoidCallback? onLiveDetails;
  final VoidCallback? onLiveSubstitute;
  final VoidCallback? onLivePitcher;
  final SwlLiveScoreboardSnapshot? liveSnapshot;
  final Future<void> Function(int version, String action)? onMatchDecision;
  final Future<void> Function(int version, String action, Map<String, dynamic>? hitParams)? onLiveAction;
  final String gamePin;
  final String homeTeam;
  final String awayTeam;

  @override
  State<SwlAdvancedScoreboard> createState() => _ScoreboardScreenState();
}

class _ScoreboardScreenState extends State<SwlAdvancedScoreboard> {
  late String visitorName;
  Timer? _liveRefreshTimer;
  SwlLiveScoreboardSnapshot? _currentLiveSnapshot;
  bool _refreshInFlight = false;
  bool _scoreQueued = false;
  Completer<void>? _scoreIdleCompleter;
  bool _liveActionInFlight = false;
  bool _lineupsLoading = false;
  bool _lineupsQueued = false;
  Completer<void>? _lineupsIdleCompleter;
  bool _pitchingConfirmed = false;
  bool _awayBatterConfirmed = false;
  bool _homeBatterConfirmed = false;
  int _lastLineupRefreshVersion = -1;
  int _livePollCount = 0;
  String? _lineupLoadError;

  Future<void> _loadLiveLineups() async {
    final live = _currentLiveSnapshot;
    if (!mounted || live == null || live.gameId.isEmpty) return;
    if (_lineupsLoading) {
      _lineupsQueued = true;
      await _lineupsIdleCompleter?.future;
      return;
    }
    _lineupsIdleCompleter ??= Completer<void>();
    _lineupsLoading = true;
    try {
      final client = Supabase.instance.client;
      final rawLineups = await client.from('swl_game_lineups')
          .select().eq('game_id', live.gameId)
          .timeout(const Duration(seconds: 12));
      final rawTurns = await client.from('swl_game_batting_turns')
          .select('team_id,next_order').eq('game_id', live.gameId)
          .timeout(const Duration(seconds: 12));
      // Estadísticas preliminares basadas solo en eventos confirmados de este partido.
      final rawEvents = <Map<String, dynamic>>[];
      const pageSize = 250;
      for (var offset = 0; ; offset += pageSize) {
        final page = await client.from('swl_game_events')
            .select('event_type,event_data,inning,is_top')
            .eq('game_id', live.gameId).lte('version', live.version)
            .order('version').order('id').range(offset, offset + pageSize - 1)
            .timeout(const Duration(seconds: 12));
        rawEvents.addAll(page);
        if (page.length < pageSize) break;
        if (!mounted || _currentLiveSnapshot?.version != live.version) return;
      }
      final batterStats = <String, Map<String, int>>{};
      for (final event in rawEvents) {
        final data = event['event_data'];
        if (data is! Map || data['batter_id'] == null) continue;
        final playerId = data['batter_id'].toString();
        final action = event['event_type']?.toString().toUpperCase();
        final totals = batterStats.putIfAbsent(playerId,
            () => {'ab': 0, 'hits': 0, 'bb': 0, 'rbi': 0, 'sf': 0});
        final rbi = data['rbi'] ?? data['rbis'];
        if (rbi is num && rbi >= 0 && rbi <= 4) totals['rbi'] = totals['rbi']! + rbi.toInt();
        if (action == 'HIT') {
          totals['ab'] = totals['ab']! + 1;
          totals['hits'] = totals['hits']! + 1;
        } else if (action == 'SACRIFICE_FLY') {
          totals['sf'] = totals['sf']! + 1;
        } else if (action == 'OUT' || action == 'DOUBLE_PLAY' || action == 'ERROR' ||
            (action == 'STRIKE' && data['plate_appearance_completed'] == true)) {
          totals['ab'] = totals['ab']! + 1;
        } else if (action == 'BALL' &&
            data['plate_appearance_completed'] == true) {
          totals['bb'] = totals['bb']! + 1;
        }
      }
      final ids = <String>{
        for (final row in rawLineups)
          if (row['pitcher_id'] != null) row['pitcher_id'].toString(),
      };
      for (final row in rawLineups) {
        final slots = row['lineup'];
        if (slots is List) {
          for (final slot in slots) {
            if (slot is Map && slot['player_id'] != null) {
              ids.add(slot['player_id'].toString());
            }
          }
        }
      }
      final players = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final rows = await client.from('players')
            .select('id,first_name,last_name,jersey_number')
            .inFilter('id', ids.toList()).timeout(const Duration(seconds: 12));
        for (final player in rows) {
          players[player['id'].toString()] = Map<String, dynamic>.from(player);
        }
      }
      List<SwlScorePlayer>? parseLineup(String teamId) {
        for (final row in rawLineups) {
          if (row['team_id']?.toString() != teamId) continue;
          final slots = swlConfirmedBattingSlots(row['lineup']);
          if (slots.isEmpty) return null;
          final result = <SwlScorePlayer>[];
          for (final slot in slots) {
            final id = slot['player_id']?.toString();
            final player = players[id];
            final name = player == null ? 'Pelotero no disponible' :
                '${player['first_name'] ?? ''} ${player['last_name'] ?? ''}'.trim();
            result.add(SwlScorePlayer(
              name: name.isEmpty ? 'Pelotero no disponible' : name,
              number: player?['jersey_number']?.toString() ?? '-',
              playerId: id,
              ab: batterStats[id]?['ab'] ?? 0,
              hits: batterStats[id]?['hits'] ?? 0,
              bb: batterStats[id]?['bb'] ?? 0,
              rbi: batterStats[id]?['rbi'] ?? 0,
              sacrifices: batterStats[id]?['sf'] ?? 0,
            ));
          }
          return result.isEmpty ? null : result;
        }
        return null;
      }
      int nextIndex(String teamId, int length) {
        for (final row in rawTurns) {
          if (row['team_id']?.toString() == teamId) {
            final order = (row['next_order'] as num?)?.toInt() ?? 1;
            return order >= 1 && order <= length ? order - 1 : -1;
          }
        }
        return 0;
      }
      if (!mounted || _currentLiveSnapshot?.gameId != live.gameId ||
          _currentLiveSnapshot?.version != live.version) return;
      Map<String, SwlPitchingTotals>? pitching;
      try {
        pitching = await swlLoadPitching(client, live.gameId, live.version);
      } catch (_) {
        // La lectura de pitcheo es independiente de la identidad del lanzador.
      }
      if (!mounted || _currentLiveSnapshot?.gameId != live.gameId ||
          _currentLiveSnapshot?.version != live.version) return;
      final away = parseLineup(live.awayTeamId);
      final home = parseLineup(live.homeTeamId);
      SwlScorePitcher readPitcher(String teamId, String teamName) {
        final lineup = rawLineups.where((row) => row['team_id']?.toString() == teamId).firstOrNull;
        final id = lineup?['pitcher_id']?.toString();
        final player = players[id];
        final totals = pitching?[id];
        final name = '${player?['first_name'] ?? ''} ${player?['last_name'] ?? ''}'.trim();
        return SwlScorePitcher(
          name: name.isEmpty ? 'Lanzador por confirmar' : name,
          number: player?['jersey_number']?.toString() ?? '-',
          teamName: teamName,
          pitchLine: totals?.pitchLine,
          outsRecorded: totals?.outs ?? 0,
          strikeouts: totals?.strikeouts ?? 0,
          walks: totals?.walks ?? 0,
          hitsAllowed: totals?.hits ?? 0,
        );
      }
      setState(() {
        _pitchingConfirmed = pitching != null && (pitching.isNotEmpty || rawEvents.isEmpty);
        homePitcher = readPitcher(live.homeTeamId, homeName);
        visitorPitcher = readPitcher(live.awayTeamId, visitorName);
        _awayBatterConfirmed = away != null &&
            nextIndex(live.awayTeamId, away.length) >= 0;
        _homeBatterConfirmed = home != null &&
            nextIndex(live.homeTeamId, home.length) >= 0;
        if (_awayBatterConfirmed && away != null) {
          visitorLineup = away;
          visitorLineupIndex = nextIndex(live.awayTeamId, away.length);
        }
        if (_homeBatterConfirmed && home != null) {
          homeLineup = home;
          homeLineupIndex = nextIndex(live.homeTeamId, home.length);
        }
        _lastLineupRefreshVersion = live.version;
        _lineupLoadError = null;
      });
    } catch (_) {
      if (mounted && _currentLiveSnapshot?.gameId == live.gameId) setState(() => _lineupLoadError =
          'No se pudo actualizar la alineación real');
    } finally {
      _lineupsLoading = false;
      if (_lineupsQueued && mounted) {
        _lineupsQueued = false;
        // Esperar la lectura acumulada antes de dar por actualizado el marcador.
        await _loadLiveLineups();
      } else {
        _lineupsQueued = false;
        final idle = _lineupsIdleCompleter;
        _lineupsIdleCompleter = null;
        if (idle != null && !idle.isCompleted) idle.complete();
      }
    }
  }

  final _historyScroll = ScrollController();
  final _historyPlayers = <String, Map<String, dynamic>>{};
  bool _historyLoading = false;
  bool _historyQueued = false;
  Completer<void>? _historyIdleCompleter;
  String? _historyReadError;

  Future<void> _refreshLiveHistory() async {
    final live = _currentLiveSnapshot;
    if (!mounted || live == null || live.gameId.isEmpty) return;
    if (_historyLoading) {
      _historyQueued = true;
      // Esperar también la consulta en curso y la recarga en cola.
      await _historyIdleCompleter?.future;
      return;
    }
    _historyIdleCompleter ??= Completer<void>();
    _historyLoading = true;
    try {
      final client = Supabase.instance.client;
      final events = <Map<String, dynamic>>[];
      const size = 250;
      for (var offset = 0; ; offset += size) {
        final page = await client.from('swl_game_events')
            .select('id,event_type,event_data,inning,is_top')
            .eq('game_id', live.gameId)
            .order('version', ascending: true).order('id', ascending: true)
            .range(offset, offset + size - 1)
            .timeout(const Duration(seconds: 8));
        events.addAll(page.where(swlIsHistoryPlay));
        if (page.length < size) break;
        if (!mounted || _currentLiveSnapshot?.gameId != live.gameId) return;
      }
      final seen = <String>{};
      events.removeWhere((event) => event['id'] != null && !seen.add(event['id'].toString()));
      final ids = <String>{
        for (final event in events)
          if (event['event_data'] case final Map data) ...{
            for (final key in ['batter_id', 'runner_id', 'last_out_player_id', 'out_runner_id'])
              if (data[key] case final Object id) id.toString(),
          },
      };
      final players = Map<String, Map<String, dynamic>>.from(_historyPlayers);
      final playerIds = ids.where((id) => !players.containsKey(id)).toList();
      for (var offset = 0; offset < playerIds.length; offset += 40) {
        if (!mounted || _currentLiveSnapshot?.gameId != live.gameId) return;
        try {
          final rows = await client.from('players')
              .select('id,first_name,last_name')
              .inFilter('id', playerIds.skip(offset).take(40).toList())
              .timeout(const Duration(seconds: 4));
          for (final row in rows) {
            players[row['id'].toString()] = row;
          }
        } catch (_) {
          break;
        }
      }
      if (!mounted || _currentLiveSnapshot?.gameId != live.gameId) return;
      final history = events.map((event) {
        final raw = event['event_data'];
        final data = raw is Map ? raw : const {};
        // En un out de corredor, priorizar al retirado sobre el bateador.
        final action = event['event_type']?.toString().trim().toUpperCase();
        final playerId = (action == 'RUNNER_OUT' || action == 'DOUBLE_PLAY')
            ? (data['last_out_player_id'] ?? data['runner_id'] ?? data['batter_id'])
            : (data['batter_id'] ?? data['runner_id'] ?? data['last_out_player_id']);
        final player = players[playerId?.toString()];
        final name = '${player?['first_name'] ?? ''} ${player?['last_name'] ?? ''}'.trim();
        // La doble matanza involucra a dos peloteros distintos: el corredor
        // retirado y el bateador. Mostrar ambos sin atribuir el out a uno solo.
        final dpBatter = players[data['batter_id']?.toString()];
        final dpBatterName = '${dpBatter?['first_name'] ?? ''} ${dpBatter?['last_name'] ?? ''}'.trim();
        final dpDescription = action == 'DOUBLE_PLAY' && dpBatterName.isNotEmpty
            ? 'Doble play · bateador: $dpBatterName'
            : 'Doble play';
        final hitBase = int.tryParse('${data['batter_base']}');
        final (notation, description) = switch (action) {
          'HIT' => switch (hitBase) {
            1 => ('H1', 'Sencillo'),
            2 => ('H2', 'Doble'),
            3 => ('H3', 'Triple'),
            4 => ('HR', 'Jonrón'),
            _ => ('H', 'Hit'),
          },
          'BALL' => ('BB', 'Base por bolas'),
          'STRIKE' => ('K', 'Ponche'),
          'OUT' => ('O', 'Out'),
          'UNDO_OUT' => ('ANULADO', 'OUT anulado · corrección registrada'),
          'SUBSTITUTION' => ('SUST', 'Sustitución'),
          'GHOST_RUNNER' => ('CF', 'Corredor fantasma en segunda'),
          'RUNNER_MOVE' => ('AV', 'Movimiento de corredor'),
          'RUNNER_OUT' => ('O', 'Out del corredor'),
          'DOUBLE_PLAY' => ('DP', dpDescription),
          'SACRIFICE_FLY' => ('SF', 'Fly de sacrificio'),
          'RUN' => ('CARRERA', 'Carrera registrada'),
          'ERROR' => ('E', 'Error registrado'),
          _ => ('JUGADA', 'Evento del partido'),
        };
        // V5.7 guarda outs_added y destinos sin prefijo p_ en el evento.
        // Conservar compatibilidad con el historial de versiones anteriores.
        final outsAdded = int.tryParse('${data['outs_added'] ?? data['outs']}') ?? 0;
        final runnerDestinations = [
          data['first_to'] ?? data['p_first_to'],
          data['second_to'] ?? data['p_second_to'],
          data['third_to'] ?? data['p_third_to'],
        ];
        final outLocations = <String>[
          for (final destination in runnerDestinations)
            if (int.tryParse('$destination') case final int base when base < 0)
              switch (base) {
                -2 => 'segunda',
                -3 => 'tercera',
                -4 => 'home',
                _ => 'base desconocida',
              },
        ];
        final outRunner = players[data['out_runner_id']?.toString()];
        final outRunnerName =
            '${outRunner?['first_name'] ?? ''} ${outRunner?['last_name'] ?? ''}'.trim();
        final outDetail = outLocations.isEmpty
            ? ''
            : ' · ${outRunnerName.isEmpty ? 'out' : '$outRunnerName: out'} en ${outLocations.join(' y ')}';
        return SwlScorePlayRecord(
          inning: (event['inning'] as num?)?.toInt() ?? live.inning,
          isTopInning: event['is_top'] == true,
          description: outsAdded > 0 && (action == 'HIT' || action == 'ERROR')
              ? '$description · $outsAdded out(s)$outDetail'
              : description,
          notation: notation,
          batterName: name.isEmpty ? 'Partido' : name,
        );
      }).toList();
      final followLatest = playsLog.isEmpty ||
          (_historyScroll.hasClients && _historyScroll.position.extentAfter < 32);
      final appended = history.length > playsLog.length;
      setState(() {
        _historyPlayers.addAll(players);
        playsLog
          ..clear()
          ..addAll(history);
        _historyReadError = null;
      });
      if (followLatest && appended) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _historyScroll.hasClients) {
            _historyScroll.jumpTo(_historyScroll.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {
      if (mounted && _currentLiveSnapshot?.gameId == live.gameId) {
        setState(() => _historyReadError = 'No se pudo actualizar el historial. Reintentando…');
      }
    } finally {
      _historyLoading = false;
      if (_historyQueued && mounted) {
        _historyQueued = false;
        // La consulta solicitada durante la carga debe terminar antes
        // de que el mánager pueda iniciar otra jugada.
        await _refreshLiveHistory();
      } else {
        _historyQueued = false;
        final idle = _historyIdleCompleter;
        _historyIdleCompleter = null;
        if (idle != null && !idle.isCompleted) idle.complete();
      }
    }
  }

  String? _liveActionError;

  Future<void> _refreshLiveScore({bool forceLineups = false}) async {
    final snapshot = _currentLiveSnapshot;
    if (!mounted || snapshot == null || snapshot.gameId.isEmpty) return;
    if (_refreshInFlight) {
      _scoreQueued = true;
      await _scoreIdleCompleter?.future;
      return;
    }
    _scoreIdleCompleter ??= Completer<void>();
    _refreshInFlight = true;
    try {
      final row = await Supabase.instance.client.from('swl_live_games')
          .select().eq('id', snapshot.gameId).maybeSingle()
          .timeout(const Duration(seconds: 12));
      if (!mounted || row == null || _currentLiveSnapshot?.gameId != snapshot.gameId) return;
      final latest = SwlLiveScoreboardSnapshot.fromGame(row);
      final previous = _currentLiveSnapshot;
      if (previous != null && latest.version < previous.version) return;
      final versionChanged = latest.version != previous?.version;
      // La autorización puede cambiar sin generar un evento de anotación.
      // Actualizar también el estado de mánagers, turno y cierre del partido.
      final accessChanged = latest.homeManagerId != previous?.homeManagerId ||
          latest.awayManagerId != previous?.awayManagerId ||
          latest.homeTeamId != previous?.homeTeamId ||
          latest.awayTeamId != previous?.awayTeamId ||
          latest.isTop != previous?.isTop ||
          latest.status != previous?.status;
      if (versionChanged || accessChanged) {
        setState(() {
          _currentLiveSnapshot = latest;
          _syncLiveSnapshot();
        });
      }
      // Una alineación puede cambiar sin incrementar la versión del marcador.
      // Revalidarla periódicamente evita mostrar un orden al bate obsoleto.
      _livePollCount++;
      if (forceLineups || versionChanged || _lastLineupRefreshVersion != latest.version ||
          _livePollCount % 3 == 0) {
        await _loadLiveLineups();
      }
    } catch (_) {
      // La pizarra conserva el último estado conocido sin conexión.
    } finally {
      _refreshInFlight = false;
      if (_scoreQueued && mounted) {
        _scoreQueued = false;
        // Una jugada confirmada durante el sondeo requiere otra lectura.
        await _refreshLiveScore();
      } else {
        _scoreQueued = false;
        final idle = _scoreIdleCompleter;
        _scoreIdleCompleter = null;
        if (idle != null && !idle.isCompleted) idle.complete();
      }
    }
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    _historyScroll.dispose();
    super.dispose();
  }

  late String homeName;

  List<int?> visitorInningRuns = [0, null, null, null, null, null];
  List<int?> homeInningRuns = [null, null, null, null, null, null];

  int visitorHits = 0;
  int homeHits = 0;
  int visitorErrors = 0;
  int homeErrors = 0;

  int inning = 1;
  bool isTopInning = true;

  int balls = 0;
  int strikes = 0;
  int outs = 0;

  bool on1B = false;
  bool on2B = false;
  bool on3B = false;

  @override
  void initState() {
    super.initState();
    visitorName = widget.awayTeam;
    homeName = widget.homeTeam;
    visitorPitcher = SwlScorePitcher(name: 'Lanzador visitante', number: '-', teamName: visitorName);
    homePitcher = SwlScorePitcher(name: 'Lanzador local', number: '-', teamName: homeName);
    _currentLiveSnapshot = widget.liveSnapshot;
    _syncLiveSnapshot();
    if (widget.liveSnapshot != null) {
      Future.microtask(_loadLiveLineups);
      Future.microtask(_refreshLiveHistory);
      _liveRefreshTimer = Timer.periodic(
        const Duration(seconds: 4), (_) {
          unawaited(_refreshLiveScore());
          unawaited(_refreshLiveHistory());
        });
    }
  }

  // Vista de lectura de un partido real: conserva el diseño original, pero
  // impide que los controles locales alteren un marcador de demostración.
  void _syncLiveSnapshot() {
    final live = _currentLiveSnapshot;
    if (live == null) return;
    inning = live.inning;
    isTopInning = live.isTop;
    balls = live.balls;
    strikes = live.strikes;
    outs = live.outs;
    visitorHits = live.awayHits;
    homeHits = live.homeHits;
    visitorErrors = live.awayErrors;
    homeErrors = live.homeErrors;
    on1B = live.firstOccupied;
    on2B = live.secondOccupied;
    on3B = live.thirdOccupied;
    visitorInningRuns = swlDisplayInnings(live.awayInnings, inning: live.inning,
      top: live.isTop, home: false, halfEnded: live.finalHalfCompleted);
    homeInningRuns = swlDisplayInnings(live.homeInnings, inning: live.inning,
      top: live.isTop, home: true, halfEnded: live.finalHalfCompleted);
    while (visitorInningRuns.length < inning) { visitorInningRuns.add(null); }
    while (homeInningRuns.length < inning) { homeInningRuns.add(null); }
  }

  @override
  void didUpdateWidget(covariant SwlAdvancedScoreboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.liveSnapshot;
    final current = _currentLiveSnapshot;
    if (incoming != oldWidget.liveSnapshot && (incoming == null ||
        incoming.gameId != current?.gameId ||
        incoming.version >= current!.version)) {
      if (incoming?.gameId != current?.gameId) {
        playsLog.clear();
        _historyPlayers.clear();
        _historyReadError = null;
      }
      _currentLiveSnapshot = incoming;
      _syncLiveSnapshot();
      if (incoming != null && (incoming.version != current?.version ||
          incoming.gameId != current?.gameId)) {
        Future.microtask(_loadLiveLineups);
        Future.microtask(_refreshLiveHistory);
      }
    }
  }

  // Lanzadores abridores
  late SwlScorePitcher visitorPitcher;
  late SwlScorePitcher homePitcher;

  // SwlScorePitcher activo en la loma (el que defiende)
  SwlScorePitcher get activePitcher => isTopInning ? homePitcher : visitorPitcher;

  List<SwlScorePlayer> visitorLineup = List.generate(9, (i) => SwlScorePlayer(name: "Bateador ${i + 1}", number: "-"));

  List<SwlScorePlayer> homeLineup = List.generate(9, (i) => SwlScorePlayer(name: "Bateador ${i + 1}", number: "-"));

  int visitorLineupIndex = 0;
  int homeLineupIndex = 0;

  SwlScorePlayer get currentBatter => isTopInning ? visitorLineup[visitorLineupIndex] : homeLineup[homeLineupIndex];

  // V5.3: configuración independiente del orden al bate en modo local.
  Future<void> _editLineup(bool visitor) async {
    if (playsLog.isNotEmpty || _history.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Configura la alineación antes de comenzar a anotar.')));
      return;
    }
    final source = visitor ? visitorLineup : homeLineup;
    final names = List.generate(13, (i) => TextEditingController(
      text: i < source.length ? source[i].name : 'Bateador ${i + 1}'));
    final numbers = List.generate(13, (i) => TextEditingController(
      text: i < source.length ? source[i].number : '-'));
    final roles = List.generate(13, (i) =>
        i < source.length ? source[i].battingRole : 'REGULAR');
    final positions = List.generate(13, (i) =>
        i < source.length ? source[i].defensivePosition : 'SIN');
    int count = source.length;
    try {
      final result = await showDialog<List<SwlScorePlayer>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            backgroundColor: const Color(0xFF16202C),
            title: Text('ALINEACIÓN · ${visitor ? visitorName : homeName}',
                style: const TextStyle(color: Colors.amber, fontSize: 17)),
            content: SizedBox(width: 440, height: 440, child: Column(children: [
              DropdownButton<int>(
                value: count,
                dropdownColor: const Color(0xFF16202C),
                style: const TextStyle(color: Colors.white),
                items: List.generate(5, (i) => DropdownMenuItem(
                  value: i + 9, child: Text('${i + 9} bateadores'))),
                onChanged: (value) => update(() => count = value ?? count),
              ),
              const Text('Defensa: P, C, 1B, 2B, 3B, SS, LF, CF, RF. DH/AH sin defensa.',
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
              const Text('Orden al bate · configuración local antes del partido',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
              Expanded(child: ListView.builder(itemCount: count, itemBuilder: (_, i) =>
                Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 465, child: Row(children: [
                  SizedBox(width: 28, child: Text('${i + 1}.',
                      style: const TextStyle(color: Colors.amber))),
                  Expanded(child: TextField(controller: names[i],
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Nombre', isDense: true,
                        labelStyle: TextStyle(color: Colors.white70)))),
                  const SizedBox(width: 6),
                  SizedBox(width: 91, child: DropdownButton<String>(
                    isExpanded: true,
                    value: roles[i],
                    dropdownColor: const Color(0xFF16202C),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    items: const [
                      DropdownMenuItem(value: 'REGULAR', child: Text('Normal')),
                      DropdownMenuItem(value: 'DH', child: Text('DH')),
                      DropdownMenuItem(value: 'AH', child: Text('AH')),
                    ],
                    onChanged: (value) => update(() =>
                        roles[i] = value ?? 'REGULAR'),
                  )),
                  const SizedBox(width: 4),
                  SizedBox(width: 62, child: DropdownButton<String>(
                    isExpanded: true,
                    value: positions[i],
                    dropdownColor: const Color(0xFF16202C),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    items: const ['SIN', 'P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF']
                        .map((position) => DropdownMenuItem(
                          value: position, child: Text(position))).toList(),
                    onChanged: (value) => update(() => positions[i] = value ?? 'SIN'),
                  )),
                  const SizedBox(width: 4),
                  SizedBox(width: 46, child: TextField(controller: numbers[i],
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: '#', isDense: true,
                        labelStyle: TextStyle(color: Colors.white70)))),
                ])))),
              )),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCELAR')),
              FilledButton(onPressed: () {
                if (List.generate(count, (i) => names[i].text.trim())
                    .any((name) => name.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Todos los bateadores deben tener nombre.')));
                  return;
                }
                final normalizedNames = List.generate(count,
                    (i) => names[i].text.trim().toLowerCase());
                if (normalizedNames.toSet().length != count) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('No repitas el mismo bateador en la alineación.')));
                  return;
                }
                final assignedNumbers = List.generate(count,
                    (i) => numbers[i].text.trim())
                    .where((number) => number.isNotEmpty && number != '-')
                    .toList();
                if (assignedNumbers.toSet().length != assignedNumbers.length) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('No repitas números de uniforme en la alineación.')));
                  return;
                }
                if (roles.take(count).where((role) => role == 'DH').length > 1) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Solo puede haber un DH por alineación.')));
                  return;
                }
                // DH y AH son roles exclusivamente ofensivos en la alineación inicial.
                // Si existe DH, el pitcher no puede ocupar un turno en este orden.
                final hasDh = roles.take(count).contains('DH');
                if (hasDh && positions.take(count).contains('P')) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Con DH, el pitcher no debe figurar como bateador.')));
                  return;
                }
                for (var i = 0; i < count; i++) {
                  if (roles[i] == 'DH' && positions[i] != 'SIN') {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('El DH no puede tener posición defensiva inicial.')));
                    return;
                  }
                }
                final assignedPositions = positions.take(count)
                    .where((position) => position != 'SIN').toList();
                if (assignedPositions.toSet().length != assignedPositions.length) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('No puedes asignar la misma posición defensiva dos veces.')));
                  return;
                }
                for (var i = 0; i < count; i++) {
                  if (roles[i] == 'AH' && positions[i] != 'SIN') {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Un AH no debe tener posición defensiva inicial.')));
                    return;
                  }
                }
                final ids = source.take(count).map((p) => p.playerId).whereType<String>().toList();
                if (ids.toSet().length != ids.length) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Hay IDs de peloteros duplicados.')));
                  return;
                }
                Navigator.pop(dialogContext, List.generate(count, (i) =>
                  SwlScorePlayer(name: names[i].text.trim(),
                    playerId: i < source.length &&
                      source[i].name == names[i].text.trim() &&
                      source[i].number == (numbers[i].text.trim().isEmpty ? '-' : numbers[i].text.trim())
                        ? source[i].playerId : null,
                    defensivePosition: positions[i],
                    battingRole: roles[i],
                    number: numbers[i].text.trim().isEmpty ? '-' : numbers[i].text.trim())));
              }, child: const Text('GUARDAR')),
            ],
          ),
        ),
      );
      if (!mounted || result == null) return;
      setState(() {
        if (visitor) { visitorLineup = result; visitorLineupIndex = 0; }
        else { homeLineup = result; homeLineupIndex = 0; }
      });
    } finally {
      for (final c in names) { c.dispose(); }
      for (final c in numbers) { c.dispose(); }
    }
  }

  // V5.3: sustitución local de bateador, sin alterar turnos ya registrados.
  Future<void> _substituteBatter(bool visitor) async {
    // La sustitución local requiere un turno existente. En vivo se usa
    // exclusivamente la operación persistente proporcionada por el padre.
    if (widget.liveSnapshot != null) return;
    final lineup = visitor ? visitorLineup : homeLineup;
    if (lineup.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Primero configura la alineación de este equipo.')));
      }
      return;
    }
    int selected = visitor ? visitorLineupIndex : homeLineupIndex;
    if (selected < 0 || selected >= lineup.length) selected = 0;
    final name = TextEditingController();
    final number = TextEditingController();
    try {
      final replacement = await showDialog<SwlScorePlayer>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            backgroundColor: const Color(0xFF16202C),
            title: const Text('SUSTITUCIÓN DE BATEADOR',
                style: TextStyle(color: Colors.amber, fontSize: 17)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<int>(
                isExpanded: true,
                value: selected,
                dropdownColor: const Color(0xFF16202C),
                style: const TextStyle(color: Colors.white),
                items: List.generate(lineup.length, (i) => DropdownMenuItem(
                  value: i,
                  child: Text('${i + 1}. ${lineup[i].name}', overflow: TextOverflow.ellipsis),
                )),
                onChanged: (value) => update(() => selected = value ?? selected),
              ),
              TextField(controller: name,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Nombre del sustituto',
                  labelStyle: TextStyle(color: Colors.white70))),
              TextField(controller: number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Número del sustituto',
                  labelStyle: TextStyle(color: Colors.white70))),
              const SizedBox(height: 8),
              const Text('El sustituto ocupará el mismo turno y rol. '
                  'Las estadísticas previas permanecen en el historial de jugadas.',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCELAR')),
              FilledButton(onPressed: () {
                final newName = name.text.trim();
                final newNumber = number.text.trim();
                if (newName.isEmpty ||
                    lineup.asMap().entries.any((entry) =>
                      entry.key != selected &&
                      entry.value.name.toLowerCase() == newName.toLowerCase()) ||
                    (newNumber.isNotEmpty && newNumber != '-' &&
                     lineup.asMap().entries.any((entry) =>
                       entry.key != selected && entry.value.number == newNumber))) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Revisa el nombre y número: no deben estar vacíos ni repetidos.')));
                  return;
                }
                Navigator.pop(dialogContext, SwlScorePlayer(
                  name: newName,
                  number: newNumber.isEmpty ? '-' : newNumber,
                  battingRole: lineup[selected].battingRole,
                  defensivePosition: lineup[selected].defensivePosition,
                ));
              }, child: const Text('SUSTITUIR')),
            ],
          ),
        ),
      );
      if (!mounted || replacement == null) return;
      _saveState();
      setState(() {
        if (visitor) {
          visitorLineup[selected] = replacement;
        } else {
          homeLineup[selected] = replacement;
        }
      });
    } finally {
      name.dispose();
      number.dispose();
    }
  }

  final List<SwlScorePlayRecord> playsLog = [];
  final List<SwlScoreGameSnapshot> _history = [];

  int get currentInningsCount => max(6, max(visitorInningRuns.length, inning));
  int get visitorTotalRuns => _currentLiveSnapshot?.awayRuns ?? visitorInningRuns.whereType<int>().fold(0, (a, b) => a + b);
  int get homeTotalRuns => _currentLiveSnapshot?.homeRuns ?? homeInningRuns.whereType<int>().fold(0, (a, b) => a + b);

  void _saveState() {
    _history.add(SwlScoreGameSnapshot(
      balls: balls,
      strikes: strikes,
      outs: outs,
      inning: inning,
      isTopInning: isTopInning,
      on1B: on1B,
      on2B: on2B,
      on3B: on3B,
      visitorInningRuns: List.from(visitorInningRuns),
      homeInningRuns: List.from(homeInningRuns),
      visitorHits: visitorHits,
      homeHits: homeHits,
      visitorErrors: visitorErrors,
      homeErrors: homeErrors,
      visitorLineupIndex: visitorLineupIndex,
      homeLineupIndex: homeLineupIndex,
      visitorLineup: visitorLineup.map((p) => p.copy()).toList(),
      homeLineup: homeLineup.map((p) => p.copy()).toList(),
      visitorPitcher: visitorPitcher.copy(),
      homePitcher: homePitcher.copy(),
      plays: List.from(playsLog),
    ));
    if (_history.length > 30) _history.removeAt(0);
  }

  void _undo() {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    setState(() {
      balls = last.balls;
      strikes = last.strikes;
      outs = last.outs;
      inning = last.inning;
      isTopInning = last.isTopInning;
      on1B = last.on1B;
      on2B = last.on2B;
      on3B = last.on3B;
      visitorInningRuns = List.from(last.visitorInningRuns);
      homeInningRuns = List.from(last.homeInningRuns);
      visitorHits = last.visitorHits;
      homeHits = last.homeHits;
      visitorErrors = last.visitorErrors;
      homeErrors = last.homeErrors;
      visitorLineupIndex = last.visitorLineupIndex;
      homeLineupIndex = last.homeLineupIndex;
      visitorLineup = last.visitorLineup.map((p) => p.copy()).toList();
      homeLineup = last.homeLineup.map((p) => p.copy()).toList();
      visitorPitcher = last.visitorPitcher.copy();
      homePitcher = last.homePitcher.copy();
      playsLog.clear();
      playsLog.addAll(last.plays);
    });
  }

  void _resetCount() {
    balls = 0;
    strikes = 0;
  }

  void _nextBatter() {
    if (isTopInning) {
      visitorLineupIndex = (visitorLineupIndex + 1) % visitorLineup.length;
    } else {
      homeLineupIndex = (homeLineupIndex + 1) % homeLineup.length;
    }
  }

  void _nextHalfInning() {
    _resetCount();
    on1B = false;
    on2B = false;
    on3B = false;
    outs = 0;

    if (isTopInning) {
      isTopInning = false;
      while (homeInningRuns.length < inning) {
        homeInningRuns.add(null);
      }
      homeInningRuns[inning - 1] ??= 0;
    } else {
      isTopInning = true;
      inning++;
      while (visitorInningRuns.length < inning) {
        visitorInningRuns.add(null);
      }
      while (homeInningRuns.length < inning) {
        homeInningRuns.add(null);
      }
      visitorInningRuns[inning - 1] = 0;
    }
  }

  void _addRunsToCurrentInning(int runs) {
    if (runs <= 0) return;
    activePitcher.runsAllowed += runs; // Se le cargan al lanzador en la loma
    final idx = inning - 1;
    if (isTopInning) {
      while (visitorInningRuns.length <= idx) visitorInningRuns.add(null);
      visitorInningRuns[idx] = (visitorInningRuns[idx] ?? 0) + runs;
    } else {
      while (homeInningRuns.length <= idx) homeInningRuns.add(null);
      homeInningRuns[idx] = (homeInningRuns[idx] ?? 0) + runs;
    }
  }

  // MODAL AL TOCAR EL PITCHER
  void _showPitcherDetailsModal() {
    final p = activePitcher;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(backgroundColor: Colors.amber, radius: 18, child: Icon(Icons.sports, color: Colors.black, size: 20)),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${p.name} #${p.number}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text("Lanzador de ${p.teamName}", style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              const Text("ESTADÍSTICAS DEL DÍA:", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statTile("IP (Entradas)", p.ip, Colors.amberAccent),
                  _statTile("K (Ponches)", "${p.strikeouts}", Colors.redAccent),
                  _statTile("BB (Boletos)", "${p.walks}", Colors.tealAccent),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statTile("H (Hits)", "${p.hitsAllowed}", Colors.blueAccent),
                  _statTile("C (Carreras)", "${p.runsAllowed}", Colors.orangeAccent),
                  _statTile("Outs Hechos", "${p.outsRecorded}", Colors.white70),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // MODAL AL TOCAR EL BATEADOR
  void _showBatterDetailsModal() {
    final b = currentBatter;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(backgroundColor: Colors.blueAccent, radius: 18, child: Icon(Icons.sports_baseball, color: Colors.white, size: 20)),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${b.name} #${b.number}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(isTopInning ? visitorName : homeName, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(color: Colors.white24, height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statTile("Turnos (AB)", "${b.ab}", Colors.white),
                  _statTile("Hits (H)", "${b.hits}", Colors.greenAccent),
                  _statTile("BB (Bolas)", "${b.bb}", Colors.tealAccent),
                  _statTile("PROMEDIO", b.battingAverage, Colors.amberAccent),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              const Text("TURNO POR TURNO EN ESTE JUEGO:", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: b.gameLog.isEmpty
                    ? const Center(child: Text("Aún no ha completado su primer turno.", style: TextStyle(color: Colors.white38, fontSize: 12)))
                    : ListView.builder(
                        itemCount: b.gameLog.length,
                        itemBuilder: (ctx, i) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(4)),
                                  child: Text("${i + 1}° Turno", style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(b.gameLog[i], style: const TextStyle(color: Colors.white70, fontSize: 12))),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Container(
      width: 95,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // ACCIÓN: BASE POR BOLAS (BB)
  void _recordWalk() {
    final batter = widget.liveSnapshot == null ||
            _lastLineupRefreshVersion == _currentLiveSnapshot?.version
        ? currentBatter
        : SwlScorePlayer(name: 'Bateador por sincronizar', number: '-');
    final pitcher = widget.liveSnapshot == null
        ? activePitcher
        : SwlScorePitcher(name: 'Lanzador por sincronizar', number: '-',
            teamName: isTopInning ? homeName : visitorName);

    batter.bb++;
    pitcher.walks++; // Suma boleto al lanzador

    final String logDesc = "${inning}ra ${isTopInning ? 'Alta' : 'Baja'} · Base por Bolas (BB)";
    batter.gameLog.add(logDesc);

    playsLog.insert(0, SwlScorePlayRecord(
      inning: inning,
      isTopInning: isTopInning,
      description: "Recibió Base por Bolas (BB)",
      notation: "BB",
      batterName: "${batter.name} #${batter.number}",
    ));

    _resetCount();
    _nextBatter();

    if (on1B && on2B && on3B) {
      _addRunsToCurrentInning(1);
    } else if (on1B && on2B) {
      on3B = true;
    } else if (on1B) {
      on2B = true;
    }
    on1B = true;
  }

  // ACCIÓN: ERROR
  void _recordErrorByOpponent(String posCode, String posName) {
    _saveState();
    setState(() {
      final batter = currentBatter;
      batter.ab++;

      if (isTopInning) {
        homeErrors++;
      } else {
        visitorErrors++;
      }

      final String logDesc = "${inning}ra ${isTopInning ? 'Alta' : 'Baja'} · Llegó por Error del $posName (E$posCode)";
      batter.gameLog.add(logDesc);

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: "Llegó a salvo por Error del $posName ($posCode)",
        notation: "E$posCode",
        batterName: "${batter.name} #${batter.number}",
      ));

      _resetCount();
      _nextBatter();

      if (on1B && on2B && on3B) {
        _addRunsToCurrentInning(1);
      } else if (on1B && on2B) {
        on3B = true;
      } else if (on1B) {
        on2B = true;
      }
      on1B = true;
    });
  }

  // ACCIÓN: OUT DETALLADO
  void _recordOutWithDetails(
    String notation,
    String description, {
    bool isSacrifice = false,
    bool isDoublePlay = false,
    bool isStrikeout = false,
  }) {
    _saveState();
    setState(() {
      final batter = currentBatter;
      final pitcher = activePitcher;

      if (!isSacrifice) {
        batter.ab++;
      }

      if (isStrikeout) {
        pitcher.strikeouts++; // Ponche sumado al lanzador
      }

      final String logDesc = "${inning}ra ${isTopInning ? 'Alta' : 'Baja'} · $description ($notation)";
      batter.gameLog.add(logDesc);

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: description,
        notation: notation,
        batterName: "${batter.name} #${batter.number}",
      ));

      _resetCount();
      _nextBatter();

      if (isSacrifice && on3B) {
        _addRunsToCurrentInning(1);
        on3B = false;
      }

      if (isDoublePlay) {
        pitcher.outsRecorded += 2; // El pitcher suma 2 outs
        if (on1B) on1B = false;
        else if (on2B) on2B = false;
        else if (on3B) on3B = false;

        if (outs + 2 >= 3) {
          _nextHalfInning();
        } else {
          outs += 2;
        }
      } else {
        pitcher.outsRecorded += 1; // El pitcher suma 1 out
        if (outs < 2) {
          outs++;
        } else {
          _nextHalfInning();
        }
      }
    });
  }

  // ACCIÓN: HIT
  void recordHit(String type, String desc) {
    _saveState();
    setState(() {
      final batter = currentBatter;
      final pitcher = activePitcher;

      batter.ab++;
      batter.hits++;
      pitcher.hitsAllowed++; // El pitcher permite un hit

      if (isTopInning) {
        visitorHits++;
      } else {
        homeHits++;
      }

      final String logDesc = "${inning}ra ${isTopInning ? 'Alta' : 'Baja'} · Conectó $desc ($type)";
      batter.gameLog.add(logDesc);

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: desc,
        notation: type,
        batterName: "${batter.name} #${batter.number}",
      ));

      _resetCount();
      _nextBatter();

      int runsScored = 0;
      if (type == "H") {
        if (on3B) { runsScored++; on3B = false; }
        if (on2B) { on3B = true; on2B = false; }
        if (on1B) { on2B = true; }
        on1B = true;
      } else if (type == "H2") {
        if (on3B) { runsScored++; on3B = false; }
        if (on2B) { runsScored++; }
        if (on1B) { on3B = true; on1B = false; }
        on2B = true;
      } else if (type == "H3") {
        if (on3B) runsScored++;
        if (on2B) runsScored++;
        if (on1B) runsScored++;
        on1B = false;
        on2B = false;
        on3B = true;
      } else if (type == "HR") {
        runsScored = 1;
        if (on1B) runsScored++;
        if (on2B) runsScored++;
        if (on3B) runsScored++;
        on1B = false;
        on2B = false;
        on3B = false;
      }

      _addRunsToCurrentInning(runsScored);
    });
  }

  void _openRunnerActionModal(int base) {
    final String baseName = base == 1 ? "1ra Base" : (base == 2 ? "2da Base" : "3ra Base");

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("CORREDOR EN $baseName", style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Text("¿Qué ocurrió con este corredor?", style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 14),
              const Text("OUT EN LAS BASES (SUMA OUT Y QUITA CORREDOR):", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.cancel, color: Colors.white, size: 18),
                      label: const Text("Out Robando (CS)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _recordBaseOut(base, "CS", "Out Robando en $baseName (CS)");
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900, padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.flash_on, color: Colors.white, size: 18),
                      label: const Text("Sorprendido / Viraje", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _recordBaseOut(base, "PO", "Sorprendido en $baseName por viraje (PO)");
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text("AVANCES Y CARRERAS:", style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (base < 3)
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), padding: const EdgeInsets.symmetric(vertical: 12)),
                        icon: const Icon(Icons.directions_run, color: Colors.white, size: 18),
                        label: Text("Robó ${base == 1 ? '2da (SB)' : '3ra (SB)'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _advanceRunner(base, isSteal: true);
                        },
                      ),
                    ),
                  if (base < 3) const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.sports_baseball, color: Colors.white, size: 18),
                      label: const Text("Anotó Carrera", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _scoreRunner(base);
                      },
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 18),
                  label: const Text("Solo quitar corredor (Error de dedo / Sin out)", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _saveState();
                    setState(() {
                      if (base == 1) on1B = false;
                      if (base == 2) on2B = false;
                      if (base == 3) on3B = false;
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _recordBaseOut(int base, String notation, String description) {
    _saveState();
    setState(() {
      activePitcher.outsRecorded += 1;
      if (base == 1) on1B = false;
      if (base == 2) on2B = false;
      if (base == 3) on3B = false;

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: description,
        notation: notation,
        batterName: "Corredor en base",
      ));

      if (outs < 2) {
        outs++;
      } else {
        _nextHalfInning();
      }
    });
  }

  void _advanceRunner(int base, {bool isSteal = false}) {
    _saveState();
    setState(() {
      if (base == 1) { on1B = false; on2B = true; }
      else if (base == 2) { on2B = false; on3B = true; }

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: isSteal ? "Robó base con éxito" : "Avanzó de base",
        notation: "SB",
        batterName: "Corredor en base",
      ));
    });
  }

  void _scoreRunner(int base) {
    _saveState();
    setState(() {
      if (base == 1) on1B = false;
      if (base == 2) on2B = false;
      if (base == 3) on3B = false;

      _addRunsToCurrentInning(1);

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: "Anotó carrera en jugada de corrido",
        notation: "CARRERA",
        batterName: "Corredor en base",
      ));
    });
  }

  void _openBatazoSelector() {
    String? selectedFielder;
    final bool hasRunners = on1B || on2B || on3B;
    final bool canDoublePlay = hasRunners && outs < 2;
    final bool canSacrifice = on3B && outs < 2;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: 550,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("REGISTRO DE BATAZO / JUGADA", style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),

                    const Text("FALLO AL CAMPO (OUT DE 1 TOQUE):", style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _quickOutChip(ctx, "Fallo al 8 (Center)", "F8"),
                        _quickOutChip(ctx, "Fallo al 7 (Left)", "F7"),
                        _quickOutChip(ctx, "Fallo al 9 (Right)", "F9"),
                        _quickOutChip(ctx, "Fallo al 3 (1B)", "F3"),
                        _quickOutChip(ctx, "Fallo al 4 (2B)", "F4"),
                        _quickOutChip(ctx, "Fallo al 5 (3B)", "F5"),
                        _quickOutChip(ctx, "Fallo al 6 (Siore)", "F6"),
                      ],
                    ),

                    if (canDoublePlay || canSacrifice) ...[
                      const SizedBox(height: 10),
                      const Text("JUGADAS ESPECIALES:", style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (canDoublePlay)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _recordOutWithDetails("DP", "Doble Play", isDoublePlay: true);
                              },
                              child: const Text("Doble Play (DP)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          if (canSacrifice)
                            _quickOutChip(ctx, "SF8 (Sacrificio al 8)", "SF8", isSac: true),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade900.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade800),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                "ERROR (SE LE CARGA AL CONTRARIO: ${isTopInning ? homeName.toUpperCase() : visitorName.toUpperCase()}):",
                                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _errorChip(ctx, "E5 (3ra)", "5", "3ra Base"),
                              _errorChip(ctx, "E6 (Siore)", "6", "Campocorto"),
                              _errorChip(ctx, "E4 (2da)", "4", "Segunda Base"),
                              _errorChip(ctx, "E3 (1ra)", "3", "Primera Base"),
                              _errorChip(ctx, "E1 (Picher)", "1", "Lanzador"),
                              _errorChip(ctx, "E2 (Quech)", "2", "Receptor"),
                              _errorChip(ctx, "E7 (Left)", "7", "Left Field"),
                              _errorChip(ctx, "E8 (Center)", "8", "Center Field"),
                              _errorChip(ctx, "E9 (Right)", "9", "Right Field"),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Divider(color: Colors.white24, height: 20),

                    const Text("ROLATA O TIRO A CUALQUIER BASE (2 TOQUES):", style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),

                    Text(
                      selectedFielder == null ? "1️⃣ Toca quién fildeó la pelota:" : "Pelota fildeada por: $selectedFielder",
                      style: TextStyle(color: selectedFielder == null ? Colors.white70 : Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _fielderBtn("1", "1", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                        const SizedBox(width: 4),
                        _fielderBtn("5", "5", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                        const SizedBox(width: 4),
                        _fielderBtn("6", "6", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                        const SizedBox(width: 4),
                        _fielderBtn("4", "4", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                        const SizedBox(width: 4),
                        _fielderBtn("3", "3", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      selectedFielder == null ? "2️⃣ Luego elige a dónde tiró:" : "2️⃣ ¿A qué base tiró el $selectedFielder?:",
                      style: TextStyle(color: selectedFielder != null ? Colors.amber : Colors.white30, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _targetBaseBtn(ctx, "A Home (2)", "2", "Tiro a Home", selectedFielder),
                        _targetBaseBtn(ctx, "A 1ra (3)", "3", "Tiro a Primera", selectedFielder),
                        _targetBaseBtn(ctx, "A 2da (4)", "4", "Tiro a Segunda", selectedFielder),
                        _targetBaseBtn(ctx, "A 2da (6)", "6", "Tiro a Segunda vía Siore", selectedFielder),
                        _targetBaseBtn(ctx, "A 3ra (5)", "5", "Tiro a Tercera", selectedFielder),
                        _targetBaseBtn(ctx, "Pisa base (Solo)", "U", "Out sin asistencia (Pisó la base)", selectedFielder),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _errorChip(BuildContext ctx, String label, String posCode, String posName) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6)),
      onPressed: () {
        Navigator.pop(ctx);
        _recordErrorByOpponent(posCode, posName);
      },
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _quickOutChip(BuildContext ctx, String label, String not, {bool isSac = false}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: isSac ? const Color(0xFF059669) : const Color(0xFF334155), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
      onPressed: () {
        Navigator.pop(ctx);
        _recordOutWithDetails(not, label, isSacrifice: isSac);
      },
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _fielderBtn(String label, String code, String? selected, Function(String) onSelect) {
    final isSelected = selected == code;
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.amber : const Color(0xFF0F172A),
          foregroundColor: isSelected ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          side: BorderSide(color: isSelected ? Colors.amber : Colors.white24),
        ),
        onPressed: () => onSelect(code),
        child: Text(code, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _targetBaseBtn(BuildContext ctx, String label, String baseCode, String desc, String? selectedFielder) {
    final isEnabled = selectedFielder != null;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isEnabled ? const Color(0xFF2563EB) : Colors.white10,
        foregroundColor: isEnabled ? Colors.white : Colors.white24,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
      onPressed: !isEnabled ? null : () {
        Navigator.pop(ctx);
        String finalNotation = baseCode == "U" ? "${selectedFielder}U" : "$selectedFielder-$baseCode";
        String finalDesc = baseCode == "U" ? "Rolata al $selectedFielder (Pisa la base)" : "Rolata del $selectedFielder · $desc ($finalNotation)";
        _recordOutWithDetails(finalNotation, finalDesc);
      },
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncedBatter = _lastLineupRefreshVersion == _currentLiveSnapshot?.version &&
        (isTopInning ? _awayBatterConfirmed : _homeBatterConfirmed) &&
        currentBatter.playerId != null;
    final batter = widget.liveSnapshot == null || syncedBatter
        ? currentBatter
        : SwlScorePlayer(name: 'Bateador por sincronizar', number: '-');
    final pitcher = activePitcher;

    final scoreboard = Scaffold(
      backgroundColor: const Color(0xFF0B1118),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16202C),
        elevation: 0,
        title: Text(widget.liveSnapshot == null ? '⚾ PIZARRA · PRUEBA LOCAL' : '⚾ PIZARRA · EN VIVO', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        actions: [
          if (widget.liveSnapshot != null)
            IconButton(tooltip: 'Actualizar pizarra', icon: const Icon(Icons.refresh, size: 20),
              onPressed: () async {
                // Primero actualizar la versión del partido. Esa lectura ya
                // coordina la alineación; luego recuperar el historial.
                await _refreshLiveScore(forceLineups: true);
                if (!mounted) return;
                await _refreshLiveHistory();
              }),
          if (widget.onLiveSubstitute != null || widget.onLivePitcher != null)
            PopupMenuButton<String>(
              tooltip: 'Cambios de jugadores',
              icon: const Icon(Icons.swap_horiz, color: Colors.amber),
              onSelected: (item) => item == 'batter'
                  ? widget.onLiveSubstitute?.call() : widget.onLivePitcher?.call(),
              itemBuilder: (_) => [
                if (widget.onLiveSubstitute != null)
                  const PopupMenuItem(value: 'batter', child: Text('Sustituir bateador')),
                if (widget.onLivePitcher != null)
                  const PopupMenuItem(value: 'pitcher', child: Text('Cambiar pitcher')),
              ],
            ),
          if (widget.onLiveDetails != null)
            IconButton(
              tooltip: 'Box Score, alineaciones e historial',
              onPressed: widget.onLiveDetails,
              icon: const Icon(Icons.analytics_outlined, color: Colors.amber),
            ),
          if (widget.liveSnapshot == null) PopupMenuButton<String>(
            tooltip: 'Sustituciones',
            icon: const Icon(Icons.swap_horiz, color: Colors.amber),
            onSelected: (value) => _substituteBatter(value == 'visitor'),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'visitor', child: Text('Sustituir · $visitorName')),
              PopupMenuItem(value: 'home', child: Text('Sustituir · $homeName')),
            ],
          ),
          if (widget.liveSnapshot == null) PopupMenuButton<String>(
            tooltip: 'Configurar alineaciones',
            icon: const Icon(Icons.groups, color: Colors.amber),
            onSelected: (value) => _editLineup(value == 'visitor'),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'visitor', child: Text('Alineación · $visitorName')),
              PopupMenuItem(value: 'home', child: Text('Alineación · $homeName')),
            ],
          ),
          if (widget.liveSnapshot == null) IconButton(
            icon: const Icon(Icons.undo, color: Colors.amber, size: 26),
            tooltip: "Deshacer",
            onPressed: _history.isEmpty ? null : _undo,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(widget.liveSnapshot == null ? 'PIN: ${widget.gamePin} · SOLO DEMOSTRACIÓN LOCAL · SIN SINCRONIZACIÓN' : 'PIN: ${widget.gamePin} · ${widget.onLiveAction == null ? 'SOLO LECTURA' : 'ANOTACIÓN POR EQUIPO'}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            _buildMlbLineScore(),
            _buildCountAndBases(),

            // BARRA INTERACTIVA: DUELO BATEADOR VS PITCHER (AMBOS CON CLIC)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                children: [
                  // 1. TARJETA CLICKEABLE DEL BATEADOR
                  Expanded(
                    flex: 6,
                    child: InkWell(
                      onTap: widget.liveSnapshot == null ? _showBatterDetailsModal : !syncedBatter ? null :
                          () => _showLivePlayerStats(batter.name,
                            'AB ${batter.ab} · H ${batter.hits} · RBI ${batter.rbi} · SF ${batter.sacrifices} · BB ${batter.bb}'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16202C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueGrey.shade800),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.sports_baseball, color: Colors.amber, size: 14),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    "${batter.name} #${batter.number}",
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                const Icon(Icons.info_outline, color: Colors.white38, size: 13),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.liveSnapshot == null || syncedBatter
                                  ? "de ${batter.ab}-${batter.hits} (${batter.battingAverage})"
                                  : (_lineupLoadError ?? "Estadísticas individuales pendientes de sincronización"),
                              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // 2. TARJETA CLICKEABLE DEL PITCHER EN LA LOMA
                  Expanded(
                    flex: 5,
                    child: InkWell(
                      onTap: widget.liveSnapshot == null ? _showPitcherDetailsModal :
                          () => _showLivePlayerStats(pitcher.name,
                           _pitchingConfirmed ? '${pitcher.ip} IP · ${pitcher.strikeouts} K · ${pitcher.walks} BB · ${pitcher.hitsAllowed} H\n${pitcher.pitchLine ?? 'Pitcheos sin datos'}' :
                              'Faltan datos de pitcheo de este partido.'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16202C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueGrey.shade800),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.sports, color: Colors.tealAccent, size: 14),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    "P: ${pitcher.name}",
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                const Icon(Icons.info_outline, color: Colors.white38, size: 13),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.liveSnapshot == null || (_pitchingConfirmed && pitcher.name != "Lanzador por confirmar")
                                  ? "${pitcher.ip} IP · ${pitcher.strikeouts} K"
                                  : "— IP · — K",
                              style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            _buildMainButtons(),

            const SizedBox(height: 4),

            Expanded(
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF16202C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueGrey.shade800),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("HISTORIAL JUGADA A JUGADA:", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                    const Divider(color: Colors.white24, height: 10),
                    if (_historyReadError case final String message)
                      Text(message, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                    Expanded(
                      child: playsLog.isEmpty
                          ? const Center(child: Text("Esperando primera jugada...", style: TextStyle(color: Colors.white38, fontSize: 13)))
                          : ListView.builder(
                              controller: widget.liveSnapshot == null ? null : _historyScroll,
                              itemCount: playsLog.length,
                              itemBuilder: (context, index) {
                                final p = playsLog[index];
                                final isHit = p.notation.startsWith("H");
                                final isError = p.notation.startsWith("E");
                                final isWalk = p.notation == "BB";
                                final isBaseOut = p.notation == "CS" || p.notation == "PO";

                                Color badgeColor = Colors.amber.shade700;
                                if (p.notation == "DP" || isBaseOut) badgeColor = Colors.red.shade700;
                                else if (isHit || p.notation == "CARRERA") badgeColor = Colors.green.shade700;
                                else if (isError) badgeColor = Colors.orange.shade800;
                                else if (isWalk) badgeColor = Colors.teal.shade700;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)),
                                        child: Text(p.notation, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "${p.inning}ra ${p.isTopInning ? 'Alta' : 'Baja'} · ${p.batterName}: ${p.description}",
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return scoreboard;
  }

  Widget _buildMlbLineScore() {
    final int count = currentInningsCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF16202C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade800),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 340),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24))),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: Text("EQUIPO", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  for (int i = 1; i <= count; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text(
                          "$i",
                          style: TextStyle(
                            color: inning == i ? Colors.amber : (i > 6 ? Colors.orangeAccent : Colors.white60),
                            fontWeight: inning == i ? FontWeight.bold : FontWeight.normal,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("C", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("H", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("E", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)))),
                ],
              ),
              TableRow(
                decoration: BoxDecoration(color: isTopInning ? Colors.white.withOpacity(0.04) : Colors.transparent),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                    child: Row(
                      children: [
                        if (isTopInning) const Icon(Icons.arrow_right, color: Colors.amber, size: 14),
                        if (widget.awayLogo != null) SwlTeamBadge(url: widget.awayLogo, size: 18),
                        Text(visitorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  for (int i = 0; i < count; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text(
                          (i < visitorInningRuns.length && visitorInningRuns[i] != null) ? "${visitorInningRuns[i]}" : "-",
                          style: TextStyle(
                            color: (i < visitorInningRuns.length && visitorInningRuns[i] != null) ? Colors.white : Colors.white24,
                            fontWeight: (i < visitorInningRuns.length && visitorInningRuns[i] != null && visitorInningRuns[i]! > 0) ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$visitorTotalRuns", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 13)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$visitorHits", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$visitorErrors", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)))),
                ],
              ),
              TableRow(
                decoration: BoxDecoration(color: !isTopInning ? Colors.white.withOpacity(0.04) : Colors.transparent),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                    child: Row(
                      children: [
                        if (!isTopInning) const Icon(Icons.arrow_right, color: Colors.amber, size: 14),
                        if (widget.homeLogo != null) SwlTeamBadge(url: widget.homeLogo, size: 18),
                        Text(homeName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  for (int i = 0; i < count; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text(
                          (i < homeInningRuns.length && homeInningRuns[i] != null) ? "${homeInningRuns[i]}" : "-",
                          style: TextStyle(
                            color: (i < homeInningRuns.length && homeInningRuns[i] != null) ? Colors.white : Colors.white24,
                            fontWeight: (i < homeInningRuns.length && homeInningRuns[i] != null && homeInningRuns[i]! > 0) ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$homeTotalRuns", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 13)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$homeHits", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$homeErrors", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountAndBases() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: const Color(0xFF16202C), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIndicator("B", balls, 3, Colors.greenAccent),
              const SizedBox(height: 5),
              _buildIndicator("S", strikes, 2, Colors.redAccent),
              const SizedBox(height: 5),
              _buildIndicator("O", outs, 2, Colors.amberAccent),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1118),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: inning > (_currentLiveSnapshot?.regulationInnings ?? 6) ? Colors.orangeAccent : Colors.amber.shade700),
            ),
            child: Row(
              children: [
                Icon(isTopInning ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.amber, size: 26),
                Text(
                  "${inning}ra ${inning > (_currentLiveSnapshot?.regulationInnings ?? 6) ? 'EXTRA' : (isTopInning ? 'ALTA' : 'BAJA')}",
                  style: TextStyle(color: inning > (_currentLiveSnapshot?.regulationInnings ?? 6) ? Colors.orangeAccent : Colors.amber, fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ],
            ),
          ),
          _buildDiamond(),
        ],
      ),
    );
  }

  Widget _buildIndicator(String l, int cur, int max, Color col) {
    return Row(children: [
      SizedBox(width: 18, child: Text(l, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
      ...List.generate(max, (i) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        width: 13, height: 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: i < cur ? col : Colors.black54,
          border: Border.all(color: i < cur ? col : Colors.white24, width: 1.5),
        ),
      )),
    ]);
  }

  Future<void> _sendSpecial(String action, Map<String, dynamic> data) async {
    final game = _currentLiveSnapshot;
    final user = Supabase.instance.client.auth.currentUser?.id;
    if (game == null || !game.canScore(user) || widget.onLiveAction == null || _liveActionInFlight) return;
    setState(() { _liveActionInFlight = true; _liveActionError = null; });
    try {
      swlPreviewSpecial(game.playState, action, source: data['source'] as int?,
        destination: data['destination'] as int?, firstTo: data['first_to'] as int?,
        secondTo: data['second_to'] as int?, thirdTo: data['third_to'] as int?,
        regulationInnings: game.regulationInnings);
      await widget.onLiveAction!(game.version, action, data);
      // El marcador se actualiza primero; después esperamos el historial
      // para que la jugada confirmada aparezca antes de habilitar otra.
      await _refreshLiveScore();
      await _refreshLiveHistory();
    } catch (error) {
      if (mounted) setState(() => _liveActionError = error.toString());
    } finally {
      if (mounted) setState(() => _liveActionInFlight = false);
    }
  }

  Future<void> _liveBaseMenu(int base) async {
    final game = _currentLiveSnapshot;
    if (game == null || _liveActionInFlight || widget.onLiveAction == null ||
        !game.canScore(Supabase.instance.client.auth.currentUser?.id)) return;
    if (!swlBaseOccupied(game.playState, base)) {
      if (base == 2 &&
          game.inning > game.regulationInnings &&
          game.outs == 0 && game.playState.balls == 0 &&
          game.playState.strikes == 0 &&
          !game.firstOccupied && !game.secondOccupied && !game.thirdOccupied &&
          game.homeRuns == game.awayRuns) {
        await _chooseGhost(game);
      }
      return;
    }
    bool legal(int destination) {
      try {
        swlPreviewSpecial(game.playState, 'RUNNER_MOVE', source: base, destination: destination);
        return true;
      } on StateError { return false; }
    }
    final choice = await showModalBottomSheet<int>(context: context, builder: (sheet) =>
      SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final target in [base, ...[1, 2, 3, 0].where((target) => target != base && legal(target))])
          ListTile(title: Text(target == base ? 'Permanecer en la base' :
            target == 0 ? 'Anotar carrera' : target > base ? 'Avanzar a ${target}B' : 'Regresar a ${target}B'),
            onTap: () => Navigator.pop(sheet, target)),
        ListTile(title: const Text('Registrar out del corredor'), onTap: () => Navigator.pop(sheet, -1)),
        ListTile(title: const Text('Sustituir corredor'), onTap: () => Navigator.pop(sheet, -2)),
      ])));
    if (!mounted || choice == null || choice == base || _currentLiveSnapshot?.version != game.version) return;
    if (choice == -2) {
      await _chooseRunnerReplacement(game, base);
      return;
    }
    if (choice == -1) {
      final outAt = await showModalBottomSheet<int>(context: context,
        builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('¿Dónde fue retirado el corredor?')),
          for (final target in [base, ...[1, 2, 3].where((b) => b > base), 0])
            ListTile(
              title: Text(target == 0 ? 'Out en home' : 'Out en ${target}B'),
              onTap: () => Navigator.pop(sheet, target),
            ),
        ])));
      if (!mounted || outAt == null || _currentLiveSnapshot?.version != game.version) return;
      await _sendSpecial('RUNNER_OUT', {'source': base, 'destination': outAt});
      return;
    }
    await _sendSpecial('RUNNER_MOVE', {'source': base, 'destination': choice});
  }

  Future<void> _chooseRunnerReplacement(SwlLiveScoreboardSnapshot game, int base) async {
    try {
      final roster = await SwlRosterRepository(Supabase.instance.client)
          .activePlayers(game.battingTeamId).timeout(const Duration(seconds: 8));
      if (!mounted || _currentLiveSnapshot?.version != game.version) return;
      final battingIds = (game.isTop ? visitorLineup : homeLineup).map((p) => p.playerId).toSet();
      final replacement = await showModalBottomSheet<String>(context: context, builder: (sheet) =>
        SafeArea(child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Elegir corredor emergente del roster')),
          for (final player in roster)
            if (!battingIds.contains(player.playerId))
              ListTile(title: Text(player.name), onTap: () => Navigator.pop(sheet, player.playerId)),
        ])));
      if (!mounted || replacement == null || _currentLiveSnapshot?.version != game.version) return;
      await _sendSpecial('RUNNER_REPLACE', {'source': base, 'player_id': replacement});
    } catch (_) {
      if (mounted) setState(() => _liveActionError = 'No se pudo consultar el roster.');
    }
  }

  Future<void> _chooseGhost(SwlLiveScoreboardSnapshot game) async {
    try {
      final roster = await SwlRosterRepository(Supabase.instance.client)
          .activePlayers(game.battingTeamId).timeout(const Duration(seconds: 8));
      if (!mounted || _currentLiveSnapshot?.version != game.version) return;
      final confirmedBatters = (game.isTop ? visitorLineup : homeLineup)
          .map((player) => player.playerId).whereType<String>().toSet();
      final eligible = roster.where((player) =>
          game.rosterGhostAllowed || confirmedBatters.contains(player.playerId));
      final player = await showModalBottomSheet<String>(context: context, builder: (sheet) =>
        SafeArea(child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Colocar corredor fantasma en segunda')),
          ListTile(title: const Text('Último out'), onTap: () => Navigator.pop(sheet, 'LAST_OUT')),
          for (final player in eligible)
            ListTile(title: Text(player.name), onTap: () => Navigator.pop(sheet, player.playerId)),
        ])));
      if (!mounted || player == null || _currentLiveSnapshot?.version != game.version) return;
      await _sendSpecial('GHOST_RUNNER', {'player_id': player});
    } catch (_) {
      if (mounted) setState(() => _liveActionError = 'No se pudo consultar el roster para el corredor fantasma.');
    }
  }

  Future<void> _liveOutMenu() async {
    final game = _currentLiveSnapshot;
    if (game == null || _liveActionInFlight) return;
    if (game.outs >= 2 || !(game.firstOccupied || game.secondOccupied || game.thirdOccupied)) {
      await _submitLiveAction('OUT');
      return;
    }
    final result = await showModalBottomSheet<int>(context: context, builder: (sheet) =>
      SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: const Text('Out normal'), onTap: () => Navigator.pop(sheet, 0)),
        if (game.thirdOccupied)
          ListTile(title: const Text('Fly de sacrificio · anota tercera'),
            onTap: () => Navigator.pop(sheet, 4)),
        for (final base in [1, 2, 3])
          if (swlBaseOccupied(game.playState, base))
            ListTile(title: Text('Doble play · bateador y corredor de ${base}B'),
              onTap: () => Navigator.pop(sheet, base)),
      ])));
    if (!mounted || result == null || _currentLiveSnapshot?.version != game.version) return;
    if (result == 0) {
      await _submitLiveAction('OUT');
    } else if (result == 4) {
      await _chooseSacrifice(game);
    } else {
      await _sendSpecial('DOUBLE_PLAY', {'source': result});
    }
  }

  Future<void> _chooseSacrifice(SwlLiveScoreboardSnapshot game) async {
    // El servidor exige corredor identificado en tercera y menos de dos outs.
    // Evitar abrir un formulario que no puede registrar una jugada válida.
    if (!game.thirdOccupied || game.outs >= 2) {
      if (mounted) setState(() => _liveActionError =
          'El fly de sacrificio requiere corredor en tercera y menos de dos outs.');
      return;
    }
    final moves = <String, dynamic>{'third_to': 0,
      if (game.firstOccupied) 'first_to': 1, if (game.secondOccupied) 'second_to': 2};
    final selected = await showDialog<bool>(context: context, builder: (dialog) =>
      StatefulBuilder(builder: (_, update) {
        Widget advance(String label, String key, List<int> options) => DropdownButtonFormField<int>(
          initialValue: moves[key] as int, decoration: InputDecoration(labelText: label),
          items: [for (final value in options) DropdownMenuItem(value: value,
            child: Text(value == 0 ? 'Anota' : '${value}B'))],
          onChanged: (value) => update(() => moves[key] = value),
        );
        return AlertDialog(title: const Text('Fly de sacrificio'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Elevado capturado · anota el corredor de tercera.'),
            if (game.firstOccupied) advance('Desde primera', 'first_to', [1, 2, 3, 0]),
            if (game.secondOccupied) advance('Desde segunda', 'second_to', [2, 3, 0]),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Registrar'))]);
      }));
    if (!mounted || selected != true || _currentLiveSnapshot?.version != game.version) return;
    // Validate the complete advancement before invoking the remote transaction.
    // This prevents a selected runner from overtaking another or sharing a base.
    try {
      swlPreviewSpecial(game.playState, 'SACRIFICE_FLY',
        firstTo: moves['first_to'] as int?,
        secondTo: moves['second_to'] as int?,
        thirdTo: moves['third_to'] as int?,
        regulationInnings: game.regulationInnings);
    } on StateError catch (error) {
      if (mounted) setState(() => _liveActionError = error.message);
      return;
    }
    await _sendSpecial('SACRIFICE_FLY', moves);
  }

  Widget _buildDiamond() {
    return SizedBox(
      width: 75, height: 65,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(
          top: 0,
          child: _baseNode(on2B, () {
            if (widget.liveSnapshot != null) { _liveBaseMenu(2); return; }
            if (on2B) _openRunnerActionModal(2);
            else { _saveState(); setState(() => on2B = true); }
          }),
        ),
        Positioned(
          left: 4,
          top: 20,
          child: _baseNode(on3B, () {
            if (widget.liveSnapshot != null) { _liveBaseMenu(3); return; }
            if (on3B) _openRunnerActionModal(3);
            else { _saveState(); setState(() => on3B = true); }
          }),
        ),
        Positioned(
          right: 4,
          top: 20,
          child: _baseNode(on1B, () {
            if (widget.liveSnapshot != null) { _liveBaseMenu(1); return; }
            if (on1B) _openRunnerActionModal(1);
            else { _saveState(); setState(() => on1B = true); }
          }),
        ),
        const Positioned(bottom: 2, child: Icon(Icons.home, color: Colors.white38, size: 18)),
      ]),
    );
  }

  Widget _baseNode(bool occupied, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: pi / 4,
        child: Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: occupied ? Colors.amber : const Color(0xFF0B1118),
            borderRadius: BorderRadius.circular(2.5),
            border: Border.all(color: occupied ? Colors.white : Colors.white54, width: 1.5),
          ),
        ),
      ),
    );
  }

  // Selector de batazo dentro de la pizarra oficial, nunca en la pantalla PIN.
  Future<Map<String, dynamic>?> _chooseLiveHit({required bool defensiveError}) async {
    final live = _currentLiveSnapshot;
    if (live == null) return null;
    final client = Supabase.instance.client;
    final game = await client.from('swl_live_games').select()
        .eq('id', live.gameId).single().timeout(const Duration(seconds: 12));
    if ((game['version'] as num?)?.toInt() != live.version) {
      throw StateError('La jugada cambió; actualiza el marcador');
    }
    final uid = client.auth.currentUser?.id;
    final top = game['is_top'] == true;
    final manager = top ? game['away_manager_id'] : game['home_manager_id'];
    if (uid == null || manager?.toString() != uid ||
        game['status'] != 'IN_PROGRESS') {
      throw StateError('El partido no está en curso o no corresponde tu turno');
    }
    final rawTeamId = top ? game['away_team_id'] : game['home_team_id'];
    final teamId = rawTeamId?.toString();
    if (teamId == null || teamId.isEmpty) {
      throw StateError('Equipo al bate no identificado');
    }
    final lineupRow = await client.from('swl_game_lineups').select('lineup')
        .eq('game_id', live.gameId).eq('team_id', teamId).maybeSingle().timeout(const Duration(seconds: 12));
    final lineup = swlConfirmedBattingSlots(lineupRow?['lineup']);
    if (lineup.length < 9) {
      throw StateError('Alineación no disponible');
    }
    final turn = await client.from('swl_game_batting_turns')
        .select('next_order').eq('game_id', live.gameId)
        .eq('team_id', teamId).maybeSingle().timeout(const Duration(seconds: 12));
    final order = (turn?['next_order'] as num?)?.toInt() ?? 1;
    if (order < 1 || order > lineup.length) {
      throw StateError('Turno al bate inválido');
    }
    final batterId = lineup[order - 1]['player_id']?.toString();
    if (batterId == null || batterId.isEmpty) {
      throw StateError('Bateador no disponible');
    }
    // Mostrar la identidad del bateador del turno real, no un jugador demo.
    final batterRow = await client.from('players')
        .select('first_name,last_name,jersey_number,universal_id')
        .eq('id', batterId).maybeSingle().timeout(const Duration(seconds: 12));
    if (batterRow == null) {
      throw StateError('No se encontró el pelotero del turno actual');
    }
    final batterName = [batterRow['first_name'], batterRow['last_name']]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .map((part) => part.toString().trim()).join(' ');
    final batterJersey = batterRow['jersey_number']?.toString() ?? '—';
    final batterCode = batterRow['universal_id']?.toString() ?? '—';
    final bases = Map<String, dynamic>.from(game['bases_state'] as Map? ?? {});
    final first = bases['first'] == true;
    final second = bases['second'] == true;
    final third = bases['third'] == true;
    int batterBase = 1;
    bool countRunsOnThirdOut = false;
    int? lastOutSource;

    // Avance sugerido según el tipo de batazo; editable por el mánager.
    // El valor 0 indica que el corredor anotó.
    int destination(int initialBase, int hitBases) {
      final next = initialBase + hitBases;
      return next >= 4 ? 0 : next;
    }
    int? firstTo = first ? destination(1, batterBase) : null;
    int? secondTo = second ? destination(2, batterBase) : null;
    int? thirdTo = third ? destination(3, batterBase) : null;
    if (!mounted) return null;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          Widget choice(String title, int value, List<int> options,
              void Function(int) change, {bool batter = false}) => DropdownButtonFormField<int>(
            key: ValueKey((title, value)),
            initialValue: value,
            decoration: InputDecoration(labelText: title),
            items: [for (final n in options) DropdownMenuItem(
              value: n, child: Text(batter
                  ? (defensiveError ? '${n}B por error' : const ['Hit', 'Doble', 'Triple', 'Jonrón'][n - 1])
                  : n == 0 ? 'Anota carrera' : n == -4 ? 'Out en home'
                  : n < 0 ? 'Out en ${-n}B' : '${n}B'))],
            onChanged: (n) {
              if (n != null) update(() {
                countRunsOnThirdOut = false;
                change(n);
              });
            },
          );
          final destinations = [firstTo, secondTo, thirdTo];
          final outCount = destinations.whereType<int>().where((d) => d < 0).length;
          final retired = destinations.indexWhere((d) => d != null && d < 0);
          final outSources = <int>[
            for (var i = 0; i < destinations.length; i++)
              if (destinations[i] != null && destinations[i]! < 0) i + 1,
          ];
          if (outCount > 1 && !outSources.contains(lastOutSource)) {
            lastOutSource = null;
          }

          final forced = firstTo == -2 || (first && secondTo == -3) ||
              (first && second && thirdTo == -4);
          final timePlay = live.outs + outCount == 3 && outCount == 1 && !forced &&
              destinations.skip(retired + 1).contains(0);
          int? runs;
          try {
            final preview = live.playState.hit(
              batterBase: batterBase, firstTo: firstTo,
              secondTo: secondTo, thirdTo: thirdTo,
              countRunsOnThirdOut: timePlay && countRunsOnThirdOut,
            );
            runs = live.isTop ? preview.awayRuns - live.awayRuns :
                preview.homeRuns - live.homeRuns;
          } on StateError {
            // El motor local de vista previa puede rechazar destinos negativos
            // aunque LAB admita un único corredor retirado durante un hit.
            // Solo habilitar ese caso si la ocupación y el orden son coherentes.
            if (!defensiveError && outCount == 1 && live.outs < 2 &&
                batterBase >= 1 && batterBase <= 3) {
              final origins = <int>[if (first) 1, if (second) 2, if (third) 3];
              final moves = <int?>[firstTo, secondTo, thirdTo];
              final occupiedTargets = <int>{batterBase};
              var lastTarget = batterBase;
              var valid = true;
              var candidateRuns = 0;
              for (final origin in origins) {
                final dest = moves[origin - 1];
                if (dest == null) { valid = false; break; }
                final allowed = switch (origin) {
                  1 => const [0, 2, 3, -2, -3, -4],
                  2 => const [0, 3, -3, -4],
                  _ => const [0, -4],
                };
                if (!allowed.contains(dest)) { valid = false; break; }
                if (dest < 0) continue;
                final target = dest == 0 ? 4 : dest;
                if (target < lastTarget || (target == lastTarget && target != 4)) {
                  valid = false; break;
                }
                lastTarget = target;
                if (dest == 0) {
                  candidateRuns++;
                } else if (!occupiedTargets.add(dest)) {
                  valid = false; break;
                }
              }
              if (valid) runs = candidateRuns;
            }
          }
          return AlertDialog(
            title: Text(defensiveError ? 'Error defensivo' : 'Batazo'),
            content: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                Text('Turno $order · $batterName  #$batterJersey\n$batterCode'),
                choice('Batazo del bateador', batterBase, [1, 2, 3, if (!defensiveError) 4], (n) {
                  batterBase = n;
                  if (first) firstTo = destination(1, n);
                  if (second) secondTo = destination(2, n);
                  if (third) thirdTo = destination(3, n);
                }, batter: true),
                if (first && batterBase != 4) choice('Corredor en primera', firstTo!, [2, 3, 0, -2, -3, -4],
                    (n) => firstTo = n),
                if (second && batterBase != 4) choice('Corredor en segunda', secondTo!, [2, 3, 0, -3, -4],
                    (n) => secondTo = n),
                if (third && batterBase != 4) choice('Corredor en tercera', thirdTo!, [3, 0, -4],
                    (n) => thirdTo = n),
                if (outCount > 1)
                  DropdownButtonFormField<int>(
                    key: ValueKey('last-out-$lastOutSource-${outSources.join("-")}'),
                    initialValue: lastOutSource,
                    decoration: const InputDecoration(
                      labelText: '¿Cuál corredor fue el último out?',
                    ),
                    items: [
                      for (final source in outSources)
                        DropdownMenuItem<int>(
                          value: source,
                          child: Text('Corredor de ${source == 1 ? "primera" : source == 2 ? "segunda" : "tercera"}'),
                        ),
                    ],
                    onChanged: (source) => update(() => lastOutSource = source),
                  ),
                if (timePlay)
                  CheckboxListTile(
                    title: const Text('Las carreras seleccionadas cruzaron antes del tercer out y este no fue forzado'),
                    value: countRunsOnThirdOut,
                    onChanged: (value) => update(() => countRunsOnThirdOut = value == true),
                  ),
                if (outCount > 0 && (outCount != 1 || live.outs >= 2))
                  const Text(
                    'Los outs múltiples y el tercer out con corredores todavía '
                    'no están habilitados. Esta jugada no se enviará.',
                    style: TextStyle(color: Colors.amber, fontSize: 12)),
                if (defensiveError)
                  const Text('El error defensivo todavía no está habilitado en el servidor.',
                    style: TextStyle(color: Colors.amber, fontSize: 12)),
                if (runs != null) Text('Carreras de la jugada: $runs'),
                if (runs == null) const Text('Revisa el orden y los destinos de los corredores',
                    style: TextStyle(color: Colors.redAccent)),
              ],
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCELAR')),
              FilledButton(onPressed: defensiveError || runs == null ||
                  (outCount > 1 && lastOutSource == null) ||
                  (outCount > 0 && (outCount != 1 || live.outs >= 2)) ? null : () =>
                  Navigator.pop(dialogContext, {
                    'p_batter_id': batterId,
                    'p_batter_base': batterBase,
                    'p_first_to': firstTo,
                    'p_second_to': secondTo,
                    'p_third_to': thirdTo,
                    if (outCount > 0) 'count_runs_on_third_out': timePlay && countRunsOnThirdOut,
                    if (outCount > 1) 'p_last_out_source': lastOutSource,
                  }), child: const Text('CONFIRMAR BATAZO')),
            ],
          );
        },
      ),
    );
  }

  // Reversión segura: solo el último OUT simple y con confirmación.
  // El servidor valida la versión, los permisos y el turno antes de modificar datos.
  Future<void> _undoLastLiveOut() async {
    final snapshot = _currentLiveSnapshot;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (_liveActionInFlight || snapshot == null || !snapshot.canScore(uid)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Deshacer último out'),
        content: const Text(
          'Solo se puede revertir el último OUT sencillo. '
          'Se restaurarán el turno al bate y las estadísticas del lanzador. '
          'La corrección quedará registrada en el historial.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('CANCELAR')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('DESHACER OUT')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_currentLiveSnapshot?.version != snapshot.version) {
      setState(() => _liveActionError =
          'El marcador cambió. Actualiza antes de deshacer.');
      return;
    }
    setState(() { _liveActionInFlight = true; _liveActionError = null; });
    try {
      await Supabase.instance.client.rpc('swl_v57_undo_last_out', params: {
        'p_game_id': snapshot.gameId,
        'p_expected_version': snapshot.version,
      });
      await _refreshLiveScore();
      await _refreshLiveHistory();
    } catch (error) {
      if (mounted) setState(() => _liveActionError =
          'No se pudo deshacer el último out: $error');
    } finally {
      if (mounted) setState(() => _liveActionInFlight = false);
    }
  }

  Future<void> _submitLiveAction(String action) async {
    final snapshot = _currentLiveSnapshot;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (_liveActionInFlight || widget.onLiveAction == null ||
        snapshot?.canScore(userId) != true) return;
    setState(() { _liveActionInFlight = true; _liveActionError = null; });
    try {
      final battedBall = action == 'HIT' || action == 'ERROR';
      final hitParams = battedBall ? await _chooseLiveHit(defensiveError: action == 'ERROR') : null;
      if (battedBall && hitParams == null) return;
      await widget.onLiveAction!(snapshot!.version,
        action == 'HIT' ? 'HIT_WITH_OUT' : action, hitParams);
      // La RPC ya terminó correctamente. Un fallo posterior al actualizar
      // la vista no significa que la jugada haya sido rechazada.
      try {
        await _refreshLiveScore();
        await _refreshLiveHistory();
        // No afirmar que el marcador está al día si la lectura no avanzó
        // hasta la versión que la RPC acaba de confirmar.
        if (mounted && _currentLiveSnapshot?.gameId == snapshot.gameId &&
            (_currentLiveSnapshot?.version ?? -1) <= snapshot.version) {
          setState(() => _liveActionError =
              'Jugada enviada, pero el marcador aún no confirma la actualización. Revisa el historial antes de continuar.');
        }
        // El lector de historial gestiona internamente sus errores; comprobar
        // su estado para no anunciar una actualización completa si falló.
        if (mounted && _historyReadError != null) {
          setState(() => _liveActionError =
              'Jugada enviada, pero no se pudo actualizar el historial. Revisa la pizarra antes de continuar.');
        }
      } catch (_) {
        if (mounted) setState(() => _liveActionError =
            'Jugada enviada. No se pudo actualizar la pizarra; revisa el historial antes de continuar.');
      }
    } catch (error) {
      if (mounted) setState(() => _liveActionError =
          'No se pudo registrar la jugada: $error');
    } finally {
      if (mounted) setState(() => _liveActionInFlight = false);
    }
  }

  void _showLivePlayerStats(String name, String stats) {
    showDialog<void>(context: context, builder: (dialog) => AlertDialog(
      title: Text(name),
      content: Text('Este partido\n$stats\n\nTemporada: acumulados pendientes de una fuente confirmada.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cerrar'))],
    ));
  }

  Future<void> _sendMatchDecision(SwlLiveScoreboardSnapshot game, String action) async {
    if (_liveActionInFlight || widget.onMatchDecision == null) return;
    setState(() { _liveActionInFlight = true; _liveActionError = null; });
    try {
      await widget.onMatchDecision!(game.version, action);
      await _refreshLiveScore();
    } catch (error) {
      if (mounted) setState(() => _liveActionError = error.toString());
    } finally {
      if (mounted) setState(() => _liveActionInFlight = false);
    }
  }

  List<Widget> _matchDecisionButtons(SwlLiveScoreboardSnapshot game, String? userId) {
    if (widget.onMatchDecision == null || userId == null ||
        (userId != game.homeManagerId && userId != game.awayManagerId)) return [];
    final actions = game.matchActions(userId);
    Widget decision(String text, String action) => TextButton(
      onPressed: _liveActionInFlight || !actions.contains(action) ? null : () => _sendMatchDecision(game, action),
      child: Text(text),
    );
    if (game.status == 'IN_PROGRESS') {
      final requestedBy = game.finishRequestedBy;
      if (requestedBy == userId) return [const Text('Cierre solicitado · esperando al otro mánager')];
      if (actions.contains('ACCEPT')) return [
        const Text('El otro mánager solicita terminar el partido.'),
        Wrap(children: [decision('Aceptar cierre', 'ACCEPT'), decision('Rechazar cierre', 'REJECT')]),
      ];
      if (actions.contains('REQUEST')) {
        return [decision('Terminar partido', 'REQUEST')];
      }
    }
    if (game.status == 'FINAL') {
      final signed = userId == game.homeManagerId ? game.homeSigned : game.awaySigned;
      return [Text(game.finishReason ?? 'Partido finalizado'),
        if (signed) const Text('Firma registrada · esperando la otra firma')
        else decision('Firmar resultado', 'SIGN')];
    }
    if (game.status == 'OFFICIAL') return [const Text('Resultado oficial · dos firmas')];
    return [];
  }

  Widget _buildLiveMainButtons() {
    final snapshot = _currentLiveSnapshot;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final block = snapshot?.scoringBlock(userId, authorized: widget.onLiveAction != null);
    final allowed = snapshot != null && block == null && !_liveActionInFlight;
    Widget liveButton(String label, String action, Color color) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color,
            disabledBackgroundColor: const Color(0xFF26313C),
            padding: const EdgeInsets.symmetric(vertical: 15)),
          onPressed: allowed ? () => _submitLiveAction(action) : null,
          onLongPress: allowed && action == 'STRIKE' ? () => _submitLiveAction('FOUL') : null,
          child: Text(label, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w900, color: Colors.white)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (block != null)
          Text(block,
            style: const TextStyle(color: Colors.amber, fontSize: 11)),
        if (_liveActionError != null)
          Text(_liveActionError!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
        Row(children: [
          liveButton('BOLA', 'BALL', const Color(0xFF10B981)),
          liveButton('STRIKE', 'STRIKE', const Color(0xFFEF4444)),
          liveButton('OUT', 'OUT', const Color(0xFFF59E0B)),
          liveButton('BATAZO / HIT', 'HIT', const Color(0xFF8B5CF6)),
        ]),
        if (allowed && snapshot.outs < 2 &&
            (snapshot.firstOccupied || snapshot.secondOccupied || snapshot.thirdOccupied))
          TextButton(onPressed: _liveOutMenu, child: const Text('Outs y jugadas especiales')),
        if (allowed)
          const Text('Error defensivo: pendiente de habilitar en LAB', style: TextStyle(color: Colors.amber, fontSize: 11)),
        if (allowed)
          TextButton(onPressed: _undoLastLiveOut, child: const Text('Deshacer último OUT')),
        if (snapshot != null) ..._matchDecisionButtons(snapshot, userId),
      ]),
    );
  }

  Widget _buildMainButtons() {
    if (widget.liveSnapshot != null) return _buildLiveMainButtons();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: _actionBtn("BOLA", const Color(0xFF10B981), () {
              _saveState();
              setState(() {
                if (balls < 3) {
                  balls++;
                } else {
                  _recordWalk();
                }
              });
            })),
            const SizedBox(width: 6),
            Expanded(child: _actionBtn("STRIKE", const Color(0xFFEF4444), () {
              _saveState();
              setState(() {
                if (strikes < 2) {
                  strikes++;
                } else {
                  _recordOutWithDetails("K", "Ponche (Tirándole)", isStrikeout: true);
                }
              });
            })),
            const SizedBox(width: 6),
            Expanded(
              child: _actionBtn("BATAZO / JUGADA", const Color(0xFFF59E0B), _openBatazoSelector),
            ),
          ]),

          const SizedBox(height: 8),

          Row(children: [
            Expanded(child: _hitBtn("H", "Sencillo", () => recordHit("H", "Sencillo (Hit)"))),
            const SizedBox(width: 6),
            Expanded(child: _hitBtn("H2", "Doble", () => recordHit("H2", "Doble"))),
            const SizedBox(width: 6),
            Expanded(child: _hitBtn("H3", "Triple", () => recordHit("H3", "Triple"))),
            const SizedBox(width: 6),
            Expanded(child: _hitBtn("HR", "Jonrón", () => recordHit("HR", "Jonrón"), isHr: true)),
          ]),
        ],
      ),
    );
  }

  Widget _actionBtn(String title, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
    );
  }

  Widget _hitBtn(String title, String subtitle, VoidCallback onTap, {bool isHr = false}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isHr ? const Color(0xFF8B5CF6) : const Color(0xFF223040),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
          Text(subtitle, style: const TextStyle(fontSize: 9, color: Colors.white60)),
        ],
      ),
    );
  }
}