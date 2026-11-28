import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'swl_pitching_stats.dart';
import 'swl_team_lookup.dart';

const _brandAsset = 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png';

List<Map<String, dynamic>> swlRows(dynamic data) => data is List
    ? data.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : [];

Future<Map<String, dynamic>> swlReadSpectatorGame(String id) async {
  final client = Supabase.instance.client;
  try {
    final result = await client
        .rpc('swl_v57_spectator_game', params: {'p_game_id': id})
        .timeout(const Duration(seconds: 12));
    if (result is! Map) throw StateError('El partido ya no está disponible.');
    return Map<String, dynamic>.from(result);
  } on PostgrestException catch (error) {
    if (error.code != 'PGRST202' && error.code != '42883') rethrow;
  }

  final game = await client
      .from('swl_live_games')
      .select(
        'id,game_pin,status,created_at,version,inning,swl_finish_reason,'
        'home_team_id,home_runs,home_hits,home_errors,home_innings,'
        'away_team_id,away_runs,away_hits,away_errors,away_innings',
      )
      .eq('id', id)
      .inFilter('status', ['IN_PROGRESS', 'FINAL', 'OFFICIAL', 'CANCELLED'])
      .single()
      .timeout(const Duration(seconds: 12));
  final teams = await swlQueryTeams(
    (columns) async => await client
        .from('teams')
        .select(columns)
        .inFilter('id', [game['home_team_id'], game['away_team_id']])
        .timeout(const Duration(seconds: 12)),
  );
  Map<String, dynamic> team(String side) => {
    'id': game['${side}_team_id'],
    ...?teams.where((row) => row['id'] == game['${side}_team_id']).firstOrNull,
    for (final field in ['runs', 'hits', 'errors', 'innings'])
      field: game['${side}_$field'],
  };
  final result = <String, dynamic>{
    'id': id,
    'code': game['game_pin'],
    'status': game['status'],
    'date': game['created_at'],
    'inning': game['inning'],
    'finish': game['swl_finish_reason'],
    'home': team('home'),
    'away': team('away'),
  };
  if (game['status'] != 'OFFICIAL') return result;
  final ids = <String>{};
  try {
    final totals = await swlLoadPitching(
      client,
      id,
      (game['version'] as num).toInt(),
    );
    if (totals != null && totals.isNotEmpty) {
      result['pitching'] = [
        for (final entry in totals.entries)
          {
            'player_id': entry.key,
            'outs': entry.value.outs,
            'h': entry.value.hits,
            'bb': entry.value.walks,
            'k': entry.value.strikeouts,
          },
      ];
      ids.addAll(totals.keys);
    }
  } on PostgrestException {
    // Se puede compartir el marcador si la estadística no está visible.
  }
  if (ids.isNotEmpty) {
    try {
      final players = await client
          .from('players')
          .select('id,first_name,last_name')
          .inFilter('id', ids.toList())
          .timeout(const Duration(seconds: 12));
      final names = {
        for (final p in players)
          p['id']: "${p['first_name'] ?? ''} ${p['last_name'] ?? ''}".trim(),
      };
      for (final category in ['batting', 'pitching']) {
        if (result[category] case final List rows) {
          for (final row in rows.cast<Map>()) {
            row['name'] = names[row['player_id']];
          }
        }
      }
    } on PostgrestException {
      // Las filas sin nombre confirmado se omiten del documento.
    }
  }
  return result;
}

String _display(Object? value) => value?.toString() ?? '-';

/// Promedio calculado solo con AB y H confirmados; nunca se infiere un cero.
String swlBattingAverage(Map<String, dynamic> row) {
  final ab = row['ab'];
  final hits = row['h'];
  if (ab is! num || hits is! num || ab < 0 || hits < 0 || hits > ab) {
    return '-';
  }
  if (ab == 0) return '.000';
  return (hits / ab).toStringAsFixed(3).replaceFirst('0.', '.');
}

typedef SwlReportTable = ({
  String title,
  List<String> labels,
  List<(String, List<String>)> rows,
});

class SwlOfficialBoxScore {
  SwlOfficialBoxScore(this.data, {this.reports = const {}}) {
    if (data['status'] != 'OFFICIAL')
      throw StateError('El resultado aún requiere las dos firmas.');
  }

  final Map<String, dynamic> data;
  final Map<String, List<SwlReportTable>> reports;
  Map<String, dynamic> side(String key) =>
      Map<String, dynamic>.from(data[key] as Map);
  String get code => _display(data['code']);
  String get date {
    final parsed = DateTime.tryParse(_display(data['date']));
    return parsed == null
        ? '-'
        : DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }

