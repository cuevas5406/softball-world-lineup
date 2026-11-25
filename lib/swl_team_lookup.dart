import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'swl_code_input.dart';

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
  final trimmed = term.trim();
  final suffix = swlCodeSuffix(trimmed);
  final code = RegExp(r'^[0-9]+$').hasMatch(suffix) ? swlCode(suffix) : null;
  try {
    final rows = await client.rpc('swl_v57_search_teams', params: {
      'p_term': code ?? trimmed, 'p_exclude': excludeId,
    }).timeout(const Duration(seconds: 12));
    return List<Map<String, dynamic>>.from(rows as List);
  } on PostgrestException catch (error) {
    if (error.code != 'PGRST202' && error.code != '42883') rethrow;
  }
  if (code != null) {
    try {
      final query = client.from('teams')
          .select('id,name,province,team_code')
          .eq('team_code', code);
      return await (excludeId == null ? query : query.neq('id', excludeId))
          .limit(20).timeout(const Duration(seconds: 12));
    } on PostgrestException catch (error) {
      if (error.code != '42703') rethrow;
    }
  }
  final safe = trimmed.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
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

class SwlTeamSearchField extends StatelessWidget {
  const SwlTeamSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.decoration,
    this.byCode = false,
    this.onModeChanged,
    this.style,
    this.maxLength,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final InputDecoration decoration;
  final bool byCode;
  final ValueChanged<bool>? onModeChanged;
  final TextStyle? style;
  final int? maxLength;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    style: style,
    maxLength: maxLength,
    keyboardType: byCode ? TextInputType.number : TextInputType.text,
    inputFormatters: byCode ? const [SwlCodeInputFormatter()] : null,
    decoration: decoration.copyWith(
      labelText: byCode ? 'Código SWL del equipo' : decoration.labelText,
      prefixText: byCode ? swlCodePrefix : null,
      floatingLabelBehavior: byCode ? FloatingLabelBehavior.always : null,
      suffixIcon: onModeChanged == null ? null : IconButton(
        tooltip: byCode ? 'Buscar por nombre o localidad' : 'Buscar por código SWL',
        icon: Icon(byCode ? Icons.search : Icons.numbers),
        onPressed: () => onModeChanged!(!byCode),
      ),
    ),
  );
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
  bool _byCode = false;
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
          if (_byCode && value) _controller.clear();
          _byCode = false;
          _changed(_controller.text);
        },
      ),
      SwlTeamSearchField(
        controller: _controller,
        byCode: _byCode,
        onModeChanged: _external ? null : (value) {
          _byCode = value;
          _controller.clear();
          _changed('');
        },
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
              _byCode = false;
              _selected = team;
              _matches = [];
            });
            widget.onSelection(_controller.text, team);
          },
        ),
    ],
  );
}
