import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// V5.2: emparejamiento real, consulta del partido y reconexión.
/// La anotación sincronizada todavía NO está habilitada.
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
  Map<String, dynamic>? _game;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  Timer? _searchTimer;
  bool _busy = false;
  bool _searching = false;
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
        if (!mounted || _teamSearch.text.trim() != term.trim()) return;
        setState(() {
          _matches = List<Map<String, dynamic>>.from(rows)
              .where((t) => t['id'].toString() != _homeId).toList();
          _searching = false;
        });
      } catch (e) {
        if (mounted) setState(() { _searching = false; _error = 'Error buscando equipos: $e'; });
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
      setState(() => _game = game);
      _subscribe(game['id'].toString());
      await _refreshGame();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo completar la operación: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshGame() async {
    final id = _game?['id']?.toString();
    if (id == null || !mounted) return;
    try {
      final row = await _client.from('swl_live_games').select().eq('id', id).single();
      if (mounted && _game?['id']?.toString() == id) {
        setState(() => _game = Map<String, dynamic>.from(row));
      }
    } catch (_) {
      // Una interrupción de red no debe cerrar el partido ni borrar el PIN.
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
          if (mounted && _game?['id']?.toString() == id) {
            setState(() => _game = Map<String, dynamic>.from(payload.newRecord));
          }
        },
      ).subscribe();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshGame());
  }

  void _stopWatching() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final old = _channel;
    _channel = null;
    if (old != null) _client.removeChannel(old);
  }

  String _name(dynamic id) {
    final key = id?.toString();
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
      for (final row in rows) {
        if (row['id'] == game['away_team_id']) {
          setState(() => _away = Map<String, dynamic>.from(row));
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopWatching();
    _searchTimer?.cancel();
    _pin.dispose();
    _teamSearch.dispose();
    super.dispose();
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
            const SizedBox(height: 12),
            Text('${inning}ra ${top ? 'ALTA' : 'BAJA'} · ${top ? 'Batea el visitante' : 'Batea el local'}',
                style: const TextStyle(color: Colors.white70)),
          ]),
        )),
      ],
      const SizedBox(height: 16),
      const Text('Modo de conexión y visualización. La anotación sincronizada todavía no está habilitada.',
          style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: _refreshGame,
          icon: const Icon(Icons.refresh), label: const Text('ACTUALIZAR ESTADO')),
      TextButton(onPressed: () {
        _stopWatching();
        setState(() { _game = null; _away = null; _error = null; });
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
        const Text('Partido compartido en LAB. Las jugadas en vivo se habilitarán en una etapa posterior.',
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
