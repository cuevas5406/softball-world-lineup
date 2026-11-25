import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const swlLogoBucket = 'swl-team-logos';

String? swlTeamLogo(Map<String, dynamic>? team) {
  final path = team?['logo_path']?.toString();
  return path != null && path.isNotEmpty
      ? Supabase.instance.client.storage.from(swlLogoBucket).getPublicUrl(path)
      : team?['logo_url']?.toString();
}

Future<List<Map<String, dynamic>>> swlQueryTeams(
  Future<List<Map<String, dynamic>>> Function(String) read,
) async {
  for (final columns in [
    'id,name,province,team_code,logo_path,logo_url',
    'id,name,province,logo_path,logo_url',
    'id,name,province,logo_url',
  ]) {
    try {
      return await read(columns);
    } on PostgrestException catch (error) {
      if (error.code != '42703') rethrow;
    }
  }
  return read('id,name,province');
}

Future<List<Map<String, dynamic>>> swlSearchTeams(
  SupabaseClient client, String term, {String? excludeId}
) async {
  try {
    final rows = await client.rpc('swl_v57_search_teams', params: {
      'p_term': term.trim(), 'p_exclude': excludeId,
    }).timeout(const Duration(seconds: 12));
    return List<Map<String, dynamic>>.from(rows as List);
  } on PostgrestException catch (error) {
    if (error.code != 'PGRST202' && error.code != '42883') rethrow;
  }
  final safe = term.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  final results = await Future.wait([
    for (final column in ['name', 'province'])
      swlQueryTeams((columns) async {
        final query = client.from('teams').select(columns).ilike(column, '%$safe%');
        return await (excludeId == null ? query : query.neq('id', excludeId))
            .order('name').order('id').limit(20).timeout(const Duration(seconds: 12));
      }),
  ]);
  return {for (final result in results) for (final team in result) team['id']: team}
      .values.take(20).toList();
}

class SwlTeamBadge extends StatelessWidget {
  const SwlTeamBadge({super.key, this.url, this.size = 36});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url ?? '');
    final fallback = Icon(
      Icons.shield_outlined,
      color: Colors.amber,
      size: size,
    );
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty)
      return fallback;
    return ClipOval(
      child: Image.network(
        uri.toString(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) => fallback,
      ),
    );
  }
}

class SwlTeamLookup extends StatefulWidget {
  const SwlTeamLookup({
    super.key,
    required this.excludeId,
    required this.onSelection,
  });
  final String excludeId;
  final void Function(String, Map<String, dynamic>?) onSelection;

  @override
  State<SwlTeamLookup> createState() => _SwlTeamLookupState();
}

class _SwlTeamLookupState extends State<SwlTeamLookup> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _request = 0;
  bool _loading = false;
  bool _external = false;
  String? _error;
  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _matches = [];

  void _changed(String value) {
    _debounce?.cancel();
    final request = ++_request;
    final term = value.trim();
    widget.onSelection(_external ? term : '', null);
    setState(() {
      _selected = null;
      _matches = [];
      _error = null;
      _loading = !_external && term.length >= 2;
    });
    if (!_loading) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final rows = await swlSearchTeams(Supabase.instance.client, term, excludeId: widget.excludeId);
        if (!mounted || request != _request) return;
        setState(() => _matches = rows);
      } catch (_) {
        if (mounted && request == _request) {
          setState(
            () => _error =
                'No se pudieron consultar los equipos. Vuelve a intentar.',
          );
        }
      } finally {
        if (mounted && request == _request) setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        title: const Text('Rival externo'),
        value: _external,
        onChanged: (value) {
          _external = value;
          _changed(_controller.text);
        },
      ),
      TextField(
        controller: _controller,
        onChanged: _changed,
        maxLength: 100,
        decoration: InputDecoration(
          labelText: _external
              ? 'Nombre del equipo externo'
              : 'Nombre o código SWL del equipo',
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (_external)
        const ListTile(
          leading: SwlTeamBadge(),
          title: Text('Equipo externo · sin cuenta ni reto'),
        ),
      if (_selected != null)
        ListTile(
          leading: SwlTeamBadge(url: swlTeamLogo(_selected)),
          title: Text('Seleccionado · ${_selected!['name']}'),
        ),
      for (final team in _matches)
        ListTile(
          leading: SwlTeamBadge(url: swlTeamLogo(team)),
          title: Text(team['name']?.toString() ?? 'Equipo'),
          subtitle: Text(
            '${team['province'] ?? 'Localidad sin confirmar'}\n${team['team_code'] ?? team['id']}',
          ),
          onTap: () {
            _controller.text = team['name']?.toString() ?? '';
            setState(() {
              _selected = team;
              _matches = [];
            });
            widget.onSelection(_controller.text, team);
          },
        ),
    ],
  );
}
