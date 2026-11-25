import 'swl_official_box_score.dart';
import 'swl_lineup_draft.dart';
import 'swl_lineup_editor.dart';
import 'swl_history_events.dart';
import 'swl_lineup_identity.dart';
import 'swl_pitching_stats.dart';
import 'swl_team_lookup.dart';
import 'swl_advanced_scoreboard.dart';
import 'swl_live_scoreboard_snapshot.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'swl_code_input.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'swl_roster_repository.dart';
import 'swl_substitution_rules.dart';

/// V5.2: emparejamiento real, consulta del partido y reconexión.
/// Anotación básica LAB disponible; reglas avanzadas pendientes.
class SwlLiveLobby extends StatefulWidget {
  final List<Map<String, dynamic>> authorizedTeams;
  final String? initialJoinPin;
  final bool readOnly;
  final String? initialOpponent;
  final String? initialOpponentId;
  final String? openGameId;
  final String? preferredHomeId;
  const SwlLiveLobby({
    super.key,
    required this.authorizedTeams,
    this.initialJoinPin,
    this.readOnly = false,
    this.initialOpponent,
    this.initialOpponentId,
    this.openGameId,
    this.preferredHomeId,
  });

  @override
  State<SwlLiveLobby> createState() => _SwlLiveLobbyState();
}

class _SwlLiveLobbyState extends State<SwlLiveLobby> {
  final _client = Supabase.instance.client;
  final _pin = TextEditingController();
  final _teamSearch = TextEditingController();
  bool _teamSearchByCode = false;
  List<Map<String, dynamic>> _matches = [];
  String? _homeId;
  Map<String, dynamic>? _away;
  final Map<String, String> _teamNames = {};
  final Map<String, String> _teamLogos = {};
  Map<String, dynamic>? _game;
  final _scoreboard = ValueNotifier<SwlLiveScoreboardSnapshot?>(null);
  List<Map<String, dynamic>> _savedLineups = [];
  Map<String, String> _lineupPlayerNames = {};
  bool _lineupsLoading = false;
  String? _lineupsError;
  int _lineupsGeneration = 0;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  Timer? _searchTimer;
  int _searchGeneration = 0;
  bool _busy = false;
  bool _startingGame = false;
  bool _recording = false;
  bool _substitutionPending = false;
  int? _uncertainSubstitutionVersion;
  bool _confirmingPlay = false;
  bool _uncertainPlay = false;
  int _recordGeneration = 0;
  String? _scoringMessage;
  bool _searching = false;
  Completer<void>? _gameRefresh;
  int _watchGeneration = 0;
  String? _connectionWarning;
  List<Map<String, dynamic>> _recentEvents = [];
  List<Map<String, dynamic>> _substitutionHistory = [];
  bool _substitutionHistoryLoading = false;
  bool _substitutionHistoryQueued = false;
  bool _substitutionHistoryTruncated = false;
  String? _substitutionHistoryError;
  int _substitutionHistoryGeneration = 0;
  List<Map<String, dynamic>> _battingStats = [];
  bool _battingStatsLoading = false;
  bool _battingStatsQueued = false;
  int _battingStatsGeneration = 0;
  String? _battingStatsError;
  bool _eventsLoading = false;
  bool _eventsRefreshQueued = false;
  int _historyPollTicks = 0;
  bool _eventsQueried = false;
  String? _eventsRequestGameId;
  int _eventsRequestGeneration = 0;
  String? _eventsError;
  String? _error;
  // V5.5: acceso guiado. El PIN identifica el partido; la sesión autoriza el equipo.
  bool _teamConfirmed = false;

