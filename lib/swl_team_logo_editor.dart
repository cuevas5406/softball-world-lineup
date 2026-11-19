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
      if (mounted && !_busy)
        setState(() => _message = 'No se pudo consultar el logo.');
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
      final suffix = Random.secure().nextInt(1 << 30).toRadixString(16);
      final path =
          '${widget.teamId}/${DateTime.now().microsecondsSinceEpoch}-$suffix.$type';
      await _client.storage
          .from(swlLogoBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$type'),
          )
          .timeout(const Duration(seconds: 25));
      if (!mounted || _client.auth.currentUser?.id != userId) return;
      await _client
          .rpc(
            'swl_v56_set_team_logo',
            params: {'p_team_id': widget.teamId, 'p_path': path},
          )
          .timeout(const Duration(seconds: 12));
      if (mounted)
        setState(() {
          _url = _client.storage.from(swlLogoBucket).getPublicUrl(path);
          _message = 'Logo actualizado.';
        });
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

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          SwlTeamBadge(url: _url),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _change,
              child: Text(_busy ? 'PROCESANDO…' : 'AGREGAR O CAMBIAR LOGO'),
            ),
          ),
        ],
      ),
      if (_message != null) Text(_message!),
    ],
  );
}
