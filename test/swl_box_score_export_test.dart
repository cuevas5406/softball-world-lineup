import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_official_box_score.dart';
import '../lib/swl_game_box_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> result({String status = 'OFFICIAL', int inning = 6}) => {
    'status': status,
    'code': 'SWL-000123',
    'inning': inning,
    'date': '2026-11-25T14:00:00Z',
    'away': {
      'id': 'a',
      'name': 'Visitante',
      'runs': 2,
      'hits': 4,
      'errors': 1,
      'innings': [2, 0, 0, 0, 0, 0],
    },
    'home': {
      'id': 'h',
      'name': 'Local',
      'runs': 3,
      'hits': 5,
      'errors': 0,
      'innings': [3, 0, 0, 0, 0, null],
    },
    'batting': [
      {
        'team_id': 'h',
        'name': 'José Pérez',
        'ab': 3,
        'h': 1,
        'hr': 0,
        'bb': 0,
        'k': 0,
        'sf': 1,
      },
    ],
    'pitching': [
      {'name': 'Ana Díaz', 'outs': 16, 'h': 4, 'bb': 2, 'k': 5},
    ],
  };

  test('FINAL y CANCELLED no se pueden exportar como oficiales', () {
    for (final status in ['FINAL', 'IN_PROGRESS', 'CANCELLED']) {
      expect(
        () => SwlOfficialBoxScore(result(status: status)),
        throwsStateError,
      );
    }
  });

  test('Conserva entradas extra, mitad sin jugar y datos ausentes', () {
    final official = SwlOfficialBoxScore(result(inning: 10));
    expect(official.tables.last.first, ['Equipo', '10', 'R', 'H', 'E']);
    expect(official.tables.first.last[6], '-');
    expect(official.tables.first.last[5], '0');
    expect(official.tables.last.last.skip(2), ['3', '5', '0']);
  });

  test('AVG usa hits y turnos oficiales, sin inventar datos ausentes', () {
    expect(swlBattingAverage({'ab': 4, 'h': 1}), '.250');
    expect(swlBattingAverage({'ab': 3, 'h': 2}), '.667');
    expect(swlBattingAverage({'ab': 0, 'h': 0}), '.000');
    expect(swlBattingAverage({'ab': null, 'h': 1}), '-');
    expect(swlBattingAverage({'ab': 2, 'h': 3}), '-');
    expect(swlBattingAverage({'ab': -1, 'h': 0}), '-');
  });

  test('Genera un PDF con estadísticas oficiales', () async {
    final bytes = await SwlOfficialBoxScore(result()).pdf();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  testWidgets('exporta equipo y global con páginas de 1080 × 1920', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await (FontLoader(
        'SwlReport',
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'))).load();
      final sample = result()..['code'] = 'SWL-DEMO';
      sample['finish'] = 'Datos sintéticos de verificación';
      final report = SwlOfficialBoxScore(
        sample,
        reports: {
          for (final team in ['a', 'h'])
            team: [
              (
                title: 'Bateo',
                labels: SwlGameBoxData.battingLabels,
                rows: [
                  for (var i = 0; i < 9; i++)
                    (
                      '${team == 'h' ? 'Local' : 'Visitante'} Gabriel de los Santos Rodríguez ${i + 1} · #${10 + i}',
                      [
                        '3',
                        '3',
                        '0',
                        '1',
                        '0',
                        '0',
                        '0',
                        '0',
                        '0',
                        '0',
                        '0',
                        '.333',
                      ],
                    ),
                  (
                    'Total',
                    [
                      '27',
                      '27',
                      '0',
                      '9',
                      '0',
                      '0',
                      '0',
                      '0',
                      '0',
                      '0',
                      '0',
                      '.333',
                    ],
                  ),
                ],
              ),
              (
                title: 'Pitcheo',
                labels: SwlGameBoxData.pitchingLabels,
                rows: [
                  (
                    'Lanzador de muestra · #1',
                    ['6.0', '4', '3', '≥2', '0', '2', '1', '5', '11', '28'],
                  ),
                  (
                    'Total',
                    ['6.0', '4', '3', '≥2', '0', '2', '1', '5', '11', '28'],
                  ),
                ],
              ),
              (
                title: 'Defensa registrada',
                labels: const ['POS', 'Participación'],
                rows: [
                  ('Pelotero de muestra 1 · #10', ['C', 'Titular']),
                ],
              ),
            ],
        },
      );
      expect(report.reportSections('h').map((e) => e.$1).toSet(), {'Local'});
      expect(report.reportSections(null).map((e) => e.$1).toSet(), {
        'Local',
        'Visitante',
      });
      final folder = Platform.environment['SWL_EXPORT_SAMPLE_DIR'];
      if (folder != null) await Directory(folder).create(recursive: true);
      for (final (label, team, pageCount) in [
        ('equipo', 'h', 4),
        ('global', null, 7),
      ]) {
        final pdf = await report.pdf(teamId: team);
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        final pages = await report.images(teamId: team);
        expect(pages.length, pageCount);
        for (final (index, png) in pages.indexed) {
          final size = ByteData.sublistView(png);
          expect([size.getUint32(16), size.getUint32(20)], [1080, 1920]);
          if (folder != null) {
            await File('$folder/$label-${index + 1}.png').writeAsBytes(png);
          }
        }
        if (folder != null) await File('$folder/$label.pdf').writeAsBytes(pdf);
      }
    });
  });

  testWidgets('Renderiza PNG con la firma del formato', (tester) async {
    await tester.runAsync(() async {
      final bytes = await SwlOfficialBoxScore(result(inning: 10)).png();
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });
  });
}
