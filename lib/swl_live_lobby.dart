import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Primera etapa de V5.1: emparejamiento real. NO registra jugadas.
class SwlLiveLobby extends StatefulWidget {
  final List<Map<String, dynamic>> authorizedTeams;
  const SwlLiveLobby({super.key, required this.authorizedTeams});

  @override
  State<SwlLiveLobby> createState() => _SwlLiveLobbyState();
}

class _SwlLiveLobbyState extends State<SwlLiveLobby> {
  final _pin = TextEditingController();
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _teams = [];
  String? _homeId;
  String? _awayId;
  Map<String, dynamic>? _game;
  RealtimeChannel? _channel;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _homeId = widget.authorizedTeams.isEmpty ? null : widget.authorizedTeams.first['id']?.toString();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    try {
      final rows = await _client.from('teams').select('id,name').order('name');
      if (!mounted) return;
      setState(() => _teams = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los equipos: $e');
    }
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
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo completar la operación: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _subscribe(String id) {
    final old = _channel;
    if (old != null) _client.removeChannel(old);
    _channel = _client.channel('swl-lobby-$id')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'swl_live_games',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
        callback: (payload) {
          if (mounted) setState(() => _game = Map<String, dynamic>.from(payload.newRecord));
        },
      ).subscribe();
  }

  String _teamName(dynamic id) {
    for (final team in _teams) {
      if (team['id']?.toString() == id?.toString()) return team['name']?.toString() ?? 'Equipo';
    }
    return id?.toString() ?? 'Equipo';
  }

  @override
  void dispose() {
    if (_channel != null) _client.removeChannel(_channel!);
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owned = widget.authorizedTeams.where((t) => _teams.any((row) => row['id'].toString() == t['id'].toString())).toList();
    final homeId = owned.any((t) => t['id'].toString() == _homeId) ? _homeId : null;
    final awayId = _teams.any((t) => t['id'].toString() == _awayId && t['id'].toString() != homeId) ? _awayId : null;
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(title: const Text('⚾ PARTIDO POR PIN · LAB'), backgroundColor: const Color(0xFF162131)),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Conexión real entre mánagers', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 19)),
        const SizedBox(height: 8),
        const Text('Primera etapa: crear y unirse al partido. La anotación sincronizada aún no está habilitada.', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 24),
        if (_game == null) ...[
          const Text('CREAR PARTIDO COMO HOME CLUB', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: homeId,
            dropdownColor: const Color(0xFF162131),
            decoration: const InputDecoration(labelText: 'Mi equipo local', labelStyle: TextStyle(color: Colors.white70)),
            items: owned.map((t) => DropdownMenuItem(value: t['id'].toString(), child: Text(t['name']?.toString() ?? 'Equipo', style: const TextStyle(color: Colors.white)))).toList(),
            onChanged: _busy ? null : (v) => setState(() { _homeId = v; if (_awayId == v) _awayId = null; }),
          ),
          DropdownButtonFormField<String>(
            value: awayId,
            dropdownColor: const Color(0xFF162131),
            decoration: const InputDecoration(labelText: 'Equipo visitante', labelStyle: TextStyle(color: Colors.white70)),
            items: _teams.where((t) => t['id'].toString() != homeId).map((t) => DropdownMenuItem(value: t['id'].toString(), child: Text(t['name']?.toString() ?? 'Equipo', style: const TextStyle(color: Colors.white)))).toList(),
            onChanged: _busy ? null : (v) => setState(() => _awayId = v),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy || homeId == null || awayId == null ? null : () => _run(() => _client.rpc('swl_v5_create_game', params: {'p_home_team_id': homeId, 'p_away_team_id': awayId})),
            child: const Text('CREAR Y GENERAR PIN'),
          ),
          const Divider(height: 36),
          const Text('UNIRME COMO MÁNAGER VISITANTE', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          TextField(
            controller: _pin,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'PIN (ej. SWL-123456)', labelStyle: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : () => _run(() => _client.rpc('swl_v5_join_game', params: {'p_game_pin': _pin.text.trim().toUpperCase()})),
            child: const Text('CONECTARME AL PARTIDO'),
          ),
        ] else ...[
          SelectableText('PIN: ${_game!['game_pin']}', style: const TextStyle(color: Colors.amber, fontSize: 25, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text('HOME CLUB: ${_teamName(_game!['home_team_id'])}', style: const TextStyle(color: Colors.white)),
          Text('VISITANTE: ${_teamName(_game!['away_team_id'])}', style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          Text(_game!['away_manager_id'] == null ? 'Esperando al mánager visitante…' : '¡Ambos mánagers están vinculados!', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('El equipo visitante bateará primero (1ra ALTA). Aún no se permiten jugadas en este modo.', style: TextStyle(color: Colors.white70)),
          TextButton(onPressed: () { if (_channel != null) _client.removeChannel(_channel!); _channel = null; setState(() => _game = null); }, child: const Text('VOLVER AL MENÚ DE CONEXIÓN')),
        ],
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      ]),
    );
  }
}