  List<List<List<String>>> get tables {
    final sides = [side('away'), side('home')];
    final count = sides.fold<int>(
      max(1, (data['inning'] as num?)?.toInt() ?? 1),
      (largest, team) => max(largest, (team['innings'] as List?)?.length ?? 0),
    );
    return [
      for (var start = 0; start < count; start += 9)
        [
          [
            'Equipo',
            for (var i = start; i < min(count, start + 9); i++) '${i + 1}',
            'R',
            'H',
            'E',
          ],
          for (final team in sides)
            [
              _display(team['name']),
              for (var i = start; i < min(count, start + 9); i++)
                _display(
                  i < ((team['innings'] as List?)?.length ?? 0)
                      ? (team['innings'] as List)[i]
                      : null,
                ),
              for (final key in ['runs', 'hits', 'errors']) _display(team[key]),
            ],
        ],
    ];
  }

  String get headline =>
      "${side('away')['name']} ${_display(side('away')['runs'])} - ${_display(side('home')['runs'])} ${side('home')['name']}";
  String get detail =>
      '$code · $date · ${data['finish'] ?? 'Resultado oficial'}';

  Iterable<(String, SwlReportTable)> reportSections(String? teamId) sync* {
    for (final key in ['away', 'home']) {
      final team = side(key);
      if (teamId != null && team['id'] != teamId) continue;
      for (final report in reports[team['id']] ?? const <SwlReportTable>[]) {
        yield (_display(team['name']), report);
      }
    }
  }

