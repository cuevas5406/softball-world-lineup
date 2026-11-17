import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'swl_roster_repository.dart';
import 'swl_substitution_rules.dart';

/// V5.2: emparejamiento real, consulta del partido y reconexión.
/// Anotación básica LAB disponible; reglas avanzadas pendientes.
class SwlLiveLobby extends StatefulWidget {
  final List<Map<String, dynamic>> authorizedTeams;
  const SwlLiveLobby({super.key, required this.authorizedTeams});

  @override
  State<SwlLiveLobby> createState() => _SwlLiveLobbyState();
}

class _SwlLiveLobbyState extends State<SwlLiveLobby> {
  final _client = Supabase.instance.client;
  final _pin = TextEditingController();
  final _teamSearch = TextEditingController();
  List<Map<String, dynamic>> _matches = [];
  String? _homeId;
  Map<String, dynamic>? _away;
  final Map<String, String> _teamNames = {};
  Map<String, dynamic>? _game;
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
  bool _recording = false;
  bool _substitutionPending = false;
  bool _substitutionUncertain = false;
  bool _confirmingPlay = false;
  bool _uncertainPlay = false;
  int _recordGeneration = 0;
  String? _scoringMessage;
  // RPC swl_v53_record_play instalado y verificado en LAB.
  // SOLO contadores básicos; no representa una anotación completa.
  static const bool _scoringBackendReady = true;
  bool _searching = false;
  bool _refreshing = false;
  bool _refreshQueued = false;
  int _watchGeneration = 0;
  DateTime? _lastSuccessfulRefresh;
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
  bool _eventsQueried = false;
  String? _eventsRequestGameId;
  int _eventsRequestGeneration = 0;
  String? _eventsError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _homeId = widget.authorizedTeams.isEmpty
        ? null
        : widget.authorizedTeams.first['id']?.toString();
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
        final safe = term.trim().replaceAll('%', r'\%').replaceAll('_', r'\_');
        final rows = await _client.from('teams')
            .select('id,name,province')
            .or('name.ilike.%$safe%,province.ilike.%$safe%')
            .order('name').limit(20);
        if (!mounted || searchGeneration != _searchGeneration ||
            _teamSearch.text.trim() != term.trim()) return;
        setState(() {
          _matches = List<Map<String, dynamic>>.from(rows)
              .where((t) => t['id'].toString() != _homeId).toList();
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
      final result = await action();
      if (!mounted) return;
      final game = Map<String, dynamic>.from(result as Map);
      setState(() {
        _game = game;
        _savedLineups = [];
        _lineupPlayerNames = {};
        _lineupsError = null;
        _lineupsGeneration++;
        _connectionWarning = null;
        _lastSuccessfulRefresh = null;
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
      _subscribe(game['id'].toString());
      _loadSubstitutionHistory();
      await _refreshGame();
      await _loadSavedLineups();
      await _loadNames();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo completar la operación: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshGame() async {
    final id = _game?['id']?.toString();
    if (id == null || !mounted) return;
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    final generation = _watchGeneration;
    try {
      final row = await _client.from('swl_live_games').select().eq('id', id).single()
          .timeout(const Duration(seconds: 12));
      if (mounted && generation == _watchGeneration && _game?['id']?.toString() == id) {
        final incoming = Map<String, dynamic>.from(row);
        final currentVersion = (_game?['version'] as num?)?.toInt() ?? -1;
        final incomingVersion = (incoming['version'] as num?)?.toInt() ?? -1;
        if (incomingVersion >= currentVersion) {
          setState(() {
            _game = incoming;
            _lastSuccessfulRefresh = DateTime.now();
            _connectionWarning = null;
          });
        }
      }
    } catch (_) {
      // Conservar el partido y el PIN; no ocultar el fallo de sincronización.
      if (mounted && generation == _watchGeneration && _game?['id']?.toString() == id) {
        setState(() => _connectionWarning =
            'No se pudo actualizar el partido. Comprueba la conexión.');
      }
    } finally {
      // Una consulta antigua no debe alterar el estado de otra sesión.
      if (generation == _watchGeneration) {
        _refreshing = false;
        if (_refreshQueued && mounted) {
          _refreshQueued = false;
          // Releer si llegaron eventos durante la consulta.
          _refreshGame();
        }
      }
    }
  }

  /// Lee la alineación confirmada en LAB. No usa borradores locales.
  Future<void> _loadSavedLineups() async {
    final gameId = _game?['id']?.toString();
    if (gameId == null || !mounted) return;
    final generation = ++_lineupsGeneration;
    setState(() { _lineupsLoading = true; _lineupsError = null; });
    try {
      final rows = await _client.from('swl_game_lineups')
          .select('team_id,lineup,revision,updated_at')
          .eq('game_id', gameId)
          .timeout(const Duration(seconds: 12));
      final saved = List<Map<String, dynamic>>.from(rows);
      final ids = <String>{};
      for (final row in saved) {
        final lineup = row['lineup'];
        if (lineup is! List) continue;
        for (final slot in lineup) {
          if (slot is Map && slot['player_id'] != null) {
            ids.add(slot['player_id'].toString());
          }
        }
      }
      final names = <String, String>{};
      if (ids.isNotEmpty) {
        final players = await _client.from('players')
            .select('id,first_name,last_name,jersey_number')
            .inFilter('id', ids.toList())
            .timeout(const Duration(seconds: 12));
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
      if (!mounted || generation != _lineupsGeneration ||
          _game?['id']?.toString() != gameId) return;
      setState(() {
        _savedLineups = saved;
        _lineupPlayerNames = {..._lineupPlayerNames, ...names};
      });
    } catch (_) {
      if (!mounted || generation != _lineupsGeneration ||
          _game?['id']?.toString() != gameId) return;
      setState(() => _lineupsError = 'No se pudieron leer las alineaciones.');
    } finally {
      if (mounted && generation == _lineupsGeneration) {
        setState(() => _lineupsLoading = false);
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
    if (id == null || (_eventsLoading && _eventsRequestGameId == id)) return;
    _eventsRequestGameId = id;
    final requestGeneration = ++_eventsRequestGeneration;
    setState(() {
      _eventsLoading = true;
      _eventsError = null;
      _eventsQueried = true;
    });
    try {
      final rows = await _client.from('swl_game_events')
          .select('id,inning,is_top,event_type,event_data,created_at,version')
          .eq('game_id', id)
          .order('id', ascending: false)
          .limit(20)
          .timeout(const Duration(seconds: 12));
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
    if (id == null) return;
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
              _lineupPlayerNames[b['player_id']?.toString()] ?? '')));
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
    if (type == 'HIT' && data['scope'] == 'hit_with_runners') {
      final base = (data['batter_base'] as num?)?.toInt();
      final hitName = switch (base) {
        1 => 'Sencillo', 2 => 'Doble', 3 => 'Triple', 4 => 'Jonrón',
        _ => 'Hit',
      };
      final runs = (data['runs'] as num?)?.toInt() ?? 0;
      return '$hitName · $runs ${runs == 1 ? 'carrera' : 'carreras'}';
    }
    if (type == 'HIT' && data['scope'] == 'basic_counters') {
      return 'Hit manual (sin avance de corredores)';
    }
    return switch (type) {
      'BALL' => 'Bola / posible boleto',
      'STRIKE' => 'Strike / posible ponche',
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

  /// Valida la vista previa; Supabase LAB vuelve a verificar todo bajo bloqueo.
  String? _hitDestinationError(int batterBase, bool first, bool second,
      bool third, int? firstTo, int? secondTo, int? thirdTo) {
    if (batterBase < 1 || batterBase > 4) return 'Base del bateador inválida.';
    if ((first && firstTo == null) || (second && secondTo == null) ||
        (third && thirdTo == null)) return 'Falta el destino de un corredor.';
    if ((!first && firstTo != null) || (!second && secondTo != null) ||
        (!third && thirdTo != null)) return 'Hay un corredor inexistente.';
    if (first && ![0, 2, 3].contains(firstTo)) return 'Destino de primera inválido.';
    if (second && ![0, 2, 3].contains(secondTo)) return 'Destino de segunda inválido.';
    if (third && ![0, 3].contains(thirdTo)) return 'Destino de tercera inválido.';
    if (first && second && secondTo == 2) {
      return 'El corredor de segunda debe avanzar: está forzado.';
    }
    if (first && second && third && thirdTo == 3) {
      return 'Con bases llenas, el corredor de tercera debe anotar.';
    }
    if (batterBase == 4 &&
        ((first && firstTo != 0) || (second && secondTo != 0) ||
         (third && thirdTo != 0))) {
      return 'El jonrón debe impulsar a todos los corredores a home.';
    }
    final occupied = <int>[batterBase, if (first) firstTo!,
      if (second) secondTo!, if (third) thirdTo!]
        .where((base) => base != 0 && base != 4).toList();
    if (occupied.toSet().length != occupied.length) {
      return 'Dos corredores no pueden ocupar la misma base.';
    }
    return null;
  }

  /// Captura los destinos de TODOS los corredores antes de anotar el hit.
  /// La versión se vuelve a verificar al confirmar para evitar jugadas obsoletas.
  Future<void> _showHitDialog() async {
    final game = _game;
    if (game == null || _recording || _confirmingPlay || _uncertainPlay ||
        _substitutionPending || _substitutionUncertain) return;
    final gameId = game['id']?.toString();
    final version = game['version'];
    final bases = Map<String, dynamic>.from(game['bases_state'] as Map? ?? {});
    final first = bases['first'] == true;
    final second = bases['second'] == true;
    final third = bases['third'] == true;
    final battingTeamId = (game['is_top'] == true
        ? game['away_team_id'] : game['home_team_id'])?.toString();
    final matching = _savedLineups.where(
        (row) => row['team_id']?.toString() == battingTeamId);
    final slots = matching.isEmpty ? <dynamic>[] :
        List<dynamic>.from(matching.first['lineup'] as List? ?? []);
    final batterIds = slots.whereType<Map>().map(
        (slot) => slot['player_id']?.toString() ?? '').where(
        (id) => id.isNotEmpty).toList();
    if (batterIds.isEmpty) {
      if (mounted) setState(() => _scoringMessage =
          'Primero guarda y actualiza la alineación del equipo que batea.');
      return;
    }
    // La fuente de verdad del turno es LAB, no una selección manual.
    int nextOrder = 1;
    try {
      final cursor = await _client.from('swl_game_batting_turns')
          .select('next_order')
          .eq('game_id', gameId!)
          .eq('team_id', battingTeamId!)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));
      nextOrder = (cursor?['next_order'] as num?)?.toInt() ?? 1;
    } catch (_) {
      if (mounted) setState(() => _scoringMessage =
          'No se pudo consultar el turno al bate. Actualiza y reintenta.');
      return;
    }
    if (!mounted || _game?['id']?.toString() != gameId ||
        nextOrder < 1 || nextOrder > batterIds.length) {
      if (mounted) setState(() => _scoringMessage =
          'Turno no válido. Revisa la alineación y actualiza el partido.');
      return;
    }
    final batterId = batterIds[nextOrder - 1];
    int batterBase = 1;
    int? firstTo = first ? 2 : null;
    int? secondTo = second ? (first ? 3 : 2) : null;
    int? thirdTo = third ? (first && second ? 0 : 3) : null;
    setState(() => _confirmingPlay = true);
    Map<String, dynamic>? selected;
    try {
      selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) {
            Widget destination(String label, int? current, void Function(int) change,
                List<int> options) => DropdownButtonFormField<int>(
              value: current,
              decoration: InputDecoration(labelText: label),
              items: [for (final v in options) DropdownMenuItem(
                value: v, child: Text(v == 0 ? 'Anota carrera' : 'Base $v'))],
              onChanged: (v) { if (v != null) updateDialog(() => change(v)); },
            );
            final destinationError = _hitDestinationError(
                batterBase, first, second, third, firstTo, secondTo, thirdTo);
            final runs = (batterBase == 4 ? 1 : 0) +
                (firstTo == 0 ? 1 : 0) +
                (secondTo == 0 ? 1 : 0) +
                (thirdTo == 0 ? 1 : 0);
            return AlertDialog(
              title: const Text('Registrar hit completo · LAB'),
              content: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('Turno $nextOrder · ${_lineupPlayerNames[batterId] ?? batterId}'),
                    subtitle: const Text('Bateador asignado por la alineación guardada'),
                  ),
                  const SizedBox(height: 8),
                  destination('Bateador', batterBase, (v) {
                    batterBase = v;
                    if (v == 4) {
                      if (first) firstTo = 0;
                      if (second) secondTo = 0;
                      if (third) thirdTo = 0;
                    }
                  }, [1, 2, 3, 4]),
                  if (first) destination('Corredor en primera', firstTo,
                      (v) => firstTo = v, [2, 3, 0]),
                  if (second) destination('Corredor en segunda', secondTo,
                      (v) => secondTo = v, [2, 3, 0]),
                  if (third) destination('Corredor en tercera', thirdTo,
                      (v) => thirdTo = v, [3, 0]),
                  const SizedBox(height: 12),
                  Text('Carreras de esta jugada: $runs',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (destinationError != null)
                    Text(destinationError,
                        style: const TextStyle(color: Colors.redAccent)),
                  const Text('4 = jonrón. 0 = corredor anota. El servidor también valida la jugada.'),
                ],
              )),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('CANCELAR')),
                FilledButton(onPressed: destinationError != null ? null : () => Navigator.pop(dialogContext, {
                  'p_batter_id': batterId,
                  'p_batter_base': batterBase,
                  'p_first_to': firstTo,
                  'p_second_to': secondTo,
                  'p_third_to': thirdTo,
                }), child: const Text('CONFIRMAR HIT')),
              ],
            );
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _confirmingPlay = false);
    }
    if (!mounted || selected == null || _recording || _uncertainPlay ||
        _substitutionPending || _substitutionUncertain ||
        _game?['id']?.toString() != gameId || _game?['version'] != version) return;
    await _recordPlay('HIT', hitParams: selected);
  }

  Future<void> _recordPlay(String action, {Map<String, dynamic>? hitParams}) async {
    final game = _game;
    final userId = _client.auth.currentUser?.id;
    if (!_scoringBackendReady || game == null || _recording || _confirmingPlay ||
        _uncertainPlay || _substitutionPending || _substitutionUncertain || userId == null) return;
    if (game['home_manager_id'] == null || game['away_manager_id'] == null ||
        (game['home_manager_id']?.toString() != userId &&
         game['away_manager_id']?.toString() != userId)) return;
    if (game['status'] == 'FINAL' || game['status'] == 'OFFICIAL') return;
    if (hitParams == null && !{'BALL', 'STRIKE', 'OUT'}.contains(action)) return;
    // Los contadores manuales pueden alterar el resultado de un partido.
    // Exigir confirmación explícita antes de enviarlos al servidor.
    if (action == 'RUN' || (action == 'HIT' && hitParams == null) || action == 'ERROR' ||
        (action == 'BALL' && ((game['balls'] as num?)?.toInt() ?? 0) == 3) ||
        (action == 'STRIKE' && ((game['strikes'] as num?)?.toInt() ?? 0) == 2) ||
        (action == 'OUT' && ((game['outs'] as num?)?.toInt() ?? 0) == 2)) {
      setState(() => _confirmingPlay = true);
      bool? accepted;
      try {
        accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar anotación de prueba'),
          content: Text(action == 'BALL' ? _walkPreview(game) : action == 'STRIKE' ? 'El tercer strike registrará ponche y out. Si es el tercero, cambiará la mitad de la entrada. ¿Confirmas?' : action == 'OUT'
              ? 'Este es el tercer out: cambiará la mitad de la entrada, '
                'reiniciará bolas, strikes y outs y limpiará las bases. '
                '¿Confirmas el cambio?'
              : '¿Registrar $action manualmente? Esta acción se guarda '
                'en Supabase LAB y se comparte con el otro dispositivo. '
                'Todavía no mueve corredores ni actualiza el box score.'),
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
      if (accepted != true || !mounted || _recording || _uncertainPlay ||
          _substitutionPending || _substitutionUncertain ||
          _game?['id'] != game['id'] ||
          _game?['version'] != game['version']) return;
    }
    final gameId = game['id']?.toString();
    final version = (game['version'] as num?)?.toInt();
    if (gameId == null || version == null) return;
    final isPlateAction = hitParams == null &&
        (action == 'BALL' || action == 'STRIKE' || action == 'OUT');
    final requestGeneration = ++_recordGeneration;
    setState(() { _recording = true; _scoringMessage = null; });
    try {
      String? plateBatterId;
      if (isPlateAction) {
        final teamId = (game['is_top'] == true
            ? game['away_team_id'] : game['home_team_id'])?.toString();
        final lineups = _savedLineups.where(
            (row) => row['team_id']?.toString() == teamId);
        if (teamId == null || lineups.isEmpty) {
          throw StateError('Guarda y actualiza la alineación del equipo que batea.');
        }
        final slots = List<dynamic>.from(
            lineups.first['lineup'] as List? ?? []);
        final cursor = await _client.from('swl_game_batting_turns')
            .select('next_order')
            .eq('game_id', gameId)
            .eq('team_id', teamId)
            .maybeSingle()
            .timeout(const Duration(seconds: 12));
        final nextOrder = (cursor?['next_order'] as num?)?.toInt() ?? 1;
        if (nextOrder < 1 || nextOrder > slots.length) {
          throw StateError('Turno inválido. Actualiza la alineación.');
        }
        plateBatterId =
            (slots[nextOrder - 1] as Map)['player_id']?.toString();
        if (plateBatterId == null || plateBatterId.isEmpty) {
          throw StateError('El bateador no tiene identificador válido.');
        }
      }
      await _client.rpc(hitParams != null
          ? 'swl_v53_apply_hit_for_player'
          : isPlateAction
              ? 'swl_v53_record_plate_action'
              : 'swl_v53_record_plate_action', params: {
        'p_game_id': gameId,
        'p_expected_version': version,
        if (hitParams == null) 'p_action': action,
        if (isPlateAction) 'p_batter_id': plateBatterId,
        if (hitParams != null) ...hitParams,
      }).timeout(const Duration(seconds: 12));
      if (!mounted || requestGeneration != _recordGeneration ||
          _game?['id']?.toString() != gameId) return;
      setState(() => _scoringMessage = '${hitParams != null ? 'Hit completo registrado' : action == 'RUN' || action == 'HIT' || action == 'ERROR' ? 'Contador manual registrado' : 'Jugada registrada'}. Actualizando marcador…');
      // La escritura ya fue confirmada. Errores de lectura posteriores
      // no deben presentarse como una anotación de resultado incierto.
      try {
        await _refreshGame();
        await _loadRecentEvents();
        await _loadBattingStats();
      } catch (_) {
        if (mounted && requestGeneration == _recordGeneration) {
          setState(() => _scoringMessage =
              'Jugada guardada; no se pudo refrescar la pantalla. Revisa el marcador.');
        }
      }
    } catch (_) {
      if (!mounted || requestGeneration != _recordGeneration ||
          _game?['id']?.toString() != gameId) return;
      // Un timeout no significa que el servidor haya rechazado la jugada.
      // Reconciliar contra el historial persistido antes de sugerir reintento.
      setState(() { _uncertainPlay = true; _scoringMessage =
          'Verificando si la jugada llegó al servidor…'; });
      try {
        final rows = await _client.from('swl_game_events')
            .select('actor_id,event_type,version')
            .eq('game_id', gameId)
            .eq('version', version + 1)
            .limit(1)
            .timeout(const Duration(seconds: 8));
        if (!mounted || requestGeneration != _recordGeneration ||
            _game?['id']?.toString() != gameId) return;
        final recorded = rows.isNotEmpty &&
            rows.first['actor_id']?.toString() == userId &&
            rows.first['event_type']?.toString() == action;
        setState(() { _uncertainPlay = !recorded; _scoringMessage = recorded
            ? 'La jugada sí fue registrada. Marcador actualizado.'
            : rows.isNotEmpty
                ? 'El partido cambió desde otro dispositivo. Revisa el marcador antes de anotar.'
                : 'No se pudo confirmar el resultado. Anotación bloqueada hasta revisar el historial.'; });
      } catch (_) {
        if (mounted && requestGeneration == _recordGeneration &&
            _game?['id']?.toString() == gameId) {
          setState(() => _scoringMessage =
              'Conexión incierta: anotación bloqueada hasta revisar el historial.');
        }
      }
      await _refreshGame();
      await _loadRecentEvents();
      await _loadBattingStats();
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
          _refreshGame();
          _loadBattingStats();
          _loadSubstitutionHistory();
        },
      ).subscribe();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      // La recepción de un evento Realtime no garantiza que la conexión
      // continúe activa. La consulta periódica permite detectar cortes.
      _refreshGame();
      _loadSavedLineups();
      _loadBattingStats();
      // Respaldo por polling si se pierde un mensaje Realtime.
      _loadSubstitutionHistory();
    });
  }

  void _stopWatching() {
    _watchGeneration++;
    _lineupsGeneration++;
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
    _substitutionUncertain = false;
    _confirmingPlay = false;
    _refreshing = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshQueued = false;
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
      final rows = await _client.from('teams').select('id,name,province')
          .inFilter('id', [game['home_team_id'], game['away_team_id']]);
      if (!mounted || _game?['id'] != game['id']) return;
      setState(() {
        for (final row in rows) {
          final id = row['id']?.toString();
          final name = row['name']?.toString();
          if (id != null && name != null) _teamNames[id] = name;
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
                subtitle: Text('ID: ${player.universalId.isEmpty ? player.playerId : player.universalId} · ${player.position}${player.isRefuerzo ? ' · Refuerzo' : ''}'),
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
  Future<void> _draftLineup(String teamId, String teamName) async {
    final game = _game;
    if (game == null || teamId.isEmpty) return;
    final myId = _client.auth.currentUser?.id;
    final isHome = game['home_team_id']?.toString() == teamId;
    final isAway = game['away_team_id']?.toString() == teamId;
    final managerId = isHome ? game['home_manager_id'] :
        (isAway ? game['away_manager_id'] : null);
    if (myId == null || managerId?.toString() != myId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Solo el mánager de este equipo puede preparar su alineación.')));
      return;
    }
    try {
      final players = await SwlRosterRepository(_client).activePlayers(teamId)
          .timeout(const Duration(seconds: 12));
      if (!mounted || _game?['id'] != game['id']) return;
      final selected = <SwlRosterPlayer>[];
      final loadedLineup = _savedLineups.where(
          (row) => row['team_id']?.toString() == teamId);
      final expectedRevision = loadedLineup.isEmpty
          ? 0
          : (loadedLineup.first['revision'] as num?)?.toInt() ?? 0;
      final existing = _savedLineups.where((row) => row['team_id']?.toString() == teamId);
      if (existing.isNotEmpty && existing.first['lineup'] is List) {
        final slots = List<dynamic>.from(existing.first['lineup'] as List);
        slots.sort((a, b) => ((a as Map)['order'] as num).compareTo((b as Map)['order'] as num));
        final byId = {for (final player in players) player.playerId: player};
        for (final slot in slots) {
          if (slot is! Map) continue;
          final player = byId[slot['player_id']?.toString()];
          if (player != null) selected.add(player);
        }
      }
      await showDialog<void>(context: context, builder: (dialogContext) =>
        StatefulBuilder(builder: (context, update) => AlertDialog(
          title: Text('Alineación · $teamName'),
          content: SizedBox(width: 450, height: 420, child: Column(children: [
            Text('Orden al bate: ${selected.length}/13 · Mínimo 9 jugadores',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('El guardado valida los peloteros en Supabase LAB.',
              style: TextStyle(fontSize: 12)),
            const Text('Por seguridad, la alineación queda bloqueada al registrar la primera jugada de un bateador. Las sustituciones durante el partido aún no están habilitadas.',
              style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
            const Divider(),
            Expanded(child: ListView(children: [
              for (final player in players) CheckboxListTile(
                dense: true,
                value: selected.any((p) => p.playerId == player.playerId),
                title: Text('${player.name} · #${player.number}'),
                subtitle: Text('${player.position} · ${player.universalId}'),
                onChanged: (checked) => update(() {
                  selected.removeWhere((p) => p.playerId == player.playerId);
                  if (checked == true && selected.length < 13) selected.add(player);
                }),
              ),
            ])),
            if (selected.isNotEmpty) SizedBox(height: 120,
              child: ReorderableListView.builder(
                itemCount: selected.length,
                onReorder: (oldIndex, newIndex) => update(() {
                  if (newIndex > oldIndex) newIndex--;
                  selected.insert(newIndex, selected.removeAt(oldIndex));
                }),
                itemBuilder: (context, index) => ListTile(
                  key: ValueKey(selected[index].playerId),
                  dense: true,
                  leading: Text('${index + 1}'),
                  title: Text(selected[index].name),
                  trailing: const Icon(Icons.drag_handle),
                ),
              ),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CERRAR')),
            TextButton(
              onPressed: selected.length >= 9 && selected.length <= 13
                ? () async {
                    final ids = selected.map((p) => p.playerId).toList();
                    Navigator.pop(dialogContext);
                    try {
                      await _client.rpc('swl_v53_save_lineup_checked', params: {
                        'p_game_id': game['id'],
                        'p_team_id': teamId,
                        'p_player_ids': ids,
                        'p_expected_revision': expectedRevision,
                      }).timeout(const Duration(seconds: 12));
                      if (!mounted || _game?['id'] != game['id']) return;
                      await _loadSavedLineups();
                      if (!mounted || _game?['id'] != game['id']) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                        content: Text('Alineación guardada en LAB: ${ids.length} bateadores.')));
                    } catch (e) {
                      if (!mounted || _game?['id'] != game['id']) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                        content: Text(e.toString().contains('LINEUP_LOCKED_AFTER_FIRST_PLATE_ACTION')
                            ? 'Alineación bloqueada: ya comenzó el bateo. Las sustituciones durante el partido estarán disponibles en una próxima versión.'
                            : 'No se pudo confirmar la alineación. Comprueba la conexión y vuelve a consultar antes de reintentar: $e')));
                    }
                  }
                : null,
              child: const Text('GUARDAR EN LAB')),
          ],
        )));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo preparar la alineación: $e')));
    }
  }

  /// Sustitución de bateador: el servidor valida y registra el cambio atómicamente.
  Future<void> _substituteBatter(String teamId, String teamName) async {
    final game = _game;
    if (game == null || teamId.isEmpty || _recording || _confirmingPlay ||
        _uncertainPlay || _substitutionPending || _substitutionUncertain) return;
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
    final slots = List<dynamic>.from(saved['lineup'] as List);
    slots.sort((a, b) => ((a as Map)['order'] as num)
        .compareTo((b as Map)['order'] as num));
    setState(() => _substitutionPending = true);
    try {
      final roster = await SwlRosterRepository(_client).activePlayers(teamId)
          .timeout(const Duration(seconds: 12));
      if (!mounted || _game?['id']?.toString() != gameId) return;
      final currentIds = slots.whereType<Map>()
          .map((slot) => slot['player_id']?.toString()).toSet();
      final available = roster.where((p) => !currentIds.contains(p.playerId)).toList();
      if (available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No hay peloteros disponibles fuera de la alineación.')));
        return;
      }
      int order = 1;
      String? incomingId = available.first.playerId;
      final confirmed = await showDialog<bool>(
        context: context,
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
                          '${_lineupPlayerNames[(slots[i] as Map)['player_id']?.toString()] ?? "Pelotero"}',
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
      final outgoingId = (slots[order - 1] as Map)['player_id']?.toString();
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
            for (final slot in slots.whereType<Map>())
              (slot['order'] as num).toInt(): slot['player_id'].toString(),
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
      final latestVersion = (_game?['version'] as num?)?.toInt();
      if (latestVersion == null) return;
      // Una respuesta perdida puede significar que el servidor SI confirmó
      // el cambio. No permitir otro intento hasta reconciliar el estado.
      var rpcStarted = false;
      try {
        rpcStarted = true;
        await _client.rpc('swl_v53_substitute_batter', params: {
        'p_game_id': gameId,
        'p_team_id': teamId,
        'p_batting_order': order,
        'p_outgoing_id': outgoingId,
        'p_incoming_id': incomingId,
        'p_expected_revision': revision,
        'p_expected_game_version': latestVersion,
        }).timeout(const Duration(seconds: 12));
      } catch (e) {
        // Un rechazo explicito de PostgREST confirma que la operacion fallo.
        // Solo una perdida de respuesta (red/timeout) deja resultado incierto.
        final serverRejected = e is PostgrestException;
        if (rpcStarted && !serverRejected && mounted &&
            _game?['id']?.toString() == gameId) {
          setState(() => _substitutionUncertain = true);
        }
        rethrow;
      }
      if (mounted) setState(() => _substitutionUncertain = false);
      if (!mounted || _game?['id']?.toString() != gameId) return;
      await _loadSavedLineups();
      await _refreshGame();
      await _loadSubstitutionHistory();
      await _loadBattingStats();
      if (!mounted || _game?['id']?.toString() != gameId) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sustitución confirmada en LAB.')));
    } catch (e) {
      if (!mounted || _game?['id']?.toString() != gameId) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se confirmó la sustitución. '
            'Actualiza el partido antes de reintentar: $e')));
    } finally {
      if (mounted && _game?['id']?.toString() == gameId) {
        setState(() => _substitutionPending = false);
      }
    }
  }

  Widget _gameView() {
    final game = _game!;
    final connected = game['home_manager_id'] != null && game['away_manager_id'] != null;
    final top = game['is_top'] != false;
    final inning = game['inning'] ?? 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectableText('PIN: ${game['game_pin']}',
          style: const TextStyle(color: Colors.amber, fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Text('HOME CLUB: ${_name(game['home_team_id'])}',
          style: const TextStyle(color: Colors.white)),
      Text('VISITANTE: ${_name(game['away_team_id'])}',
          style: const TextStyle(color: Colors.white)),
      Wrap(spacing: 8, children: [
        OutlinedButton(onPressed: () => _showActiveRoster(
          game['home_team_id']?.toString() ?? '', _name(game['home_team_id'])),
          child: const Text('VER ROSTER LOCAL')),
        OutlinedButton(onPressed: () => _showActiveRoster(
          game['away_team_id']?.toString() ?? '', _name(game['away_team_id'])),
          child: const Text('VER ROSTER VISITANTE')),
        OutlinedButton(onPressed: () => _draftLineup(
          game['home_team_id']?.toString() ?? '', _name(game['home_team_id'])),
          child: const Text('EDITAR ALINEACIÓN LOCAL')),
        OutlinedButton(onPressed: () => _draftLineup(
          game['away_team_id']?.toString() ?? '', _name(game['away_team_id'])),
          child: const Text('EDITAR ALINEACIÓN VISITANTE')),
        OutlinedButton(onPressed: _substitutionPending || _substitutionUncertain ||
          _recording || _confirmingPlay || _uncertainPlay ? null : () => _substituteBatter(
          game['home_team_id']?.toString() ?? '', _name(game['home_team_id'])),
          child: const Text('SUSTITUIR LOCAL')),
        OutlinedButton(onPressed: _substitutionPending || _substitutionUncertain ||
          _recording || _confirmingPlay || _uncertainPlay ? null : () => _substituteBatter(
          game['away_team_id']?.toString() ?? '', _name(game['away_team_id'])),
          child: const Text('SUSTITUIR VISITANTE')),
      ]),
      _lineupStatus(game['home_team_id']?.toString() ?? '', 'Alineación local'),
      _lineupStatus(game['away_team_id']?.toString() ?? '', 'Alineación visitante'),
      if (_lineupsLoading) const LinearProgressIndicator(),
      if (_lineupsError != null) Text(_lineupsError!,
          style: const TextStyle(color: Colors.orangeAccent)),
      TextButton.icon(onPressed: _loadSavedLineups,
          icon: const Icon(Icons.sync), child: const Text('ACTUALIZAR ALINEACIONES')),
      const SizedBox(height: 14),
      if (!connected)
        const Text('Esperando al mánager visitante…',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))
      else ...[
        const Text('¡Ambos mánagers están vinculados!',
            style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        const Text('PARTIDO COMPARTIDO · LAB',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 19)),
        const SizedBox(height: 12),
        Card(color: const Color(0xFF162131), child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(_name(game['away_team_id']), style: const TextStyle(color: Colors.white))),
              Text('${game['away_runs'] ?? 0}', style: const TextStyle(color: Colors.amber, fontSize: 24)),
            ]),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(_name(game['home_team_id']), style: const TextStyle(color: Colors.white))),
              Text('${game['home_runs'] ?? 0}', style: const TextStyle(color: Colors.amber, fontSize: 24)),
            ]),
            _inningAudit(game),
            const SizedBox(height: 12),
            Text('ENTRADA $inning · ${top ? 'ALTA' : 'BAJA'} · '
                '${top ? 'Batea el visitante' : 'Batea el local'}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            Text('HITS  ${game['away_hits'] ?? 0} – ${game['home_hits'] ?? 0}   '
                'ERRORES  ${game['away_errors'] ?? 0} – ${game['home_errors'] ?? 0}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('Bolas: ${game['balls'] ?? 0}  ·  '
                'Strikes: ${game['strikes'] ?? 0}  ·  '
                'Outs: ${game['outs'] ?? 0}',
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 6, alignment: WrapAlignment.center,
              children: [
                _baseLabel('1B', _baseOccupied(game, 'first')),
                _baseLabel('2B', _baseOccupied(game, 'second')),
                _baseLabel('3B', _baseOccupied(game, 'third')),
              ]),
            const SizedBox(height: 8),
            Text('Estado: ${game['status'] ?? 'SCHEDULED'}  ·  '
                'Versión: ${game['version'] ?? 0}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        )),
      ],
      const SizedBox(height: 12),
      if (_connectionWarning != null)
        Text(_connectionWarning!,
            style: const TextStyle(color: Colors.orangeAccent)),
      if (_lastSuccessfulRefresh != null)
        Text('Última actualización recibida: '
            '${TimeOfDay.fromDateTime(_lastSuccessfulRefresh!).format(context)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 16),
      if (_scoringBackendReady &&
          (_client.auth.currentUser?.id == game['home_manager_id']?.toString() ||
           _client.auth.currentUser?.id == game['away_manager_id']?.toString())) ...[
        Text('PRUEBA LAB · ${_client.auth.currentUser?.id == game['home_manager_id']?.toString() ? 'MÁNAGER LOCAL' : 'MÁNAGER VISITANTE'} · NO BOX SCORE',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        Wrap(spacing: 8, children: [
          for (final action in ['BALL', 'STRIKE', 'OUT'])
            ElevatedButton(
              onPressed: _recording || _confirmingPlay || _uncertainPlay ||
                _substitutionPending || _substitutionUncertain ||
                game['home_manager_id'] == null || game['away_manager_id'] == null ||
                game['status'] == 'FINAL' || game['status'] == 'OFFICIAL'
                ? null : () => _recordPlay(action),
              child: Text(action),
            ),
        ]),
        ElevatedButton.icon(
          icon: const Icon(Icons.sports_baseball),
          label: const Text('HIT / JONRÓN CON CORREDORES'),
          onPressed: _recording || _confirmingPlay || _uncertainPlay ||
            _substitutionPending || _substitutionUncertain ||
              game['home_manager_id'] == null || game['away_manager_id'] == null ||
              game['status'] == 'FINAL' || game['status'] == 'OFFICIAL'
              ? null : _showHitDialog,
        ),
        const Text('Prueba LAB: solo se permiten jugadas vinculadas al bateador. La cuarta BALL registra boleto y el tercer STRIKE ponche. Las estadísticas siguen siendo preliminares; no usar como box score oficial.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
        if (_substitutionUncertain)
          ListTile(
            title: const Text('Sustitución sin confirmación de red',
                style: TextStyle(color: Colors.orangeAccent)),
            subtitle: const Text('No repitas el cambio. Consulta el estado '
                'del servidor para comprobar si fue aplicado.'),
            trailing: FilledButton(
              onPressed: _substitutionPending ? null : () async {
                try {
                  final gameId = _game?['id']?.toString();
                  if (gameId == null) return;
                  // Lecturas directas: los métodos de refresco normales capturan
                  // sus errores y por sí solos no prueban una reconciliación.
                  final latestGame = await _client.from('swl_live_games')
                      .select('version').eq('id', gameId).single()
                      .timeout(const Duration(seconds: 12));
                  await _client.from('swl_game_lineups')
                      .select('team_id,revision').eq('game_id', gameId)
                      .timeout(const Duration(seconds: 12));
                  if (!mounted || _game?['id']?.toString() != gameId) return;
                  await _refreshGame();
                  await _loadSavedLineups();
                  await _loadSubstitutionHistory();
                  if (!mounted || _game?['id']?.toString() != gameId) return;
                  if (_connectionWarning != null ||
                      (_game?['version'] as num?)?.toInt() !=
                      (latestGame['version'] as num?)?.toInt()) {
                    throw StateError('El estado local aún no está actualizado.');
                  }
                  setState(() => _substitutionUncertain = false);
                } catch (_) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No se pudo reconciliar el cambio.')));
                }
              },
              child: const Text('VERIFICAR'),
            ),
          ),
        if (_uncertainPlay)
          OutlinedButton.icon(
            icon: const Icon(Icons.fact_check),
            label: const Text('REVISAR Y DESBLOQUEAR ANOTACIÓN'),
            onPressed: _recording ? null : () async {
              await _refreshGame();
              await _loadRecentEvents();
              if (!mounted || !_uncertainPlay) return;
              final reviewed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Resultado no confirmado'),
                  content: const Text(
                    'Antes de continuar, verifica el marcador y el historial '
                    'en ambos dispositivos. No repitas la jugada anterior '
                    'sin comprobar si se registró. ¿Ya lo verificaste?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('MANTENER BLOQUEO')),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('YA VERIFIQUÉ')),
                  ],
                ),
              );
              if (mounted && reviewed == true) {
                setState(() {
                  _uncertainPlay = false;
                  _scoringMessage = 'Bloqueo retirado tras revisión manual.';
                });
              }
            },
          ),
        if (_recording) const LinearProgressIndicator(),
        if (_scoringMessage != null)
          Text(_scoringMessage!, style: const TextStyle(color: Colors.amber)),
      ],
      if (!_scoringBackendReady)
        const Text('Modo de conexión y visualización. La anotación sincronizada todavía no está habilitada.', 
          style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: _refreshGame,
          icon: const Icon(Icons.refresh), label: const Text('ACTUALIZAR ESTADO')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _eventsLoading ? null : _loadRecentEvents,
        icon: const Icon(Icons.history),
        label: const Text('CONSULTAR ÚLTIMAS JUGADAS'),
      ),
      if (_eventsLoading) const LinearProgressIndicator(),
      if (_eventsError != null)
        Text(_eventsError!, style: const TextStyle(color: Colors.orangeAccent)),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _battingStatsLoading ? null : _loadBattingStats,
        icon: const Icon(Icons.query_stats),
        label: const Text('ESTADÍSTICAS POR PELOTERO · PRELIMINARES'),
      ),
      if (_battingStatsLoading) const LinearProgressIndicator(),
      if (_battingStatsError != null)
        Text(_battingStatsError!,
            style: const TextStyle(color: Colors.orangeAccent)),
      if (!_battingStatsLoading && _battingStats.isEmpty &&
          _battingStatsError == null)
        const Text('Sin estadísticas individuales registradas todavía.',
            style: TextStyle(color: Colors.white70)),
      if (_battingStats.isNotEmpty) _battingBoxScore(game),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _substitutionHistoryLoading ? null : _loadSubstitutionHistory,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('CONSULTAR TODAS LAS SUSTITUCIONES'),
      ),
      if (_substitutionHistoryLoading) const LinearProgressIndicator(),
      if (_substitutionHistoryError != null)
        Text(_substitutionHistoryError!,
            style: const TextStyle(color: Colors.orangeAccent)),
      if (_substitutionHistoryTruncated)
        const Text('Solo se muestran las 500 sustituciones más recientes.',
            style: TextStyle(color: Colors.orangeAccent)),
      for (final event in _substitutionHistory)
        ListTile(
          dense: true,
          title: Text(_eventDescription(event),
              style: const TextStyle(color: Colors.white)),
          subtitle: Text('Entrada ${event['inning'] ?? '?'} · '
              'Versión ${event['version'] ?? '?'}',
              style: const TextStyle(color: Colors.white70)),
        ),
      if (_recentEvents.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('HISTORIAL REGISTRADO',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        ..._recentEvents.map((event) => ListTile(
          dense: true,
          title: Text(_eventDescription(event),
              style: const TextStyle(color: Colors.white)),
          subtitle: Text('Entrada ${event['inning'] ?? '?'} · '
              '${event['is_top'] == true ? 'Alta' : 'Baja'} · '
              'Versión ${event['version'] ?? '?'}',
              style: const TextStyle(color: Colors.white70)),
        )),
      ],
      if (_eventsQueried && _recentEvents.isEmpty && !_eventsLoading && _eventsError == null)
        const Text('Sin jugadas consultadas o registradas.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      TextButton(onPressed: () {
        _stopWatching();
        setState(() {
          _game = null;
          _away = null;
          _teamNames.clear();
          _error = null;
          _connectionWarning = null;
          _lastSuccessfulRefresh = null;
          _recentEvents = [];
        _substitutionHistory = [];
        _substitutionHistoryGeneration++;
        _substitutionHistoryLoading = false;
        _substitutionHistoryQueued = false;
        _substitutionHistoryTruncated = false;
        _substitutionHistoryError = null;
          _battingStats = [];
          _eventsError = null;
          _eventsQueried = false;
          _eventsRequestGameId = null;
          _eventsRequestGeneration++;
          _recordGeneration++;
          _recording = false;
          _substitutionPending = false;
          _substitutionUncertain = false;
          _scoringMessage = null;
        });
      }, child: const Text('VOLVER AL MENÚ DE CONEXIÓN')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final owned = widget.authorizedTeams;
    final homeId = owned.any((t) => t['id']?.toString() == _homeId) ? _homeId : null;
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(title: const Text('⚾ PARTIDO POR PIN · LAB'),
          backgroundColor: const Color(0xFF162131)),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Conexión real entre mánagers',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 19)),
        const SizedBox(height: 8),
        const Text('Partido compartido en LAB. Anotación experimental; faltan pruebas completas en dispositivos.',
            style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 24),
        if (_game != null) _gameView() else ...[
          const Text('CREAR PARTIDO COMO HOME CLUB',
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
          TextField(
            controller: _teamSearch,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Buscar visitante por nombre o provincia',
              prefixIcon: Icon(Icons.search),
              labelStyle: TextStyle(color: Colors.white70)),
            onChanged: _searchTeams,
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_matches.isNotEmpty) ...[
            const SizedBox(height: 6),
            ..._matches.map((t) => ListTile(
              title: Text(t['name']?.toString() ?? 'Equipo',
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(t['province']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white54)),
              onTap: () => setState(() {
                _away = t;
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
              await _loadNames();
            },
            child: const Text('CREAR Y GENERAR PIN'),
          ),
          const Divider(height: 36),
          const Text('UNIRME COMO MÁNAGER VISITANTE',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6)],
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'PIN del partido (6 números)',
              prefixText: 'SWL-',
              prefixStyle: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
              labelStyle: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : () async {
              if (_pin.text.length != 6) {
                setState(() => _error = 'Introduce los 6 números del PIN.');
                return;
              }
              await _run(() => _client.rpc('swl_v5_join_game',
                  params: {'p_game_pin': 'SWL-${_pin.text}'}));
              await _loadNames();
            },
            child: const Text('CONECTARME AL PARTIDO'),
          ),
        ],
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      ]),
    );
  }
}
