import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_official_box_score.dart';

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

  test('Genera un PDF con estadísticas oficiales', () async {
    final bytes = await SwlOfficialBoxScore(result()).pdf();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  testWidgets('Renderiza PNG con la firma del formato', (tester) async {
    await tester.runAsync(() async {
      final bytes = await SwlOfficialBoxScore(result(inning: 10)).png();
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });
  });
}
