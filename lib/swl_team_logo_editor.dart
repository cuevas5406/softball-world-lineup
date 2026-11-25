import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'swl_team_lookup.dart';

String? swlLogoType(Uint8List bytes) {
  if (bytes.length >= 8 &&
      [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ].asMap().entries.every((e) => bytes[e.key] == e.value)) {
    return 'png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255)
    return 'jpeg';
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP')
    return 'webp';
  return null;
}

class SwlTeamLogoEditor extends StatefulWidget {
  const SwlTeamLogoEditor({super.key, required this.teamId});
  final String teamId;

  @override
  State<SwlTeamLogoEditor> createState() => _SwlTeamLogoEditorState();
}

class _SwlTeamLogoEditorState extends State<SwlTeamLogoEditor> {
  final _client = Supabase.instance.client;
  static const _maxBytes = 2 * 1024 * 1024;
  String? _url;
  String? _message;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final team = await swlQueryTeams(
        (columns) async => await _client
            .from('teams')
            .select(columns)
            .eq('id', widget.teamId)
            .timeout(const Duration(seconds: 12)),
      );
      if (mounted && !_busy)
        setState(() => _url = swlTeamLogo(team.firstOrNull));
    } catch (_) {
      if (mounted) setState(() => _message = 'No se pudo consultar el logo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _change() async {
    if (_busy) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final allowed = await _client
          .rpc('swl_can_manage_roster', params: {'p_team_id': widget.teamId})
          .timeout(const Duration(seconds: 12));
      if (allowed != true)
        throw StateError('Solo el mánager autorizado puede cambiar el logo.');
      final bucket = await _client
          .rpc('swl_v56_team_logo_bucket', params: {'p_team_id': widget.teamId})
          .timeout(const Duration(seconds: 12));
      if (bucket != swlLogoBucket)
        throw StateError('El almacenamiento de logos no está habilitado.');
      if (!mounted) return;
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null || !mounted) return;
      if (await image.length() > _maxBytes)
        throw StateError('Selecciona una imagen de hasta 2 MB.');
      final bytes = await image.readAsBytes();
      final type = swlLogoType(bytes);
      if (type == null || bytes.length > _maxBytes) {
        throw StateError('Usa PNG, JPEG o WebP de hasta 2 MB.');
      }
      final decoded = await decodeImageFromList(bytes);
      final valid = decoded.width <= 1600 && decoded.height <= 1600;
      decoded.dispose();
      if (!valid)
        throw StateError('El logo debe tener hasta 1600 píxeles por lado.');
      if (!mounted || _client.auth.currentUser?.id != userId) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Vista previa del logo'),
          content: Image.memory(bytes, width: 240, height: 240, fit: BoxFit.contain),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Guardar logo')),
          ],
        ),
      );
      if (accepted != true || !mounted || _client.auth.currentUser?.id != userId) return;
      final suffix = Random.secure().nextInt(1 << 30).toRadixString(16);
      final path =
          '${widget.teamId}/${DateTime.now().microsecondsSinceEpoch}-$suffix.$type';
      try {
        await _client.storage
            .from(swlLogoBucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: 'image/$type'),
            )
            .timeout(const Duration(seconds: 25));
      } catch (_) {
        // A timeout may occur after Storage has accepted the object.
        await _tryRemoveUnlinkedLogo(path);
        rethrow;
      }
      if (!mounted || _client.auth.currentUser?.id != userId) {
        await _tryRemoveUnlinkedLogo(path);
        return;
      }
      Object? saved;
      try {
        saved = await _client.rpc('swl_v57_set_team_logo', params: {
          'p_team_id': widget.teamId, 'p_path': path,
          'p_expected_url': _url, 'p_public_url': _publicUrl(path),
        }).timeout(const Duration(seconds: 12));
      } catch (_) {
        await _tryRemoveUnlinkedLogo(path);
        rethrow;
      }
      final previousUrl = _url;
      if (mounted) setState(() {
        _url = saved as String?;
        _message = 'Logo actualizado.';
      });
      if (previousUrl != saved) await _tryRemovePreviousLogo(previousUrl);
    } catch (error) {
      if (mounted)
        setState(
          () =>
              _message = error is PostgrestException && error.code == 'PGRST202'
              ? 'La carga de logos está pendiente de habilitación en LAB.'
              : 'No se confirmó el logo: $error',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tryRemoveUnlinkedLogo(String path) async {
    try {
      final rows = await _client
          .from('teams')
          .select('logo_url')
          .eq('id', widget.teamId)
          .limit(1)
          .timeout(const Duration(seconds: 8));
      if (rows.length != 1) return;
      if (rows.first['logo_url'] == _publicUrl(path)) return;
      await _client.storage
          .from(swlLogoBucket)
          .remove([path])
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort cleanup; Storage RLS must reject referenced objects.
    }
  }

  Future<void> _tryRemovePreviousLogo(String? oldUrl) async {
    if (oldUrl == null) return;
    final prefix = _publicUrl('${widget.teamId}/');
    if (!oldUrl.startsWith(prefix)) return;
    final path = oldUrl.substring(_publicUrl('').length);
    if (path.isEmpty || path.contains('?') || path.contains('#')) return;
    await _tryRemoveUnlinkedLogo(path);
  }

  String _publicUrl(String path) =>
      _client.storage.from(swlLogoBucket).getPublicUrl(path);

  Future<void> _remove() async {
    if (_busy || _url == null) return;
    setState(() { _busy = true; _message = null; });
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Quitar el logo del equipo'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Quitar logo')),
          ],
        ),
      );
      if (!mounted || accepted != true) return;
      final previousUrl = _url;
      await _client.rpc('swl_v57_set_team_logo', params: {
        'p_team_id': widget.teamId, 'p_path': null,
        'p_expected_url': previousUrl, 'p_public_url': null,
      }).timeout(const Duration(seconds: 12));
      if (mounted) setState(() { _url = null; _message = 'Logo retirado.'; });
      await _tryRemovePreviousLogo(previousUrl);
    } catch (error) {
      if (mounted) setState(() => _message = error is PostgrestException
          ? error.message : 'No se confirmó la eliminación. Sal y vuelve a consultar el equipo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          SwlTeamBadge(url: _url),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: _busy || _loading ? null : _change,
              child: Text(_busy ? 'PROCESANDO…' : 'AGREGAR O CAMBIAR LOGO'),
            ),
          ),
        ],
      ),
      if (_url != null)
        TextButton(onPressed: _busy ? null : _remove, child: const Text('Quitar logo')),
      if (_message != null) Text(_message!),
    ],
  );
}