  Future<Map<String, Uint8List>> _teamLogos() async {
    final entries = await Future.wait(
      ['away', 'home'].map((key) async {
        final url = Uri.tryParse(swlTeamLogo(side(key)) ?? '');
        if (url == null || url.scheme != 'https' || url.host.isEmpty)
          return null;
        try {
          final bytes = await NetworkAssetBundle(url)
              .load(url.toString())
              .timeout(const Duration(seconds: 4));
          if (bytes.lengthInBytes <= 2 * 1024 * 1024) {
            return MapEntry(
              key,
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          }
        } catch (_) {
          // El nombre del equipo sigue disponible.
        }
        return null;
      }),
    );
    return Map.fromEntries(entries.whereType<MapEntry<String, Uint8List>>());
  }

  Future<Uint8List> pdf({String? teamId}) async {
    final doc = pw.Document(
      title: 'Box Score $code',
      author: 'Softball World Lineup',
    );
    final branding = pw.MemoryImage(
      (await rootBundle.load(_brandAsset)).buffer.asUint8List(),
    );
    final teamLogos = await _teamLogos();
    pw.Widget table(List<List<String>> rows) => pw.TableHelper.fromTextArray(
      headers: rows.first,
      data: rows
          .skip(1)
          .map(
            (row) => row
                .map(
                  (cell) =>
                      cell.startsWith('≥') ? 'mín. ${cell.substring(1)}' : cell,
                )
                .toList(),
          )
          .toList(),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.center,
    );
    final batting = swlRows(data['batting'])
        .where((row) => row['name'] != null);
    final pitching = swlRows(data['pitching'])
        .where((row) => row['name'] != null);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(
          base: pw.Font.ttf(
            await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
          ),
          bold: pw.Font.ttf(
            await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
          ),
        ),
        margin: const pw.EdgeInsets.all(28),
        header: (_) =>
            pw.Text('SWL · $code', style: const pw.TextStyle(fontSize: 9)),
        footer: (context) =>
            pw.Text('Softball World Lineup · ${context.pageNumber}'),
        build: (_) => [
          pw.Row(
            children: [
              pw.Image(branding, width: 45),
              pw.SizedBox(width: 12),
              pw.Text(
                'BOX SCORE OFICIAL',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final key in ['away', 'home'])
                if (teamLogos[key] case final Uint8List bytes)
                  pw.Image(
                    pw.MemoryImage(bytes),
                    width: 40,
                    height: 40,
                    fit: pw.BoxFit.contain,
                  ),
            ],
          ),
          pw.Header(level: 0, text: headline),
          pw.Text(detail),
          if (reports.isNotEmpty)
            pw.Text(
              'mín. = mínimo confirmado',
              style: const pw.TextStyle(fontSize: 8),
            ),
          pw.SizedBox(height: 15),
          for (final block in tables) ...[
            table(block),
            pw.SizedBox(height: 10),
          ],
          for (final (team, report) in reportSections(teamId)) ...[
            pw.Header(level: 1, text: '${report.title} · $team'),
            table([
              ['Pelotero', ...report.labels],
              for (final (name, values) in report.rows) [name, ...values],
            ]),
          ],
          if (reports.isEmpty) ...[
            for (final key in ['away', 'home']) ...[
              pw.Header(level: 1, text: 'Bateo · ${side(key)['name']}'),
              if (!batting.any((row) => row['team_id'] == side(key)['id']))
                pw.Text('Estadísticas disponibles insuficientes.')
              else
                table([
                  [
                    'Pelotero',
                    'AB',
                    'R',
                    'H',
                    '2B',
                    '3B',
                    'HR',
                    'RBI',
                    'BB',
                    'K',
                    'AVG',
                  ],
                  for (final row in batting.where(
                    (row) => row['team_id'] == side(key)['id'],
                  ))
                    [
                      for (final col in [
                        'name',
                        'ab',
                        'r',
                        'h',
                        'doubles',
                        'triples',
                        'hr',
                        'rbi',
                        'bb',
                        'k',
                      ])
                        _display(row[col]),
                      swlBattingAverage(row),
                    ],
                ]),
            ],
            pw.Header(level: 1, text: 'Pitcheo'),
            pw.Text(
              'Los registros de pitcheo se muestran sin atribución de equipo '
              'cuando el origen no la proporciona.',
              style: const pw.TextStyle(fontSize: 8),
            ),
            if (pitching.isEmpty)
              pw.Text('Estadísticas disponibles insuficientes.')
            else
              table([
                ['Pitcher', 'Equipo', 'IP', 'H', 'BB', 'K'],
                for (final row in pitching)
                  [
                    _display(row['name']),
                    _display(row['team_name']),
                    if (row['outs'] case final num outs)
                      '${outs ~/ 3}.${outs % 3}'
                    else
                      '-',
                    for (final col in ['h', 'bb', 'k']) _display(row[col]),
                  ],
              ]),
          ],
        ],
      ),
    );
    return doc.save();
  }

  Future<List<Uint8List>> images({
    String? teamId,
    bool scoreboardOnly = false,
  }) async {
    final logos = await _teamLogos();
    final blocks = tables;
    final pages = <(String, List<List<String>>, bool)>[
      for (final block in blocks) ('Pizarra', block, true),
      if (!scoreboardOnly)
        for (final (team, report) in reportSections(teamId))
          for (var start = 0; start < report.rows.length; start += 20)
            (
              '${report.title} · $team',
              [
                ['Pelotero', ...report.labels],
                for (final (name, values) in report.rows.skip(start).take(20))
                  [name, ...values],
              ],
              false,
            ),
    ];
    return [
      for (final (index, page) in pages.indexed)
        await _pngPage(
          page.$1,
          page.$2,
          index + 1,
          pages.length,
          logos,
          [
            side('away'),
            side('home'),
          ].where((side) => side['id'] == teamId).firstOrNull,
        ),
    ];
  }

  Future<Uint8List> png() async => (await images(scoreboardOnly: true)).first;

  Future<Uint8List> _pngPage(
    String title,
    List<List<String>> block,
    int index,
    int total,
    Map<String, Uint8List> logos,
    Map<String, dynamic>? selected,
  ) async {
    const width = 1080;
    const height = 1920;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xff111b2a), BlendMode.src);
    void text(
      String value,
      double x,
      double y,
      double w,
      double size, {
      Color color = Colors.white,
    }) {
      final layout = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: FontWeight.w700,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(minWidth: w, maxWidth: w);
      layout.paint(canvas, Offset(x, y));
      layout.dispose();
    }

    Future<void> logo(Uint8List bytes, Rect target) async {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
      try {
        final frame = await codec.getNextFrame();
        try {
          final image = frame.image;
          final scale = min(
            target.width / image.width,
            target.height / image.height,
          );
          final fitted = Rect.fromCenter(
            center: target.center,
            width: image.width * scale,
            height: image.height * scale,
          );
          canvas.drawImageRect(
            image,
            Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
            fitted,
            Paint()..filterQuality = FilterQuality.medium,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }

    await logo(
      (await rootBundle.load(_brandAsset)).buffer.asUint8List(),
      const Rect.fromLTWH(492, 22, 96, 96),
    );
    for (final (key, x) in [('away', 84.0), ('home', 900.0)]) {
      if (logos[key] case final Uint8List bytes) {
        try {
          await logo(bytes, Rect.fromLTWH(x, 22, 96, 96));
        } catch (_) {
          // El nombre sigue visible si el archivo no es decodificable.
        }
      }
    }
    final hex =
        selected?['primary_color']?.toString().replaceFirst('#', '') ?? '';
    final accentValue = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    final accent = accentValue == null
        ? Colors.amber
        : Color(0xff000000 | accentValue);
    canvas.drawRect(
      const Rect.fromLTWH(24, 157, 1032, 8),
      Paint()..color = accent,
    );
    text('SOFTBALL WORLD LINEUP', 80, 118, 920, 38, color: Colors.amber);
    text('RESULTADO OFICIAL', 80, 193, 920, 31);
    text(headline, 40, 248, 1000, 40);
    text(detail, 40, 314, 1000, 25);
    final caption = selected == null ? title : '${selected['name']} · $title';
    text(caption, 40, 398, 1000, 32, color: Colors.amber);
    final nameWidth = block.first.length > 8 ? 370.0 : 420.0;
    final cell = (1032 - nameWidth) / (block.first.length - 1);
    for (var row = 0; row < block.length; row++) {
      final y = 454.0 + row * 61;
      canvas.drawRect(
        Rect.fromLTWH(24, y, 1032, 58),
        Paint()
          ..color = row == 0
              ? const Color(0xff36516b)
              : row.isEven
              ? const Color(0xff1f3147)
              : const Color(0xff19293c),
      );
      final name = block[row].first;
      final split = name.lastIndexOf(' · #');
      text(
        split < 0
            ? name
            : '${name.substring(split + 3)} · ${name.substring(0, split)}',
        27,
        y + 13,
        nameWidth - 6,
        24,
      );
      for (var column = 1; column < block[row].length; column++) {
        text(
          block[row][column],
          24 + nameWidth + (column - 1) * cell,
          y + 13,
          cell,
          block.first.length > 8 ? 21 : 24,
        );
      }
    }
    text('≥ Mínimo confirmado · — Dato no disponible', 40, 1800, 1000, 24);
    text('$code · $index/$total', 40, 1850, 1000, 28, color: Colors.amber);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('No se pudo renderizar la imagen.');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }
}

class SwlShareBoxScoreButton extends StatefulWidget {
  const SwlShareBoxScoreButton({
    super.key,
    required this.gameId,
    this.loadScore,
    this.ownTeam,
  });
  final Future<SwlOfficialBoxScore> Function()? loadScore;
  final String? ownTeam;
  final String gameId;

  @override
  State<SwlShareBoxScoreButton> createState() => _SwlShareBoxScoreButtonState();
}

class _SwlShareBoxScoreButtonState extends State<SwlShareBoxScoreButton> {
  bool _working = false;

  Future<void> _share() async {
    setState(() => _working = true);
    try {
      final format = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (code, label) in [
                if (widget.ownTeam != null && widget.loadScore != null)
                  ('png-team', 'Imagen de mi equipo'),
                if (widget.loadScore != null) ('png-global', 'Imagen global'),
                ('png-score', 'Imagen del marcador'),
                if (widget.ownTeam != null && widget.loadScore != null)
                  ('pdf-team', 'PDF de mi equipo'),
                ('pdf-global', 'PDF global'),
              ])
                ListTile(
                  title: Text(label),
                  onTap: () => Navigator.pop(sheet, code),
                ),
            ],
          ),
        ),
      );
      if (format == null || !mounted) return;
      final game = widget.loadScore != null
          ? await widget.loadScore!()
          : SwlOfficialBoxScore(await swlReadSpectatorGame(widget.gameId));
      final team = format.endsWith('-team') ? widget.ownTeam : null;
      final png = format.startsWith('png');
      final pages = png
          ? await game.images(
              teamId: team,
              scoreboardOnly: format == 'png-score',
            )
          : [await game.pdf(teamId: team)];
      final cache = await getTemporaryDirectory();
      final directory = await cache.createTemp('swl-box-score-');
      final safeCode = game.code.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final files = [
        for (final (index, bytes) in pages.indexed)
          await File(
            '${directory.path}/Box-Score-$safeCode-${index + 1}.${png ? "png" : "pdf"}',
          ).writeAsBytes(bytes),
      ];
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          title: 'Box Score ${game.code}',
          files: [
            for (final file in files)
              XFile(file.path, mimeType: png ? 'image/png' : 'application/pdf'),
          ],
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo compartir. Verifica que el resultado esté oficializado.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _working ? null : _share,
    icon: const Icon(Icons.share_outlined),
    label: Text(_working ? 'PREPARANDO…' : 'COMPARTIR BOX SCORE'),
  );
}
