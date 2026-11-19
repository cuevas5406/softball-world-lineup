import 'package:flutter_test/flutter_test.dart';
import 'package:softball_world_lineup/swl_lineup_identity.dart';
import 'package:softball_world_lineup/swl_pitching_stats.dart';

void main() {
  final first = {'order': 1, 'player_id': 'a'};
  final second = {'order': 2, 'player_id': 'b'};
  test('Ordena la alineación por turno confirmado y conserva el ID', () {
    expect(swlConfirmedBattingSlots([second, first]), [first, second]);
  });
  test('Descarta órdenes repetidos, incompletos e identidades duplicadas', () {
    expect(swlConfirmedBattingSlots([first, first]), isEmpty);
    expect(swlConfirmedBattingSlots([second]), isEmpty);
    expect(
      swlConfirmedBattingSlots([
        first,
        {...second, 'player_id': 'a'},
      ]),
      isEmpty,
    );
  });
  test('El pitcheo suma outs y mantiene entradas en formato deportivo', () {
    final totals = SwlPitchingTotals()
      ..add({'outs': 3, 'strikes_out': 1, 'walks': 0, 'hits': 0})
      ..add({'outs': 1, 'strikes_out': 0, 'walks': 1, 'hits': 1});
    expect(totals.innings, '1.1');
    expect(totals.strikeouts, 1);
    expect(totals.walks, 1);
    expect(totals.hits, 1);
  });
}
