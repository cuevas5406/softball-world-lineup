import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'swl_team_logo_editor.dart';

class SwlTeamSettings extends StatefulWidget {
  const SwlTeamSettings({
    super.key,
    required this.teamId,
    required this.name,
    required this.province,
  });

  final String teamId;
  final String name;
  final String province;

  @override
  State<SwlTeamSettings> createState() => _SwlTeamSettingsState();
}

class _SwlTeamSettingsState extends State<SwlTeamSettings> {
  static const _fields = <String, (String, int)>{
    'name': ('Nombre del equipo', 100),
    'province': ('Localidad', 100),
    'primary_color': ('Color principal (#RRGGBB)', 7),
    'secondary_color': ('Color secundario (#RRGGBB)', 7),
    'delegate': ('Delegado o representante', 100),
    'contact': ('Contacto administrativo', 150),
  };
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  int? _revision;
  bool _loading = false;
  bool _saving = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in _fields.keys)
        field: TextEditingController(
          text: switch (field) {
            'name' => widget.name,
            'province' => widget.province,
            _ => '',
          },
        ),
    };
    _read();
  }

  Future<void> _read() async {
    setState(() {
      _loading = true;
      _notice = null;
    });
    try {
      final result = await Supabase.instance.client
          .rpc('swl_v57_team_settings', params: {'p_team_id': widget.teamId})
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      for (final entry in _controllers.entries) {
        entry.value.text = result[entry.key]?.toString() ?? '';
      }
      setState(() => _revision = (result['revision'] as num).toInt());
    } catch (error) {
      if (mounted)
        setState(
          () =>
              _notice = error is PostgrestException && error.code == 'PGRST202'
              ? 'La edición de datos y colores requiere habilitar la función en LAB.'
              : 'No se pudo consultar la configuración del equipo.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_revision == null || !_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    final values = {
      for (final entry in _controllers.entries)
        entry.key: entry.key.endsWith('_color')
            ? entry.value.text.trim().toUpperCase()
            : entry.value.text.trim(),
    };
    try {
      await Supabase.instance.client
          .rpc(
            'swl_v57_update_team_settings',
            params: {
              'p_team_id': widget.teamId,
              'p_expected_revision': _revision,
              'p_data': values,
            },
          )
          .timeout(const Duration(seconds: 12));
      if (mounted) Navigator.pop(context, values);
    } catch (error) {
      if (mounted)
        setState(
          () => _notice = error is PostgrestException ? error.message : 'No se confirmó el guardado. Comprueba la configuración antes de reintentar.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(
        title: const Text('Configuración del equipo'),
        backgroundColor: const Color(0xFF0F1722),
        actions: [
          if (!_loading && !_saving && _revision == null)
            IconButton(
              onPressed: _read,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwlTeamLogoEditor(teamId: widget.teamId),
              const SizedBox(height: 16),
              for (final entry in _fields.entries)
                TextFormField(
                  controller: _controllers[entry.key],
                  enabled: _revision != null && !_saving,
                  maxLength: entry.value.$2,
                  decoration: InputDecoration(labelText: entry.value.$1),
                  validator: (raw) {
                    final value = raw?.trim() ?? '';
                    if (entry.key == 'name' && value.isEmpty)
                      return 'Indica el nombre del equipo.';
                    if (entry.key.endsWith('_color') &&
                        value.isNotEmpty &&
                        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value))
                      return 'Usa el formato #RRGGBB.';
                    return null;
                  },
                ),
              if (_notice != null)
                Text(
                  _notice!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              if (_revision != null)
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'GUARDANDO…' : 'GUARDAR CONFIGURACIÓN'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