  @override
  void initState() {
    super.initState();
    final primaryTeam = widget.preferredHomeId;
    _homeId = widget.authorizedTeams.any((team) => team['id']?.toString() == primaryTeam)
        ? primaryTeam
        : widget.authorizedTeams.firstOrNull?['id']?.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pin = widget.initialJoinPin;
      final opponent = widget.initialOpponent;
      final gameId = widget.openGameId;
      if (gameId != null) {
        _openSavedGame(gameId);
      } else if (pin != null) {
        _joinFromPin(pin);
      } else if (opponent != null) {
        _teamSearch.text = opponent;
        final opponentId = widget.initialOpponentId;
        if (opponentId == null) {
          _searchTeams(opponent);
        } else {
          _selectScheduledOpponent(opponentId);
        }
      }
    });
  }

  Future<void> _openSavedGame(String id) async {
    await _run(() => _client.from('swl_live_games').select().eq('id', id).single());
    if (mounted && _game?['id']?.toString() == id) {
      final game = _game!;
      if ((game['status'] == 'SCHEDULED' || game['status'] == 'IN_PROGRESS') &&
          _myTeamId(game) != null) {
        setState(() => _teamConfirmed = true);
        await _loadSavedLineups();
      } else {
        _openOriginalScoreboardPreview(exitLobbyOnReturn: true);
      }
    }
  }

  Future<void> _selectScheduledOpponent(String id) async {
    final term = _teamSearch.text;
    try {
      final team = await _client.from('teams').select('id,name,province')
          .eq('id', id).single().timeout(const Duration(seconds: 12));
      if (!mounted || _teamSearch.text != term) return;
      setState(() {
        _away = team;
        _teamSearch.text = team['name']?.toString() ?? term;
      });
    } catch (_) {
      if (mounted && _teamSearch.text == term) {
        setState(() => _error = 'El rival seleccionado ya no está disponible. Busca el equipo nuevamente.');
      }
    }
  }

  Future<void> _joinFromPin(String supplied) async {
    final digits = swlCodeSuffix(supplied);
    if (!RegExp(r'^\d{6}$').hasMatch(digits)) {
      setState(() => _error = 'El PIN real debe contener 6 números (SWL-XXXXXX).');
      return;
    }
    _pin.text = digits;
    final pin = swlCode(digits);
    await _run(() async {
      // El PIN identifica un único partido. No aceptar una respuesta RPC
      // perteneciente a otro encuentro ni ejecutar una segunda unión.
      final game = await _client.from('swl_live_games')
          .select().eq('game_pin', pin).maybeSingle()
          .timeout(const Duration(seconds: 12));
      final userId = _client.auth.currentUser?.id;
      final authorizedIds = widget.authorizedTeams
          .map((team) => team['id']?.toString())
          .whereType<String>().toSet();
      final awayId = game?['away_team_id']?.toString();
      final homeManager = game?['home_manager_id']?.toString();
      final awayManager = game?['away_manager_id']?.toString();
      final status = game?['status']?.toString().toUpperCase();
      final eligibleAway = game != null && awayId != null &&
          authorizedIds.contains(awayId) && homeManager != userId &&
          (awayManager == null || awayManager.isEmpty) &&
          status != 'FINAL' && status != 'OFFICIAL';
      final mayAttemptJoin = !widget.readOnly && userId != null &&
          authorizedIds.isNotEmpty && (game == null || eligibleAway);
      final dynamic result = mayAttemptJoin
          ? await _client.rpc('swl_v5_join_game', params: {'p_game_pin': pin})
          : game;
      if (result == null) {
        throw StateError('Partido no disponible para este PIN.');
      }
      if (result is! Map) {
        throw StateError('El servidor devolvió un formato de partido inesperado.');
      }
      final linked = Map<String, dynamic>.from(result);
      if (linked['game_pin']?.toString().trim().toUpperCase() != pin) {
        throw StateError('La respuesta no corresponde al PIN solicitado.');
      }
      return linked;
    });
  }

  Future<void> _searchTeams(String term) async {
    _searchTimer?.cancel();
    final searchGeneration = ++_searchGeneration;
    if (term.trim().length < 2) {
      if (mounted) setState(() { _matches = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final teams = await swlSearchTeams(_client, term, excludeId: _homeId);
        if (!mounted || searchGeneration != _searchGeneration ||
            _teamSearch.text.trim() != term.trim()) return;
        setState(() {
          _matches = teams.take(20).toList();
          _searching = false;
        });
      } catch (e) {
        if (mounted && searchGeneration == _searchGeneration) {
          setState(() { _searching = false; _error = 'Error buscando equipos: $e'; });
        }
      }
    });
  }

  Future<void> _run(Future<dynamic> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await action().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final game = Map<String, dynamic>.from(result as Map);
      setState(() {
        _game = game;
        _teamConfirmed = false;
        _savedLineups = [];
        _lineupPlayerNames = {};
        _lineupsError = null;
        _lineupsGeneration++;
        _connectionWarning = null;
        _recentEvents = [];
        _substitutionHistory = [];
        _substitutionHistoryGeneration++;
        _substitutionHistoryLoading = false;
        _substitutionHistoryQueued = false;
        _substitutionHistoryTruncated = false;
        _substitutionHistoryError = null;
        _eventsError = null;
        _eventsQueried = false;
        _eventsRequestGameId = null;
        _eventsRequestGeneration++;
        _recordGeneration++;
        _recording = false;
        _scoringMessage = null;
      });
      _scoreboard.value = SwlLiveScoreboardSnapshot.fromGame(game);
      _subscribe(game['id'].toString());
      await _refreshGame(afterCurrent: true);
      if (_myTeamId(game) != null) await _loadSavedLineups();
      await _loadNames();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo completar la operación: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshGame({bool afterCurrent = false}) async {
    final id = _game?['id']?.toString();
    if (id == null || !mounted) return;
    final generation = _watchGeneration;
    final current = _gameRefresh;
    if (current != null) {
      await current.future;
      if (afterCurrent && mounted && generation == _watchGeneration) {
        await _refreshGame();
      }
      return;
    }
    final refresh = _gameRefresh = Completer<void>();
    try {
      final row = await _client.from('swl_live_games').select().eq('id', id).single()
          .timeout(const Duration(seconds: 12));
      if (mounted && generation == _watchGeneration && _game?['id']?.toString() == id) {
        final incoming = Map<String, dynamic>.from(row);
        final currentVersion = (_game?['version'] as num?)?.toInt() ?? -1;
        final incomingVersion = (incoming['version'] as num?)?.toInt() ?? -1;
        if (incomingVersion < currentVersion) return;
        final changed = jsonEncode(incoming) != jsonEncode(_game);
        if (changed || _connectionWarning != null) {
          setState(() {
            _game = incoming;
            _connectionWarning = null;
          });
        }
        if (changed) {
          _scoreboard.value = SwlLiveScoreboardSnapshot.fromGame(incoming);
        }
      }
    } catch (_) {
      // Conservar el partido y el PIN; no ocultar el fallo de sincronización.
      if (mounted && generation == _watchGeneration && _game?['id']?.toString() == id) {
        if (_connectionWarning == null) {
          setState(() => _connectionWarning =
              'No se pudo actualizar el partido. Comprueba la conexión.');
        }
      }
    } finally {
      if (identical(_gameRefresh, refresh)) _gameRefresh = null;
      refresh.complete();
    }
  }

  /// Lee la alineación confirmada en LAB. No usa borradores locales.
  Future<void> _loadSavedLineups({bool announce = false}) async {
    final gameId = _game?['id']?.toString();
    if (gameId == null || !mounted) return;
    final generation = ++_lineupsGeneration;
    _lineupsLoading = true;
    try {
      final rows = await _client.from('swl_game_lineups')
          .select()
          .eq('game_id', gameId)
          .timeout(const Duration(seconds: 12));
      final saved = List<Map<String, dynamic>>.from(rows)
        ..sort((a, b) => a['team_id'].toString().compareTo(b['team_id'].toString()));
      final ids = <String>{};
      for (final row in saved) {
        if (row['pitcher_id'] != null) ids.add(row['pitcher_id'].toString());
        final lineup = row['lineup'];
        if (lineup is! List) continue;
        for (final slot in lineup) {
          if (slot is Map && slot['player_id'] != null) {
            ids.add(slot['player_id'].toString());
          }
        }
      }
      Map<String, String> names = {};
      try {
        names = await _lookupPlayerNames(ids);
      } catch (_) {
        // El acceso a perfiles no invalida el orden confirmado del partido.
      }
      if (!mounted || generation != _lineupsGeneration ||
          _game?['id']?.toString() != gameId) return;
      if (_lineupsError != null || jsonEncode(saved) != jsonEncode(_savedLineups) ||
          names.entries.any((entry) => _lineupPlayerNames[entry.key] != entry.value)) {
        setState(() {
          _savedLineups = saved;
          _lineupsError = null;
          _lineupPlayerNames = {..._lineupPlayerNames, ...names};
        });
      }
      if (announce) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alineaciones confirmadas actualizadas.')),
      );
    } catch (_) {
      if (!mounted || generation != _lineupsGeneration ||
          _game?['id']?.toString() != gameId) return;
      if (_lineupsError == null) {
        setState(() => _lineupsError = 'No se pudieron leer las alineaciones.');
      }
    } finally {
      if (mounted && generation == _lineupsGeneration) {
        _lineupsLoading = false;
      }
    }
  }

  Widget _lineupStatus(String teamId, String label) {
    Map<String, dynamic>? saved;
    for (final row in _savedLineups) {
      if (row['team_id']?.toString() == teamId) { saved = row; break; }
    }
    final players = saved?['lineup'];
    final count = players is List ? players.length : 0;
    final revision = saved?['revision'];
    if (saved == null) {
      return Text('$label: Sin alineación guardada',
          style: const TextStyle(color: Colors.white70));
    }
    final slots = players is List ? List<dynamic>.from(players) : <dynamic>[];
    slots.sort((a, b) {
      final ao = a is Map ? (a['order'] as num?)?.toInt() ?? 0 : 0;
      final bo = b is Map ? (b['order'] as num?)?.toInt() ?? 0 : 0;
      return ao.compareTo(bo);
    });
    return Card(color: const Color(0xFF162131), child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label · $count bateadores · revisión $revision',
            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        if (saved['designated_hitter_id'] != null)
          Text('Bateador designado: ${_lineupPlayerNames[saved['designated_hitter_id'].toString()] ?? 'Pelotero pendiente'}'),
        if (saved['pitcher_id'] != null)
          Text('Pitcher titular: ${_lineupPlayerNames[saved['pitcher_id'].toString()] ?? 'Pelotero pendiente'}'
            '${saved['pitcher_bats'] == false ? ' · solo defensa' : ''}'),
        for (final slot in slots)
          if (slot is Map)
            Text('${slot['order']}. ${_lineupPlayerNames[slot['player_id']?.toString()] ?? 'Pelotero no disponible'}',
                style: const TextStyle(color: Colors.white70)),
      ]),
    ));
  }

  // Resuelve también jugadores sustituidos, que ya no aparecen en la alineación.
  // Los IDs proceden exclusivamente de eventos y estadísticas del partido actual.
  Future<Map<String, String>> _lookupPlayerNames(Set<String> playerIds) async {
    final missing = playerIds.where((id) => id.isNotEmpty &&
        !_lineupPlayerNames.containsKey(id)).toList();
    if (missing.isEmpty) return const {};
    final names = <String, String>{};
    // Lotes pequeños para evitar URLs excesivas en PostgREST.
    for (var start = 0; start < missing.length; start += 40) {
      final batch = missing.skip(start).take(40).toList();
      final players = await _client.from('players')
          .select('id,first_name,last_name,jersey_number')
          .inFilter('id', batch).timeout(const Duration(seconds: 12));
      for (final player in players) {
        final id = player['id']?.toString();
        if (id == null) continue;
        final fullName = [player['first_name'], player['last_name']]
            .map((part) => part?.toString().trim() ?? '')
            .where((part) => part.isNotEmpty).join(' ');
        final number = player['jersey_number']?.toString() ?? '';
        names[id] = '${fullName.isEmpty ? 'Jugador sin nombre' : fullName}'
            '${number.isEmpty ? '' : ' · #$number'}';
      }
    }
    return names;
  }

  // Historial de solo lectura. No crea ni modifica eventos.
  Future<void> _loadRecentEvents() async {
    final id = _game?['id']?.toString();
    if (!mounted || id == null) return;
    if (_eventsLoading && _eventsRequestGameId == id) {
      _eventsRefreshQueued = true;
      return;
    }
    _eventsRequestGameId = id;
    final requestGeneration = ++_eventsRequestGeneration;
    setState(() {
      _eventsLoading = true;
      _eventsError = null;
      _eventsQueried = true;
    });
    try {
      const pageSize = 50;
      const recentLimit = 20;
      final rows = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (var offset = 0; rows.length < recentLimit; offset += pageSize) {
        final page = await _client.from('swl_game_events')
            .select('id,inning,is_top,event_type,event_data,created_at,version')
            .eq('game_id', id)
            .order('version', ascending: false)
            .order('id', ascending: false)
            .range(offset, offset + pageSize - 1)
            .timeout(const Duration(seconds: 12));
        if (!mounted || requestGeneration != _eventsRequestGeneration ||
            _game?['id']?.toString() != id) return;
        rows.addAll(page.where((event) => swlIsHistoryPlay(event) &&
            (event['id'] == null || seen.add(event['id'].toString())))
            .take(recentLimit - rows.length));
        if (page.length < pageSize) break;
      }
      final ids = <String>{};
      for (final event in rows) {
        final data = event['event_data'];
        if (data is! Map) continue;
        for (final key in ['batter_id', 'outgoing_player_id', 'incoming_player_id']) {
          if (data[key] != null) ids.add(data[key].toString());
        }
      }
      final names = await _lookupPlayerNames(ids);
      if (!mounted || requestGeneration != _eventsRequestGeneration || _game?['id']?.toString() != id) return;
      setState(() {
        _recentEvents = List<Map<String, dynamic>>.from(rows);
        _lineupPlayerNames = {..._lineupPlayerNames, ...names};
      });
    } catch (_) {
      if (mounted && requestGeneration == _eventsRequestGeneration && _game?['id']?.toString() == id) {
        setState(() => _eventsError =
            'No se pudo consultar el historial de jugadas.');
      }
    } finally {
      if (mounted && requestGeneration == _eventsRequestGeneration && _eventsRequestGameId == id) {
        setState(() => _eventsLoading = false);
        if (_eventsRefreshQueued && mounted && _game?['id']?.toString() == id) {
          _eventsRefreshQueued = false;
          // Ejecutar la lectura más reciente después de finalizar la anterior.
          _loadRecentEvents();
        }
      }
    }
  }

  Future<void> _loadSubstitutionHistory() async {
    final gameId = _game?['id']?.toString();
    if (gameId == null || !mounted) return;
    if (_substitutionHistoryLoading) {
      // Realtime o el mánager pidió otra lectura mientras la anterior seguía
      // activa. Repetir al terminar para no perder la última sustitución.
      _substitutionHistoryQueued = true;
      return;
    }
    final generation = ++_substitutionHistoryGeneration;
    setState(() {
      _substitutionHistoryLoading = true;
      _substitutionHistoryError = null;
    });
    try {
      final rows = await _client.from('swl_game_events')
          .select('id,inning,is_top,event_type,event_data,created_at,version')
          .eq('game_id', gameId)
          .eq('event_type', 'SUBSTITUTION')
          .order('id', ascending: false)
          .limit(501)
          .timeout(const Duration(seconds: 12));
      final history = List<Map<String, dynamic>>.from(rows.take(500));
      final ids = <String>{};
      for (final event in history) {
        final data = event['event_data'];
        if (data is! Map) continue;
        for (final field in ['outgoing_player_id', 'incoming_player_id']) {
          if (data[field] != null) ids.add(data[field].toString());
        }
      }
      final names = await _lookupPlayerNames(ids);
      if (!mounted || generation != _substitutionHistoryGeneration ||
          _game?['id']?.toString() != gameId) return;
      setState(() {
        _substitutionHistory = history;
        _substitutionHistoryTruncated = rows.length > 500;
        _lineupPlayerNames = {..._lineupPlayerNames, ...names};
      });
    } catch (_) {
      if (mounted && generation == _substitutionHistoryGeneration &&
          _game?['id']?.toString() == gameId) {
        setState(() => _substitutionHistoryError =
            'No se pudo consultar el historial de sustituciones.');
      }
    } finally {
      if (mounted && generation == _substitutionHistoryGeneration) {
        setState(() => _substitutionHistoryLoading = false);
        if (_substitutionHistoryQueued &&
            _game?['id']?.toString() == gameId) {
          _substitutionHistoryQueued = false;
          _loadSubstitutionHistory();
        }
      }
    }
  }

  Future<void> _loadBattingStats() async {
    final id = _game?['id']?.toString();
    if (!mounted || id == null) return;
    if (_battingStatsLoading) {
      _battingStatsQueued = true;
      return;
    }
    final generation = ++_battingStatsGeneration;
    setState(() {
      _battingStatsLoading = true;
      _battingStatsError = null;
    });
    try {
      final raw = await _client.rpc('swl_v53_batting_stats',
          params: {'p_game_id': id})
          .timeout(const Duration(seconds: 12));
      if (!mounted || _game?['id']?.toString() != id ||
          generation != _battingStatsGeneration) return;
      final stats = raw is List
          ? raw.whereType<Map>().map((r) =>
              Map<String, dynamic>.from(r)).toList()
          : <Map<String, dynamic>>[];
      final names = await _lookupPlayerNames(stats
          .map((r) => r['player_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty).toSet());
      if (!mounted || _game?['id']?.toString() != id ||
          generation != _battingStatsGeneration) return;
      setState(() {
        _battingStats = stats;
        _lineupPlayerNames = {..._lineupPlayerNames, ...names};
      });
    } catch (_) {
      if (mounted && _game?['id']?.toString() == id &&
          generation == _battingStatsGeneration) {
        setState(() => _battingStatsError =
            'No se pudieron consultar las estadísticas. Reintenta la actualización.');
      }
    } finally {
      if (mounted && generation == _battingStatsGeneration) {
        setState(() => _battingStatsLoading = false);
        if (_battingStatsQueued) {
          _battingStatsQueued = false;
          _loadBattingStats();
        }
      }
    }
  }

  /// Agrupa el box score preliminar por equipo, sin sumar a los sustitutos
  /// sobre los titulares. Los datos provienen del RPC de eventos anotados.
  Widget _battingBoxScore(Map<String, dynamic> game) {
    final homeId = game['home_team_id']?.toString() ?? '';
    final awayId = game['away_team_id']?.toString() ?? '';
    final currentIds = <String>{};
    for (final lineup in _savedLineups) {
      final slots = lineup['lineup'];
      if (slots is List) {
        for (final slot in slots) {
          if (slot is Map && slot['player_id'] != null) {
            currentIds.add(slot['player_id'].toString());
          }
        }
      }
    }
    final substitutedOut = <String>{};
    final substitutedIn = <String>{};
    for (final event in _substitutionHistory) {
      if (event['event_type'] != 'SUBSTITUTION') continue;
      final raw = event['event_data'];
      if (raw is! Map) continue;
      if (raw['outgoing_player_id'] != null) {
        substitutedOut.add(raw['outgoing_player_id'].toString());
      }
      if (raw['incoming_player_id'] != null) {
        substitutedIn.add(raw['incoming_player_id'].toString());
      }
    }
    int count(Map<String, dynamic> row, String field) =>
        (row[field] as num?)?.toInt() ?? 0;
    Widget section(String teamId, String heading) {
      final rows = _battingStats.where((r) =>
          r['team_id']?.toString() == teamId).toList();
      rows.sort((a, b) =>
          (_lineupPlayerNames[a['player_id']?.toString()] ?? '').compareTo(
              _lineupPlayerNames[b['player_id']?.toString()] ?? ''));
      final vb = rows.fold<int>(0, (sum, r) => sum + count(r, 'at_bats'));
      final h = rows.fold<int>(0, (sum, r) => sum + count(r, 'hits'));
      final bb = rows.fold<int>(0, (sum, r) => sum + count(r, 'walks'));
      final k = rows.fold<int>(0, (sum, r) => sum + count(r, 'strikeouts'));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 10),
        Text(heading, style: const TextStyle(
            color: Colors.amber, fontWeight: FontWeight.bold)),
        if (rows.isEmpty)
          const Text('Sin apariciones registradas para este equipo.',
              style: TextStyle(color: Colors.white70)),
        for (final stat in rows) Builder(builder: (context) {
          final id = stat['player_id']?.toString() ?? '';
          final role = substitutedOut.contains(id) && !currentIds.contains(id)
              ? 'Sustituido'
              : substitutedIn.contains(id) ? 'Entró de cambio'
              : currentIds.contains(id) ? 'En alineación' : 'Participó';
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_lineupPlayerNames[id] ?? id,
                style: const TextStyle(color: Colors.white)),
            subtitle: Text('$role · VB ${count(stat, 'at_bats')} · '
                'H ${count(stat, 'hits')} · 1B ${count(stat, 'singles')} · '
                '2B ${count(stat, 'doubles')} · 3B ${count(stat, 'triples')} · '
                'HR ${count(stat, 'home_runs')} · BB ${count(stat, 'walks')} · '
                'K ${count(stat, 'strikeouts')}',
                style: const TextStyle(color: Colors.white70)),
          );
        }),
        Text('Subtotal registrado · VB $vb · H $h · BB $bb · K $k',
            style: const TextStyle(color: Colors.white70,
                fontWeight: FontWeight.bold)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      const Text('BOX SCORE INDIVIDUAL · PRELIMINAR',
          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
      const Text('Solo jugadas con pelotero identificado. Los subtotales no '
          'sustituyen el marcador oficial. Los titulares y sustitutos '
          'mantienen registros individuales separados.',
          style: TextStyle(color: Colors.white70, fontSize: 12)),
      section(awayId, 'VISITANTE · ${_name(awayId)}'),
      section(homeId, 'LOCAL · ${_name(homeId)}'),
    ]);
  }

  /// Presenta la jugada que el servidor confirmó, no una estimación local.
  /// Los eventos antiguos sin metadatos siguen mostrándose como contadores.
  String _eventDescription(Map<String, dynamic> event) {
    final type = event['event_type']?.toString() ?? 'Jugada';
    final raw = event['event_data'];
    final data = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    if (type == 'SUBSTITUTION') {
      final outId = data['outgoing_player_id']?.toString() ?? '';
      final inId = data['incoming_player_id']?.toString() ?? '';
      final outgoing = _lineupPlayerNames[outId] ?? 'Jugador $outId';
      final incoming = _lineupPlayerNames[inId] ?? 'Jugador $inId';
      return 'Sustitución · turno ${data['batting_order'] ?? '?'}: '
          'sale $outgoing · entra $incoming';
    }
    if ((type == 'HIT' && data['scope'] == 'hit_with_runners') ||
        (type == 'ERROR' && data['charged_team_id'] != null)) {
      final base = (data['batter_base'] as num?)?.toInt();
      final hitName = type == 'ERROR' ? 'Error defensivo' : switch (base) {
        1 => 'Sencillo', 2 => 'Doble', 3 => 'Triple', 4 => 'Jonrón',
        _ => 'Hit',
      };
      final runs = (data['runs'] as num?)?.toInt() ?? 0;
      final outs = (data['outs'] as num?)?.toInt() ?? 0;
      final outLabel = [data['p_first_to'], data['p_second_to'], data['p_third_to']].contains(-4)
          ? ' · out en home' : outs > 0 ? ' · $outs out(s)' : '';
      return '$hitName · $runs ${runs == 1 ? 'carrera' : 'carreras'}$outLabel';
    }
    if (type == 'HIT' && data['scope'] == 'basic_counters') {
      return 'Hit manual (sin avance de corredores)';
    }
    return switch (type) {
      'BALL' => 'Base por bolas',
      'STRIKE' => 'Ponche',
      'RUNNER_MOVE' => 'Movimiento de corredor',
      'RUNNER_OUT' => 'Out del corredor',
      'DOUBLE_PLAY' => 'Doble play',
      'SACRIFICE_FLY' => 'Fly de sacrificio',
      'OUT' => 'Out',
      'RUN' => 'Carrera manual',
      'ERROR' => 'Error manual',
      _ => type,
    };
  }

  /// Describe el boleto a partir del estado real recibido del servidor.
  /// Es una vista previa: la transacción en LAB decide el resultado final.
  String _walkPreview(Map<String, dynamic> game) {
    final raw = game['bases_state'];
    final bases = raw is Map ? raw : const <String, dynamic>{};
    final first = bases['first'] == true;
    final second = bases['second'] == true;
    final third = bases['third'] == true;
    final advances = <String>['Bateador a primera'];
    if (first) advances.add('Corredor de primera a segunda');
    if (first && second) advances.add('Corredor de segunda a tercera');
    if (first && second && third) {
      advances.add('Corredor de tercera anota una carrera');
    } else if (third) {
      advances.add('Corredor de tercera permanece en base');
    }
    return 'Cuarta bola: boleto.\n${advances.join('\n')}.\n'
        'El conteo de bolas y strikes se reiniciará.';
  }

  Future<void> _recordPlay(
    String gameId,
    int expectedVersion,
    String action,
    Map<String, dynamic>? hitParams,
  ) async {
    final userId = _client.auth.currentUser?.id;
    if (!mounted || _game?['id']?.toString() != gameId) return;
    if (_uncertainPlay || _uncertainSubstitutionVersion != null) {
      throw StateError(_scoringMessage ?? 'Revisa el historial antes de volver a anotar.');
    }
    if (_recording || _confirmingPlay || _substitutionPending) {
      throw StateError('Hay una operación del partido en curso.');
    }

    final latest = await _client.from('swl_live_games').select()
        .eq('id', gameId).single().timeout(const Duration(seconds: 12));
    if (!mounted || _game?['id']?.toString() != gameId) return;
    final game = Map<String, dynamic>.from(latest);
    final snapshot = SwlLiveScoreboardSnapshot.fromGame(game);
    if (_recording || _confirmingPlay || _substitutionPending ||
        _uncertainPlay || _uncertainSubstitutionVersion != null) {
      throw StateError('Hay una operación del partido pendiente de confirmar.');
    }
    if (!snapshot.canScore(userId) || _myTeamId(game) != snapshot.battingTeamId ||
        _client.auth.currentUser?.id != userId) {
      throw StateError('El partido no está en curso o no corresponde tu turno.');
    }
    if (snapshot.version != expectedVersion ||
        SwlLiveScoreboardSnapshot.fromGame(_game!).version > expectedVersion) {
      throw StateError('El marcador cambió. Revisa la pizarra antes de confirmar la jugada.');
    }
    final isHit = action == 'HIT' && hitParams != null;
    final extendedBall = const {'HIT_WITH_OUT', 'ERROR'}.contains(action);
    final special = const {'GHOST_RUNNER','RUNNER_MOVE','RUNNER_OUT','RUNNER_REPLACE',
      'DOUBLE_PLAY','SACRIFICE_FLY','HIT_WITH_OUT','ERROR'}.contains(action);
    if (!isHit && !special && !{'BALL', 'STRIKE', 'OUT', 'FOUL'}.contains(action)) {
      throw StateError('Jugada no disponible.');
    }
    if (isHit || extendedBall) {
      if (hitParams == null) throw StateError('Faltan los avances del batazo.');
      // La vista previa local de hits no implementa todos los casos
      // transaccionales de V5.7 (por ejemplo, corredor retirado).
      // No rechazar aquí una jugada que la RPC valida con identidades,
      // ocupación, versión y permisos. Para hits simples conservar preview.
      if (isHit) {
        snapshot.playState.hit(
          batterBase: hitParams['p_batter_base'] as int,
          firstTo: hitParams['p_first_to'] as int?,
          secondTo: hitParams['p_second_to'] as int?,
          thirdTo: hitParams['p_third_to'] as int?,
          countRunsOnThirdOut: hitParams['count_runs_on_third_out'] == true,
        );
      } else {
        final batterBase = hitParams['p_batter_base'];
        // Un HIT_WITH_OUT también puede representar un jonrón (base 4)
        // cuando los corredores anotan normalmente. ERROR no admite HR.
        final maxBatterBase = action == 'ERROR' ? 3 : 4;
        if (batterBase is! int || batterBase < 1 ||
            batterBase > maxBatterBase) {
          throw StateError('Destino del bateador inválido.');
        }
        if (hitParams['p_batter_id'] == null) {
          throw StateError('Falta la identidad del bateador.');
        }
      }
    }
    if (action == 'BALL' && snapshot.balls == 3) {
      setState(() => _confirmingPlay = true);
      bool? accepted;
      try {
        accepted = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmar jugada'),
            content: Text(_walkPreview(game)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('CANCELAR')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('CONFIRMAR')),
            ],
          ),
        );
      } finally {
        if (mounted) setState(() => _confirmingPlay = false);
      }
      if (accepted != true || !mounted || _game?['id']?.toString() != gameId) return;
      if (_client.auth.currentUser?.id != userId ||
          SwlLiveScoreboardSnapshot.fromGame(_game!).version > expectedVersion) {
        throw StateError('Cambió la sesión o el marcador. Vuelve a revisar la jugada.');
      }
    }
    final requestGeneration = ++_recordGeneration;
    setState(() { _recording = true; _scoringMessage = null; });
    var sent = false;
    try {
      String? plateBatterId;
      if (!isHit && (!special || const {'SACRIFICE_FLY', 'DOUBLE_PLAY', 'HIT_WITH_OUT', 'ERROR'}.contains(action))) {
        final lineup = await _client.from('swl_game_lineups').select('lineup')
            .eq('game_id', gameId).eq('team_id', snapshot.battingTeamId)
            .maybeSingle().timeout(const Duration(seconds: 12));
        final slots = swlConfirmedBattingSlots(lineup?['lineup']);
        final cursor = await _client.from('swl_game_batting_turns')
            .select('next_order').eq('game_id', gameId)
            .eq('team_id', snapshot.battingTeamId)
            .maybeSingle().timeout(const Duration(seconds: 12));
        final nextOrder = (cursor?['next_order'] as num?)?.toInt() ?? 1;
        if (nextOrder < 1 || nextOrder > slots.length) {
          throw StateError('Guarda y actualiza la alineación del equipo que batea.');
        }
        plateBatterId = slots[nextOrder - 1]['player_id']?.toString();
        if (extendedBall && plateBatterId != hitParams?['p_batter_id']) {
          throw StateError('Cambió el bateador. Vuelve a abrir el batazo.');
        }
        if (plateBatterId == null || plateBatterId.isEmpty) {
          throw StateError('El bateador no tiene identificador válido.');
        }
      }
      if (!mounted || _game?['id']?.toString() != gameId) return;
      if (_client.auth.currentUser?.id != userId ||
          SwlLiveScoreboardSnapshot.fromGame(_game!).version > expectedVersion) {
        throw StateError('Cambió la sesión o el marcador. Vuelve a revisar la jugada.');
      }
      final authorized = await _client.rpc('swl_can_manage_roster',
          params: {'p_team_id': snapshot.battingTeamId}).timeout(const Duration(seconds: 12));
      if (!mounted || _game?['id']?.toString() != gameId) return;
      if (authorized != true || _client.auth.currentUser?.id != userId ||
          SwlLiveScoreboardSnapshot.fromGame(_game!).version > expectedVersion) {
        throw StateError('Ya no tienes permiso vigente para anotar esta jugada.');
      }
      final params = {
        'p_game_id': gameId,
        'p_expected_version': expectedVersion,
        if (!isHit) 'p_action': action,
        if (!isHit && !extendedBall) 'p_batter_id': plateBatterId,
        if (extendedBall) 'p_batter_id': plateBatterId,
        if (isHit) ...hitParams,
        // Las RPC de jugadas especiales reciben SOLO p_data; los campos
        // p_batter_base/p_first_to/etc no son argumentos de la función.
        if (special) 'p_data': hitParams ?? <String, dynamic>{},
      };
      final rpcParams = action == 'DOUBLE_PLAY' ? <String, dynamic>{
        'p_game_id': gameId,
        'p_expected_version': expectedVersion,
        'p_source': hitParams?['source'],
      } : extendedBall ? <String, dynamic>{
        'p_game_id': gameId,
        'p_expected_version': expectedVersion,
        'p_action': action,
        'p_batter_id': plateBatterId,
        // La RPC verifica que el bateador dentro de p_data coincida
        // exactamente con el bateador autorizado del turno. Construirlo
        // aquí impide que un diálogo antiguo o una sustitución deje
        // identificadores inconsistentes entre ambos argumentos.
        'p_data': <String, dynamic>{
          ...hitParams!,
          'p_batter_id': plateBatterId,
        },
      } : params;
      sent = true;
      try {
        await _client.rpc(action == 'DOUBLE_PLAY' ? 'swl_v57_double_play' :
            action == 'FOUL' ? 'swl_v56_record_foul' : special ? (extendedBall
              ? (action == 'ERROR' ? 'swl_v57_defensive_error' : 'swl_v57_batted_ball')
              : 'swl_v56_special_play') : isHit ? 'swl_v56_apply_hit' :
            'swl_v56_record_plate_action', params: rpcParams)
            .timeout(const Duration(seconds: 12));
      } on PostgrestException catch (error) {
        // PGRST202 indica que PostgREST no pudo invocar la función nueva.
        // Una respuesta incierta sigue el flujo de reconciliación.
        if (special || action == 'FOUL' || error.code != 'PGRST202' || _savedLineups.any((row) => row['pitcher_id'] != null)) rethrow;
        await _client.rpc(isHit ? 'swl_v53_apply_hit_for_player' :
            'swl_v53_record_plate_action', params: params)
            .timeout(const Duration(seconds: 12));
      }
      // La RPC respondió; un fallo posterior de refresco no es un envío incierto.
      sent = false;
      await _refreshGame(afterCurrent: true);
      await _loadRecentEvents();
      await _loadBattingStats();
    } catch (error) {
      if (!sent) rethrow;
      if (error is PostgrestException) {
        final status = int.tryParse(error.code ?? '');
        if (status == null || status < 500) {
          // Un rechazo puede coincidir con una jugada registrada por el otro
          // teléfono. Refrescar también historial y estadísticas evita dejar
          // la pizarra y el relato en versiones distintas.
          // El error de la RPC es el diagnóstico principal. Un fallo de red
          // durante el refresco no debe ocultarlo con otro mensaje.
          try {
            await _refreshGame(afterCurrent: true);
            await _loadRecentEvents();
            await _loadBattingStats();
          } catch (_) {
            // Mantener visible el rechazo original del servidor.
          }
          throw StateError(error.code == 'PGRST202' || error.code == '42883'
              ? (special ? 'Esta jugada todavía no está habilitada en el servidor. No se registró; contacta al administrador.' : 'Esta anotación todavía no está habilitada en el servidor. No se registró; contacta al administrador.')
              : error.message);
        }
      }
      if (!mounted || requestGeneration != _recordGeneration ||
          _game?['id']?.toString() != gameId) return;
      setState(() {
        _uncertainPlay = true;
        _scoringMessage = 'La respuesta se interrumpió. Revisa el historial antes de volver a anotar.';
      });
      try {
        final event = await _client.from('swl_game_events')
            .select('version')
            .eq('game_id', gameId).eq('version', expectedVersion + 1)
            .maybeSingle().timeout(const Duration(seconds: 8));
        if (!mounted || requestGeneration != _recordGeneration ||
            _game?['id']?.toString() != gameId) return;
        if (event != null) {
          setState(() {
            _uncertainPlay = false;
            _scoringMessage =
                'El partido avanzó. Revisa el historial antes de anotar otra jugada.';
          });
        }
      } catch (_) {
        // El bloqueo se mantiene si el historial no permite resolver el envío.
      }
      await _refreshGame(afterCurrent: true);
      await _loadRecentEvents();
      if (_scoringMessage != null) throw StateError(_scoringMessage!);
    } finally {
      if (mounted && requestGeneration == _recordGeneration) {
        setState(() => _recording = false);
      }
    }
  }

  void _subscribe(String id) {
    _stopWatching();
    _channel = _client.channel('swl-lobby-$id')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'swl_live_games',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, column: 'id', value: id),
        callback: (payload) {
          if (!mounted || _game?['id']?.toString() != id) return;
          // Realtime puede entregar campos incompletos o eventos fuera de orden.
          // La lectura SELECT con versión es la fuente de verdad.
          _refreshGame(afterCurrent: true);
          if (_teamConfirmed && !_lineupsLoading) _loadSavedLineups();
        },
      )..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'swl_game_events',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, column: 'game_id', value: id),
        callback: (payload) {
          if (!mounted || _game?['id']?.toString() != id) return;
          // El historial se lee desde la base de datos, nunca del payload.
          _loadRecentEvents();
        },
      ).subscribe();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      // La recepción de un evento Realtime no garantiza que la conexión
      // continúe activa. La consulta periódica permite detectar cortes.
      _refreshGame();
      if (_teamConfirmed && !_lineupsLoading) _loadSavedLineups();
      // Respaldo si Realtime pierde eventos o se desconecta.
      if (++_historyPollTicks % 4 == 0) _loadRecentEvents();
    });
  }

  void _stopWatching() {
    _watchGeneration++;
    _eventsRequestGeneration++;
    _eventsRefreshQueued = false;
    _historyPollTicks = 0;
    _lineupsGeneration++;
    _lineupsLoading = false;
    _battingStatsGeneration++;
    _battingStatsQueued = false;
    _battingStatsLoading = false;
    _battingStatsError = null;
    _savedLineups = [];
    _substitutionHistory = [];
    _substitutionHistoryGeneration++;
    _substitutionHistoryLoading = false;
    _substitutionHistoryQueued = false;
    _substitutionHistoryTruncated = false;
    _substitutionHistoryError = null;
    _lineupPlayerNames = {};
    _lineupsError = null;
    _uncertainPlay = false;
    _substitutionPending = false;
    _uncertainSubstitutionVersion = null;
    _confirmingPlay = false;
    _gameRefresh = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final old = _channel;
    _channel = null;
    if (old != null) _client.removeChannel(old);
  }

  String _name(dynamic id) {
    final key = id?.toString();
    if (key != null && _teamNames.containsKey(key)) return _teamNames[key]!;
    if (_away?['id']?.toString() == key) return _away?['name']?.toString() ?? 'Visitante';
    for (final t in widget.authorizedTeams) {
      if (t['id']?.toString() == key) return t['name']?.toString() ?? 'Local';
    }
    return 'Equipo';
  }

  Future<void> _loadNames() async {
    final game = _game;
    if (game == null) return;
    try {
      final ids = [game['home_team_id'], game['away_team_id']].whereType<String>().toList();
      if (ids.isEmpty) return;
      final rows = await swlQueryTeams((columns) async =>
          await _client.from('teams').select(columns).inFilter('id', ids)
             .timeout(const Duration(seconds: 12)));
      if (!mounted || _game?['id'] != game['id']) return;
      setState(() {
        for (final row in rows) {
          final id = row['id']?.toString();
          final name = row['name']?.toString();
          if (id != null && name != null) _teamNames[id] = name;
          final logo = swlTeamLogo(row);
          if (id != null && logo != null) _teamLogos[id] = logo;
          if (row['id'] == game['away_team_id']) {
            _away = Map<String, dynamic>.from(row);
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopWatching();
    _scoreboard.dispose();
    _searchTimer?.cancel();
    _searchGeneration++;
    _pin.dispose();
    _teamSearch.dispose();
    super.dispose();
  }

  Widget _baseLabel(String base, bool occupied) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(occupied ? Icons.sports_baseball : Icons.circle_outlined,
          size: 15, color: occupied ? Colors.amber : Colors.white54),
      const SizedBox(width: 4),
      Text('$base ${occupied ? "OCUPADA" : "LIBRE"}',
          style: TextStyle(fontSize: 11,
              color: occupied ? Colors.amber : Colors.white70)),
    ],
  );

  // Solo lectura: interpreta el estado JSONB existente sin escribir datos.
  bool _baseOccupied(Map<String, dynamic> game, String base) {
    final state = game['bases_state'];
    if (state is! Map) return false;
    return state[base] == true;
  }

  // Solo lectura: el RPC básico aún no actualiza home_innings/away_innings.
  // No mostrar un desglose como oficial cuando no concilia con el total.
  List<int>? _serverInnings(dynamic raw) {
    if (raw is! List) return null;
    final values = <int>[];
    for (final item in raw) {
      if (item is! num || item < 0 || item != item.toInt()) return null;
      values.add(item.toInt());
    }
    return values;
  }

  Widget _inningAudit(Map<String, dynamic> game) {
    final home = _serverInnings(game['home_innings']);
    final away = _serverInnings(game['away_innings']);
    final homeRuns = (game['home_runs'] as num?)?.toInt() ?? 0;
    final awayRuns = (game['away_runs'] as num?)?.toInt() ?? 0;
    final valid = home != null && away != null &&
        home.fold<int>(0, (a, b) => a + b) == homeRuns &&
        away.fold<int>(0, (a, b) => a + b) == awayRuns;
    if (!valid) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('Desglose por entrada pendiente de conciliación con el servidor. '
            'El marcador total sigue siendo la referencia de esta prueba LAB.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text('Carreras por entrada · Visitante: ${away.join(' / ')} · '
          'Local: ${home.join(' / ')}',
          style: const TextStyle(color: Colors.white70, fontSize: 12)),
    );
  }

  Future<void> _showActiveRoster(String teamId, String teamName) async {
    if (teamId.isEmpty) return;
    // Carga antes de abrir el diálogo: no se confunde roster vacío con error.
    try {
      final players = await SwlRosterRepository(_client).activePlayers(teamId)
          .timeout(const Duration(seconds: 12));
      if (!mounted || _game == null) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text('Roster activo · $teamName'),
        content: SizedBox(width: 420, child: players.isEmpty
          ? const Text('Este equipo no tiene peloteros fichados activos.')
          : ListView(shrinkWrap: true, children: [
              for (final player in players) ListTile(
                dense: true,
                title: Text('${player.name} · #${player.number}'),
                subtitle: Text('ID: ${player.universalId.isEmpty ? player.playerId : player.universalId} · ${player.positionLabel}${player.isRefuerzo ? ' · Refuerzo' : ''}'),
              ),
            ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('CERRAR'))],
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo consultar el roster: $e')));
    }
  }

  /// Alineación oficial: el servidor valida mánager, equipo y roster activo.
  bool _savingLineup = false;

  Future<void> _draftLineup(String teamId, String teamName) async {
    final game = _game;
    if (_savingLineup || _startingGame || game == null ||
        !['SCHEDULED', 'IN_PROGRESS'].contains(game['status'])) return;
    final myId = _client.auth.currentUser?.id;
    if (myId == null || _myTeamId(game) != teamId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Solo el mánager de este equipo puede preparar su alineación.')));
      return;
    }
    setState(() => _savingLineup = true);
    try {
      final players = await SwlRosterRepository(_client).activePlayers(teamId)
          .timeout(const Duration(seconds: 12));
      if (!mounted || _game?['id'] != game['id']) return;
      final saved = _savedLineups.where(
          (row) => row['team_id']?.toString() == teamId).firstOrNull;
      final expectedRevision = (saved?['revision'] as num?)?.toInt() ?? 0;
      final rivalPlayers = <String>{};
      for (final row in _savedLineups) {
        if (row['team_id']?.toString() == teamId) continue;
        rivalPlayers.addAll(swlConfirmedBattingSlots(row['lineup'])
            .map((slot) => slot['player_id']?.toString()).whereType<String>());
        if (row['defensive_positions'] case final Map defense) {
          rivalPlayers.addAll(defense.keys.whereType<String>());
        }
        if (row['pitcher_id'] case final String pitcher) rivalPlayers.add(pitcher);
      }
      final roster = {
        for (final player in players)
          if (!rivalPlayers.contains(player.playerId)) player.playerId: player,
      };
      if (players.any((player) => rivalPlayers.contains(player.playerId))) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Los peloteros confirmados por el rival no pueden jugar en ambos equipos.'),
        ));
      }
      final slots = swlConfirmedBattingSlots(saved?['lineup']);
      final selected = <String>{
        for (final slot in slots)
          if (roster.containsKey(slot['player_id'])) slot['player_id'] as String,
        // The batting order is independent of the defensive assignments.
        // Do not add non-batting fielders to the offensive order.
      }.toList();
      final savedPositions = saved?['defensive_positions'];
      final positions = <String, String>{
        if (savedPositions is Map)
          for (final entry in savedPositions.entries)
            if (roster.containsKey(entry.key) &&
                swlDefensivePositions.contains(entry.value) && entry.value != 'P')
              entry.key as String: entry.value as String,
        if (roster.containsKey(saved?['pitcher_id'])) saved!['pitcher_id'] as String: 'P',
      };
      var draft = SwlLineupDraft(selected, positions,
        pitcherBats: saved?['pitcher_bats'] != false || !positions.containsValue('P'),
        designatedId: saved?['designated_hitter_id']?.toString(),
      );
      final draftKey = 'swl.lineup.$myId.${game['id']}.$teamId.$expectedRevision';
      final preferences = SharedPreferencesAsync();
      String? previous;
      try {
        previous = await preferences.getString(draftKey);
        if (previous != null) {
          draft = SwlLineupDraft.fromLocalJson(
            jsonDecode(previous) as Map<String, dynamic>, roster.keys.toSet());
        }
      } on FormatException {
        previous = null;
      } on TypeError {
        previous = null;
      } catch (_) {
        // La edición sigue disponible si falla el almacenamiento del teléfono.
      }
      if (!mounted || _game?['id'] != game['id'] ||
          _client.auth.currentUser?.id != myId) return;
      Future<void> pendingDraftWrite = Future.value();
      var draftWriteFailed = false;
      void persistDraft(String? value) {
        pendingDraftWrite = pendingDraftWrite.then((_) async {
          try {
            if (value == null) {
              await preferences.remove(draftKey);
            } else {
              await preferences.setString(draftKey, value);
            }
            draftWriteFailed = false;
          } catch (_) {
            draftWriteFailed = true;
          }
        });
      }

      final save = await showSwlLineupEditor(
        context, teamName: teamName, roster: roster, draft: draft,
        onDraftChanged: (working) => persistDraft(jsonEncode(working.toLocalJson())),
      );
      if (save == null) persistDraft(previous);
      await pendingDraftWrite;
      if (!mounted || _game?['id'] != game['id']) return;
      if (draftWriteFailed) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo actualizar el borrador local.')));
      }
      if (save != true) return;
      if (_client.auth.currentUser?.id != myId || _game?['status'] != game['status']) {
        throw StateError('Cambió la sesión o el estado del partido.');
      }
      // LAB V5.6 requires a complete defensive lineup to start the game.
      // Never silently save a batting-only lineup through the legacy RPC:
      // it would appear saved but fail BOTH_LINEUPS_REQUIRED on start.
      await _client.rpc(
        'swl_v56_save_lineup',
        params: draft.saveParameters(
          gameId: game['id'].toString(), teamId: teamId,
          revision: expectedRevision, extended: true,
        ),
      ).timeout(const Duration(seconds: 12));
      if (!mounted || _game?['id'] != game['id']) return;
      persistDraft(null);
      await pendingDraftWrite;
      await _loadSavedLineups(announce: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is PostgrestException && e.code == 'PGRST202'
            ? 'LAB aún no admite guardar pitcher y posiciones. La selección sigue sin confirmarse.'
            : e.toString().contains('LINEUP_LOCKED_AFTER_FIRST_PLATE_ACTION')
              ? 'La alineación se bloqueó al comenzar el bateo. Usa SUSTITUIR BATEADOR.'
              : e.toString().contains('INVALID_PITCHER_OR_POSITIONS')
                ? 'Selecciona un pitcher y asigna posiciones defensivas válidas antes de guardar.'
                : e.toString().contains('PITCHER_INVALID')
                  ? 'El pitcher debe pertenecer al roster y ocupar la posición P. Si batea, inclúyelo en el orden; si no batea, déjalo fuera.'
                  : e.toString().contains('DESIGNATED_HITTER_INVALID')
                    ? 'Revisa el bateador designado: si el pitcher batea, no debe haber DH; si no batea, el DH debe estar en el orden y fuera de la defensa.'
                    : e.toString().contains('DEFENSIVE_POSITIONS_')
                      ? 'Las posiciones defensivas deben ser únicas y pertenecer a jugadores activos del equipo.'
                      : e.toString().contains('STALE_LINEUP_REVISION')
                        ? 'La alineación cambió en otro dispositivo. Actualízala antes de guardar.'
                        : e.toString().contains('LINEUP_REVISION')
                  ? 'La alineación cambió en otro dispositivo. Actualízala antes de guardar.'
                  : (_eligibilityMessage(e) ?? 'No se pudo confirmar la alineación: $e'))));
    } finally {
      if (mounted) setState(() => _savingLineup = false);
    }
  }

  /// Sustitución de bateador: el servidor valida y registra el cambio atómicamente.
  Future<void> _substituteBatter(String teamId, String teamName, {BuildContext? dialogHost}) async {
    final game = _game;
    if (game == null || game['status'] != 'IN_PROGRESS' ||
        _myTeamId(game) != teamId || _recording || _confirmingPlay ||
        _uncertainPlay || _substitutionPending || _uncertainSubstitutionVersion != null) return;
    final gameId = game['id']?.toString();
    final myId = _client.auth.currentUser?.id;
    final isHome = game['home_team_id']?.toString() == teamId;
    final manager = isHome ? game['home_manager_id'] : game['away_manager_id'];
    if (gameId == null || myId == null || manager?.toString() != myId) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solo el mánager del equipo puede sustituir.')));
      return;
    }
    final found = _savedLineups.where((r) => r['team_id']?.toString() == teamId);
    if (found.isEmpty || found.first['lineup'] is! List) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Primero guarda la alineación del equipo.')));
      return;
    }
    final saved = found.first;
    final revision = (saved['revision'] as num?)?.toInt() ?? 0;
    final slots = swlConfirmedBattingSlots(saved['lineup']);
    if (slots.isEmpty || slots.length > 13) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El orden confirmado no es válido. Actualiza la alineación.')));
      return;
    }
    setState(() => _substitutionPending = true);
    try {
      final roster = await SwlRosterRepository(_client).activePlayers(teamId)
          .timeout(const Duration(seconds: 12));
      if (!mounted || _game?['id']?.toString() != gameId) return;
      final currentIds = slots.whereType<Map>()
          .map((slot) => slot['player_id']?.toString()).toSet();
      final removedIds = {
        for (final event in _substitutionHistory)
          if (event['event_data'] case final Map data)
            data['outgoing_player_id']?.toString(),
      };
      final available = roster.where((p) => !currentIds.contains(p.playerId) &&
          p.playerId != saved['pitcher_id'] && !removedIds.contains(p.playerId)).toList();
      if (available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No hay peloteros disponibles fuera de la alineación.')));
        return;
      }
      int order = 1;
      String? incomingId = available.first.playerId;
      if (dialogHost != null && !dialogHost.mounted) return;
      final confirmed = await showDialog<bool>(
        context: dialogHost ?? context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('Sustitución · $teamName'),
            content: SizedBox(width: 420, child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                const Text('El jugador entrante ocupa el mismo turno. '
                    'El jugador saliente conserva sus estadísticas. '
                    'No se permiten reingresos en esta versión.'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: order,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Turno que se sustituye'),
                  items: [
                    for (var i = 0; i < slots.length; i++)
                      DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}. '
                          '${_lineupPlayerNames[slots[i]['player_id']?.toString()] ?? "Pelotero"}',
                          overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) { if (v != null) update(() => order = v); },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: incomingId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Pelotero entrante'),
                  items: [
                    for (final player in available)
                      DropdownMenuItem(
                        value: player.playerId,
                        child: Text('${player.name} · #${player.number}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => update(() => incomingId = v),
                ),
              ],
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('CANCELAR')),
              FilledButton(onPressed: incomingId == null ? null :
                () => Navigator.pop(dialogContext, true),
                child: const Text('CONFIRMAR SUSTITUCIÓN')),
            ],
          ),
        ),
      );
      if (confirmed != true || incomingId == null || !mounted ||
          _game?['id']?.toString() != gameId) return;
      final outgoingId = slots[order - 1]['player_id']?.toString();
      if (outgoingId == null) return;
      // Validación local antes de llamar a LAB; el servidor vuelve a validar
      // de manera transaccional frente a cambios concurrentes.
      try {
        SwlSubstitutionRequest(
          gameId: gameId,
          teamId: teamId,
          outgoingPlayerId: outgoingId,
          incomingPlayerId: incomingId!,
          battingOrder: order,
          expectedLineupRevision: revision,
        ).validate(
          activeOrder: {
            for (var index = 0; index < slots.length; index++)
              index + 1: slots[index]['player_id'].toString(),
          },
          rosterIds: roster.map((p) => p.playerId).toSet(),
          previouslyRemovedPlayerIds: {
            for (final event in _substitutionHistory)
              if (event['event_data'] is Map &&
                  (event['event_data'] as Map)['outgoing_player_id'] != null)
                (event['event_data'] as Map)['outgoing_player_id'].toString(),
          },
        );
      } on StateError catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sustitución inválida: ${e.message}')));
        return;
      }
      final version = (game['version'] as num?)?.toInt();
      final currentLineup = _savedLineups
          .where((row) => row['team_id']?.toString() == teamId).firstOrNull;
      if (version == null || _client.auth.currentUser?.id != myId ||
          _game?['version'] != game['version'] ||
          currentLineup?['revision'] != saved['revision']) {
        throw StateError('El partido cambió. Revisa la sustitución antes de enviarla.');
      }
      // Una respuesta perdida puede significar que el servidor SI confirmó
      // el cambio. No permitir otro intento hasta reconciliar el estado.
      var rpcStarted = false;
      try {
        rpcStarted = true;
        final extended = saved['pitcher_id'] != null ||
            (saved['defensive_positions'] is Map && (saved['defensive_positions'] as Map).isNotEmpty);
        await _client.rpc(extended ? 'swl_v56_substitute_batter' : 'swl_v53_substitute_batter', params: {
        'p_game_id': gameId,
        'p_team_id': teamId,
        'p_batting_order': order,
        'p_outgoing_id': outgoingId,
        'p_incoming_id': incomingId,
        'p_expected_revision': revision,
        'p_expected_game_version': version,
        }).timeout(const Duration(seconds: 12));
      } catch (e) {
        // Un rechazo explicito de PostgREST confirma que la operacion fallo.
        // Solo una perdida de respuesta (red/timeout) deja resultado incierto.
        final serverRejected = e is PostgrestException &&
            swlIsExplicitSubstitutionRejection(e.code);
        if (rpcStarted && !serverRejected && mounted &&
            _game?['id']?.toString() == gameId) {
          setState(() => _uncertainSubstitutionVersion = version);
        }
        rethrow;
      }
      if (mounted) setState(() => _uncertainSubstitutionVersion = null);
      if (!mounted || _game?['id']?.toString() != gameId) return;
      await _loadSavedLineups();
      await _refreshGame(afterCurrent: true);
      await _loadSubstitutionHistory();
      await _loadBattingStats();
      if (!mounted || _game?['id']?.toString() != gameId) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sustitución confirmada en LAB.')));
    } catch (e) {
      if (!mounted || _game?['id']?.toString() != gameId) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_eligibilityMessage(e) ?? 'No se pudo verificar la sustitución. '
            'Actualiza el partido y revisa la alineación antes de reintentar: $e')));
    } finally {
      if (mounted && _game?['id']?.toString() == gameId) {
        setState(() => _substitutionPending = false);
      }
    }
  }

  String? _myTeamId(Map<String, dynamic> game) {
    if (widget.readOnly) return null;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    for (final side in ['home', 'away']) {
      final teamId = game['${side}_team_id']?.toString();
      if (game['${side}_manager_id']?.toString() == userId && teamId != null &&
          widget.authorizedTeams.any((team) => team['id']?.toString() == teamId)) {
        return teamId;
      }
    }
    return null;
  }

  bool _hasMyLineup(Map<String, dynamic> game) {
    final teamId = _myTeamId(game);
    if (teamId == null) return false;
    return _savedLineups.any((row) =>
      row['team_id']?.toString() == teamId &&
      row['lineup'] is List && (row['lineup'] as List).isNotEmpty);
  }

  Widget _teamConfirmationView() {
    final game = _game!;
    final myTeamId = _myTeamId(game);
    final homeId = game['home_team_id']?.toString();
    final awayId = game['away_team_id']?.toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('PASO 2 · TOMA TU EQUIPO',
        style: TextStyle(color: Colors.amber, fontSize: 20,
          fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      SelectableText('Partido ${game['game_pin'] ?? ''}',
        style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 14),
      for (final side in [
        {'id': homeId, 'label': 'LOCAL'},
        {'id': awayId, 'label': 'VISITANTE'},
      ])
        Card(color: const Color(0xFF162131), child: ListTile(
          leading: SwlTeamBadge(url: _teamLogos[side['id']]),
          title: Text(_name(side['id']),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(side['label']!,
            style: const TextStyle(color: Colors.white70)),
          trailing: side['id'] == myTeamId
            ? const Icon(Icons.verified, color: Colors.greenAccent)
            : const Icon(Icons.lock_outline, color: Colors.white38),
        )),
      const SizedBox(height: 12),
      if (myTeamId == null)
        FilledButton.icon(
          onPressed: _openOriginalScoreboardPreview,
          icon: const Icon(Icons.visibility),
          label: const Text('VER RESULTADO EN VIVO'),
        )
      else ...[
        Text('Tu equipo autorizado: ${_name(myTeamId)}',
          style: const TextStyle(color: Colors.greenAccent)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            setState(() => _teamConfirmed = true);
            _loadSavedLineups();
          },
          icon: const Icon(Icons.arrow_forward),
          label: const Text('CONTINUAR A MI ALINEACIÓN'),
        ),
      ],
      const SizedBox(height: 12),
      TextButton(onPressed: _leaveGame, child: const Text('VOLVER')),
    ]);
  }

  bool _hasConfirmedLineup(String? teamId) => teamId != null &&
      _savedLineups.any((row) {
        if (row['team_id']?.toString() != teamId) return false;
        final count = swlConfirmedBattingSlots(row['lineup']).length;
        return count >= 9 && count <= 13;
      });

  bool _canStartGame(Map<String, dynamic> game) {
    final home = game['home_team_id']?.toString();
    final away = game['away_team_id']?.toString();
    return game['status'] == 'SCHEDULED' && home != null && home != away &&
        _myTeamId(game) == home && game['away_manager_id'] != null &&
        game['away_manager_id'] != game['home_manager_id'] &&
        _lineupsError == null && _hasConfirmedLineup(home) && _hasConfirmedLineup(away);
  }

  Future<void> _startGame() async {
    final game = _game;
    if (_startingGame || _savingLineup || game == null || !_canStartGame(game)) return;
    setState(() => _startingGame = true);
    try {
      await _client.rpc('swl_v56_start_game', params: {
        'p_game_id': game['id'],
        'p_expected_version': game['version'],
      }).timeout(const Duration(seconds: 12));
      await _refreshGame(afterCurrent: true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == 'PGRST202' || error.code == '42883'
          ? 'LAB aún no tiene habilitada la transición para iniciar el partido.'
          : _eligibilityMessage(error) ?? error.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      await _refreshGame(afterCurrent: true);
      if (mounted && _game?['status'] != 'IN_PROGRESS') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se confirmó el inicio. Actualiza el partido antes de reintentar.')));
      }
    } finally {
      if (mounted) setState(() => _startingGame = false);
    }
  }

  Future<void> _showRivalLineup(String rivalId) async {
    await _loadSavedLineups();
    if (!mounted || !context.mounted) return;
    await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
      title: Text('Alineación rival · ${_name(rivalId)}'),
      content: SingleChildScrollView(child: _lineupsError == null
          ? _lineupStatus(rivalId, 'Alineación confirmada')
          : Text(_lineupsError!)),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('CERRAR'))],
    ));
  }

  Future<void> _changePitcher(SwlLiveScoreboardSnapshot snapshot) async {
    final game = _game;
    final team = game == null ? null : _myTeamId(game);
    if (_substitutionPending || _uncertainSubstitutionVersion != null ||
        _recording || _confirmingPlay || _uncertainPlay || team == null || game == null ||
        team == snapshot.battingTeamId || snapshot.status != 'IN_PROGRESS' ||
        snapshot.gameId != game['id'] || game['balls'] != 0 || game['strikes'] != 0) return;
    final lineup = _savedLineups.where((row) => row['team_id'] == team).firstOrNull;
    final pitcherId = lineup?['pitcher_id']?.toString();
    if (pitcherId == null) return;
    final order = lineup?['lineup'];
    if (order is! List) return;
    final batters = {for (final slot in order.whereType<Map>()) slot['player_id']?.toString()};
    setState(() => _substitutionPending = true);
    try {
      final players = await SwlRosterRepository(_client).activePlayers(team)
          .timeout(const Duration(seconds: 12));
      if (!mounted || _game?['id'] != game['id']) return;
      // La posición habitual no limita quién puede lanzar. Para un cambio
      // puramente defensivo, se permite intercambiar dos jugadores en campo.
      // Un ingreso desde el banco con pitcher bateador requiere sustituir
      // primero el turno al bate para evitar desordenar la alineación.
      final defensive = lineup?['defensive_positions'];
      final assigned = defensive is Map ? defensive.keys.map((e) => e.toString()).toSet() : <String>{};
      final eligible = players.where((player) => player.playerId != pitcherId &&
          (lineup?['pitcher_bats'] == false
              ? !batters.contains(player.playerId) && !assigned.contains(player.playerId)
              : assigned.contains(player.playerId) && batters.contains(player.playerId)));
      final candidate = await showDialog<String>(context: context, builder: (dialog) =>
        AlertDialog(
          title: const Text('Cambiar pitcher'),
          content: SizedBox(width: 400, child: eligible.isEmpty
              ? const Text('No hay otro pitcher elegible con la regla de bateo actual.')
              : ListView(shrinkWrap: true, children: [
                for (final player in eligible)
                  ListTile(title: Text(player.name), subtitle: Text(player.positionLabel),
                    onTap: () => Navigator.pop(dialog, player.playerId)),
              ])),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('CANCELAR'))],
        ),
      );
      if (!mounted || candidate == null || _game?['id'] != game['id']) return;
      if (_game?['version'] != snapshot.version || _myTeamId(_game!) != team) {
        throw StateError('El partido cambió. Revisa el cambio de pitcher.');
      }
      try {
        await _client.rpc('swl_v56_change_pitcher', params: {
          'p_game_id': game['id'], 'p_team_id': team, 'p_player_id': candidate,
          'p_expected_version': snapshot.version,
        }).timeout(const Duration(seconds: 12));
      } catch (error) {
        if (mounted && _game?['id'] == game['id'] &&
            (error is! PostgrestException ||
                !swlIsExplicitSubstitutionRejection(error.code))) {
          setState(() => _uncertainSubstitutionVersion = snapshot.version);
        }
        rethrow;
      }
      await _refreshGame(afterCurrent: true);
      await _loadSavedLineups(announce: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        error is PostgrestException && error.code == 'PGRST202'
          ? 'LAB aún no admite cambios de pitcher.'
          : 'No se confirmó el cambio. Actualiza la alineación antes de repetir: $error')));
    } finally {
      if (mounted) setState(() => _substitutionPending = false);
    }
  }

  Future<void> _swapFielders(SwlLiveScoreboardSnapshot snapshot) async {
    final game = _game;
    final team = game == null ? null : _myTeamId(game);
    if (team == null || game == null || team == snapshot.battingTeamId ||
        snapshot.status != 'IN_PROGRESS' || snapshot.balls != 0 || snapshot.strikes != 0 ||
        snapshot.gameId != game['id'] || _recording || _confirmingPlay ||
        _uncertainPlay || _substitutionPending ||
        _uncertainSubstitutionVersion != null) return;
    final lineup = _savedLineups.where((row) => row['team_id'] == team).firstOrNull;
    final positions = lineup?['defensive_positions'];
    if (positions is! Map) return;
    final fielders = positions.entries.where((entry) => entry.value != 'P').toList();
    if (fielders.length < 2) return;
    setState(() => _substitutionPending = true);
    try {
      var first = fielders.first.key.toString();
      var second = fielders[1].key.toString();
      final accepted = await showDialog<bool>(context: context,
        builder: (dialog) => StatefulBuilder(builder: (_, update) {
          Widget select(String label, String value, ValueChanged<String> change) =>
              DropdownButtonFormField<String>(
                initialValue: value, isExpanded: true,
                decoration: InputDecoration(labelText: label),
                items: [for (final entry in fielders)
                  DropdownMenuItem(value: entry.key.toString(),
                    child: Text('${entry.value} · ${_lineupPlayerNames[entry.key] ?? 'Pelotero'}'))],
                onChanged: (id) { if (id != null) update(() => change(id)); },
              );
          return AlertDialog(title: const Text('Intercambiar posiciones defensivas'),
            scrollable: true, content: Column(mainAxisSize: MainAxisSize.min, children: [
              select('Primer defensor', first, (id) => first = id),
              select('Segundo defensor', second, (id) => second = id),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('CANCELAR')),
              FilledButton(onPressed: first == second ? null : () => Navigator.pop(dialog, true),
                child: const Text('INTERCAMBIAR')),
            ]);
        }));
      if (accepted != true || !mounted || _game?['id'] != game['id']) return;
      if (_game?['version'] != snapshot.version || _myTeamId(_game!) != team) {
        throw StateError('Cambió el partido. Actualiza la alineación.');
      }
      try {
        await _client.rpc('swl_v57_swap_fielders', params: {
          'p_game_id': game['id'], 'p_team_id': team, 'p_expected_version': snapshot.version,
          'p_first': first, 'p_second': second,
        }).timeout(const Duration(seconds: 12));
      } catch (error) {
        if (mounted && _game?['id'] == game['id'] &&
            (error is! PostgrestException ||
                !swlIsExplicitSubstitutionRejection(error.code))) {
          setState(() => _uncertainSubstitutionVersion = snapshot.version);
        }
        rethrow;
      }
      await _refreshGame(afterCurrent: true);
      await _loadSavedLineups(announce: true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        error is PostgrestException && (error.code == 'PGRST202' || error.code == '42883')
          ? 'El intercambio de posiciones requiere la función de LAB.'
          : 'No se confirmó el intercambio: $error')));
    } finally {
      if (mounted) setState(() => _substitutionPending = false);
    }
  }

  Future<void> _reviewPendingSubstitution() async {
    final id = _game?['id'];
    final version = _uncertainSubstitutionVersion;
    if (id == null || version == null || _substitutionPending) return;
    setState(() => _substitutionPending = true);
    try {
      await _refreshGame(afterCurrent: true);
      await Future.wait([_loadSavedLineups(), _loadSubstitutionHistory()]);
      if (!mounted || _game?['id'] != id) return;
      if (_connectionWarning != null || _lineupsError != null ||
          _substitutionHistoryError != null || (_game?['version'] as num?) == null) {
        throw StateError('No se pudo verificar el estado del partido.');
      }
      final advanced = (_game!['version'] as num) > version;
      setState(() => _uncertainSubstitutionVersion = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(advanced
          ? 'El partido avanzó. Revisa la alineación actual antes de repetir el cambio.'
          : 'La versión sigue igual. Si reintentas, el servidor validará la versión.')));
    } catch (error) {
      if (mounted && _game?['id'] == id) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted && _game?['id'] == id) setState(() => _substitutionPending = false);
    }
  }

  Future<void> _showGameDetails(BuildContext scoreboardContext) async {
    final game = _game;
    if (game == null) return;
    final id = game['id'].toString();
    Map<String, SwlPitchingTotals>? pitching;
    Map<String, String> pitcherNames = {};
    String? pitchingError;
    Future<void> readPitching() async {
      try {
        pitching = await swlLoadPitching(_client, id, SwlLiveScoreboardSnapshot.fromGame(game).version);
        pitcherNames = await _lookupPlayerNames(pitching?.keys.toSet() ?? {});
      } catch (_) {
        pitchingError = 'No se pudo leer la estadística de pitcheo.';
      }
    }
    await Future.wait([_loadSavedLineups(), _loadRecentEvents(),
      _loadSubstitutionHistory(), _loadBattingStats(), readPitching()]);
    if (!mounted || !scoreboardContext.mounted || _game?['id']?.toString() != id) return;
    await showDialog<void>(context: scoreboardContext, builder: (dialog) => AlertDialog(
      title: const Text('Box Score y alineaciones'),
      content: SizedBox(width: 450, child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_name(game['away_team_id'])} ${game['away_runs'] ?? 0} · '
            '${_name(game['home_team_id'])} ${game['home_runs'] ?? 0} · ${game['status']}'),
          _inningAudit(game),
          for (final side in ['away', 'home'])
            if (game['${side}_team_id'] != null)
              _lineupStatus(game['${side}_team_id'].toString(), _name(game['${side}_team_id'])),
          for (final message in [_lineupsError, _battingStatsError, _substitutionHistoryError,
            _eventsError, if (_substitutionHistoryTruncated) 'Historial de sustituciones limitado.'])
            if (message != null) Text(message),
          _battingBoxScore(game),
          const Text('Pitcheo individual · jugadas acreditadas'),
          if (pitchingError != null) Text(pitchingError!),
          if (pitchingError == null && (pitching == null || pitching!.isEmpty))
            const Text('Aún no hay estadísticas de pitcheo confirmadas.'),
          for (final entry in (pitching ?? <String, SwlPitchingTotals>{}).entries)
            ListTile(title: Text(pitcherNames[entry.key] ?? _lineupPlayerNames[entry.key] ?? 'Pitcher'),
              subtitle: Text('${entry.value.innings} IP · ${entry.value.strikeouts} K · '
                '${entry.value.walks} BB · ${entry.value.hits} H\n${entry.value.pitchLine}')), 
          const Text('Jugadas recientes'),
          if (_eventsQueried)
            for (final event in _recentEvents) ListTile(title: Text(_eventDescription(event))),
        ]),
      )),
      actions: [
        if (game['status'] == 'OFFICIAL') SwlShareBoxScoreButton(gameId: id),
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('CERRAR')),
      ],
    ));
  }

  String? _eligibilityMessage(Object error) {
    if (error is! PostgrestException) return null;
    return switch (error.message) {
      'PELOTERO_EN_AMBOS_EQUIPOS' => 'Un pelotero ya está confirmado con el equipo rival.',
      'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO' => 'Un pelotero ya participa con otro equipo o está en otro partido activo.',
      'PELOTERO_FUERA_DEL_ROSTER' => 'Un pelotero ya no está activo en el roster del equipo.',
      _ => null,
    };
  }

  Future<void> _sendDecision(String gameId, int version, String action) async {
    final game = _game;
    if (game == null || game['id']?.toString() != gameId || _myTeamId(game) == null) {
      throw StateError('El partido ya no está disponible para este mánager.');
    }
    final cancel = action.startsWith('CANCEL_');
    try {
      await _client.rpc(cancel ? 'swl_v57_cancel_game' : 'swl_v56_match_decision', params: {
        'p_game_id': gameId, 'p_expected_version': version, 'p_action': action,
      }).timeout(const Duration(seconds: 12));
      await _refreshGame(afterCurrent: true);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw StateError(cancel ? 'La cancelación conjunta requiere habilitación en LAB.'
            : 'Cierre y firmas pendientes de habilitación en LAB.');
      }
      rethrow;
    }
  }

  Widget _lineupPreparationView() {
    final game = _game!;
    final myTeamId = _myTeamId(game);
    if (myTeamId == null) return _teamConfirmationView();
    final homeId = game['home_team_id']?.toString();
    final awayId = game['away_team_id']?.toString();
    final rivalId = myTeamId == homeId ? awayId : homeId;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('PASO 3 · PREPARA TU ALINEACIÓN',
        style: TextStyle(color: Colors.amber, fontSize: 20,
          fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text(_name(myTeamId), style: const TextStyle(color: Colors.white,
        fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      _lineupStatus(myTeamId, 'Mi alineación'),
      if (_lineupsError != null)
        Text(_lineupsError!, style: const TextStyle(color: Colors.orangeAccent)),
      const SizedBox(height: 14),
      if (['SCHEDULED', 'IN_PROGRESS'].contains(game['status']))
        FilledButton.icon(
          onPressed: _savingLineup || _startingGame || _lineupsError != null
              ? null : () => _draftLineup(myTeamId, _name(myTeamId)),
          icon: const Icon(Icons.edit_note),
          label: Text(_savingLineup ? 'PROCESANDO ALINEACIÓN…' : 'EDITAR MI ALINEACIÓN'),
        ),
      Align(alignment: Alignment.centerRight, child: IconButton(
        tooltip: 'Actualizar partido y alineaciones',
        onPressed: () async {
          await _refreshGame(afterCurrent: true);
          await _loadSavedLineups(announce: true);
        },
        icon: const Icon(Icons.refresh, size: 20),
      )),
      const SizedBox(height: 12),
      if (rivalId != null)
        OutlinedButton(onPressed: () => _showRivalLineup(rivalId),
          child: const Text('VER ALINEACIÓN RIVAL')),
      if (game['status'] == 'SCHEDULED' && myTeamId == homeId)
        FilledButton(
          onPressed: _startingGame || _savingLineup || !_canStartGame(game)
                ? null : _startGame,
          child: Text(_startingGame ? 'INICIANDO…' : 'INICIAR PARTIDO'),
        ),
      if (game['status'] == 'SCHEDULED')
        const Text('El mánager local inicia el partido cuando ambos equipos han confirmado su alineación.'),
      if (_hasMyLineup(game) || game['status'] == 'IN_PROGRESS' ||
          SwlLiveScoreboardSnapshot.fromGame(game).cancellationActions(_client.auth.currentUser?.id).isNotEmpty ||
          game['swl_cancel_requested_by'] != null || game['status'] == 'CANCELLED')
        FilledButton.icon(
          onPressed: _openOriginalScoreboardPreview,
          icon: const Icon(Icons.sports_baseball),
          label: const Text('ABRIR PIZARRA OFICIAL'),
        )
      else
        const Text('Guarda tu alineación para continuar a la pizarra. '
          'El rival prepara la suya desde su propio dispositivo.',
          style: TextStyle(color: Colors.white70)),
      if (game['status'] == 'IN_PROGRESS' && game['is_top'] is bool &&
          myTeamId != SwlLiveScoreboardSnapshot.fromGame(game).battingTeamId &&
          _savedLineups.any((row) => row['team_id'] == myTeamId && row['pitcher_id'] != null))
        ...[
          OutlinedButton(
            onPressed: _substitutionPending || _uncertainSubstitutionVersion != null ||
                game['balls'] != 0 || game['strikes'] != 0
                ? null : () => _changePitcher(SwlLiveScoreboardSnapshot.fromGame(game)),
            child: const Text('CAMBIAR PITCHER'),
          ),
          OutlinedButton(
            onPressed: _substitutionPending || _uncertainSubstitutionVersion != null ||
                game['balls'] != 0 || game['strikes'] != 0
                ? null : () => _swapFielders(SwlLiveScoreboardSnapshot.fromGame(game)),
            child: const Text('INTERCAMBIAR POSICIONES'),
          ),
        ],
      if (_hasMyLineup(game) && game['status'] == 'IN_PROGRESS')
        OutlinedButton(
          onPressed: _substitutionPending || _uncertainSubstitutionVersion != null ? null :
              () => _substituteBatter(myTeamId, _name(myTeamId)),
          child: const Text('SUSTITUIR BATEADOR'),
        ),
      if (_uncertainSubstitutionVersion != null)
        OutlinedButton(
          onPressed: _substitutionPending ? null : _reviewPendingSubstitution,
          child: const Text('VERIFICAR CAMBIO PENDIENTE'),
        ),
      OutlinedButton(
        onPressed: () => _showActiveRoster(myTeamId, _name(myTeamId)),
        child: const Text('VER ROSTER ACTIVO'),
      ),
      TextButton(onPressed: () => setState(() => _teamConfirmed = false),
        child: const Text('VOLVER A MI EQUIPO')),
    ]);
  }

  void _leaveGame() {
    _stopWatching();
    setState(() {
      _game = null;
      _battingStats = [];
      _teamConfirmed = false;
      _away = null;
      _teamNames.clear();
      _teamLogos.clear();
      _error = null;
      _connectionWarning = null;
      _savedLineups = [];
      _lineupPlayerNames = {};
    });
  }

  // La pizarra oficial es la única pantalla de anotación del partido.
  Future<void> _openOriginalScoreboardPreview({bool exitLobbyOnReturn = false}) async {
    final game = _game;
    if (game == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ValueListenableBuilder(
        valueListenable: _scoreboard,
        builder: (context, live, child) => SwlAdvancedScoreboard(
        gamePin: game['game_pin']?.toString() ?? '',
        homeTeam: _name(game['home_team_id']?.toString() ?? ''),
        awayTeam: _name(game['away_team_id']?.toString() ?? ''),
        liveSnapshot: live ?? SwlLiveScoreboardSnapshot.fromGame(game),
        onLiveDetails: () => _showGameDetails(context),
        onLiveSubstitute: _myTeamId(_game ?? game) != null &&
            live?.status == 'IN_PROGRESS'
            ? () async {
              if (_uncertainSubstitutionVersion != null) {
                await _reviewPendingSubstitution();
                return;
              }
              final team = _myTeamId(_game ?? game);
              if (team == null) return;
              // Leer la versión y el turno actuales antes de sustituir:
              // el rival puede haber anotado mientras se abría el menú.
              await _refreshGame(afterCurrent: true);
              if (!mounted || _game == null ||
                  _game!['status'] != 'IN_PROGRESS' ||
                  _myTeamId(_game!) != team ||
                  _substitutionPending || _uncertainSubstitutionVersion != null) return;
              await _loadSavedLineups();
              if (mounted && context.mounted) {
                await _substituteBatter(team, _name(team), dialogHost: context);
              }
            } : null,
        onLivePitcher: _myTeamId(_game ?? game) != null &&
            live?.status == 'IN_PROGRESS' &&
            _myTeamId(_game ?? game) != live?.battingTeamId &&
            live?.balls == 0 && live?.strikes == 0
            ? () async {
                if (live == null) return;
                if (_uncertainSubstitutionVersion != null) {
                  await _reviewPendingSubstitution();
                  return;
                }
                await _loadSavedLineups();
                if (mounted) await _changePitcher(live);
              } : null,
        onLiveSwapFielders: _myTeamId(_game ?? game) != null &&
            live?.status == 'IN_PROGRESS' &&
            _myTeamId(_game ?? game) != live?.battingTeamId &&
            live?.balls == 0 && live?.strikes == 0
            ? () async {
                if (live == null) return;
                if (_uncertainSubstitutionVersion != null) {
                  await _reviewPendingSubstitution();
                  return;
                }
                await _loadSavedLineups();
                if (mounted) await _swapFielders(live);
              } : null,
        onLiveRefresh: _myTeamId(game) == null ? null : _reviewPendingSubstitution,
        onMatchDecision: _myTeamId(game) == null ? null :
            (version, action) => _sendDecision(game['id'].toString(), version, action),
        homeLogo: _teamLogos[game['home_team_id']],
        awayLogo: _teamLogos[game['away_team_id']],
        onLiveAction: _myTeamId(game) == null ? null :
            (version, action, hitParams) =>
                _recordPlay(game['id'].toString(), version, action, hitParams),
        ),
      ),
    ));
    if (mounted && exitLobbyOnReturn) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final owned = widget.authorizedTeams;
    final homeId = owned.any((t) => t['id']?.toString() == _homeId) ? _homeId : null;
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(title: const Text('⚾ PIZARRA EN VIVO'),
          backgroundColor: const Color(0xFF162131)),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        if (_game != null) ...[
          if (!_teamConfirmed) _teamConfirmationView()
          else _lineupPreparationView(),
        ] else ...[
          if (owned.isNotEmpty) ...[
          const Text('CREAR PARTIDO COMO LOCAL',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: homeId,
            dropdownColor: const Color(0xFF162131),
            decoration: const InputDecoration(labelText: 'Mi equipo local',
                labelStyle: TextStyle(color: Colors.white70)),
            items: owned.map((t) => DropdownMenuItem<String>(
              value: t['id'].toString(),
              child: Text(t['name']?.toString() ?? 'Equipo',
                  style: const TextStyle(color: Colors.white)))).toList(),
            onChanged: _busy ? null : (v) => setState(() {
              _homeId = v;
              if (_away?['id']?.toString() == v) _away = null;
            }),
          ),
          const SizedBox(height: 12),
          SwlTeamSearchField(
            controller: _teamSearch,
            byCode: _teamSearchByCode,
            onModeChanged: (value) {
              setState(() {
                _teamSearchByCode = value;
                _away = null;
                _teamSearch.clear();
              });
              _searchTeams('');
            },
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Buscar visitante por nombre, localidad o código SWL',
              prefixIcon: Icon(Icons.search),
              labelStyle: TextStyle(color: Colors.white70)),
            onChanged: (term) {
              if (_away != null) setState(() => _away = null);
              _searchTeams(term);
            },
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_matches.isNotEmpty) ...[
            const SizedBox(height: 6),
            ..._matches.map((t) => ListTile(
              leading: SwlTeamBadge(url: swlTeamLogo(t)),
              title: Text(t['name']?.toString() ?? 'Equipo',
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(t['province']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white54)),
              onTap: () => setState(() {
                _away = t;
                _teamSearchByCode = false;
                _matches = [];
                _teamSearch.text = t['name']?.toString() ?? '';
                _searchTimer?.cancel();
              }),
            )),
          ],
          if (_away != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('VISITANTE SELECCIONADO: ${_away!['name']}',
                style: const TextStyle(color: Colors.greenAccent)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy || homeId == null || _away == null ||
                _away!['id']?.toString() == homeId ? null : () async {
              await _run(() => _client.rpc('swl_v5_create_game', params: {
                'p_home_team_id': homeId, 'p_away_team_id': _away!['id'],
              }));
            },
            child: const Text('CREAR Y GENERAR PIN'),
          ),
          const Divider(height: 36),
          ],
          const Text('CONECTARME POR PIN',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            inputFormatters: const [SwlCodeInputFormatter(maxDigits: 6)],
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'PIN del partido (6 números)',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              prefixText: swlCodePrefix,
              prefixStyle: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
              labelStyle: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : () async {
              await _joinFromPin(_pin.text);
            },
            child: const Text('CONECTARME AL PARTIDO'),
          ),
        ],
        if (_connectionWarning != null) Text(_connectionWarning!),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      ]),
    );
  }
}
