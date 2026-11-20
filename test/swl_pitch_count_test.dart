import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_history_events.dart';
import '../lib/swl_pitching_stats.dart';

void main() {
  test(
    'Conserva B, S y los resultados finales sin sumar el terminal dos veces',
    () {
      final first = SwlPitchingTotals()
        ..add({
          'pitch_in_play': 0,
          'pitch_count': 1,
          'pitch_balls': 1,
          'pitch_strikes': 0,
          'walks': 1,
        })
        ..add({
          'pitch_in_play': 0,
          'pitch_count': 1,
          'pitch_balls': 0,
          'pitch_strikes': 1,
          'strikes_out': 1,
        })
        ..add({
          'pitch_in_play': 0,
          'pitch_count': 0,
          'pitch_balls': 0,
          'pitch_strikes': 0,
          'outs': 1,
        });
      final relief = SwlPitchingTotals()
        ..add({
          'pitch_in_play': 0,
          'pitch_count': 1,
          'pitch_balls': 0,
          'pitch_strikes': 1,
        });
      expect(
        (
          first.pitches,
          first.balls,
          first.strikes,
          first.walks,
          first.strikeouts,
        ),
        (2, 1, 1, 1, 1),
      );
      expect(relief.pitchLine, '1 PITCHES · 0 B · 1 S · 0 en juego');
      expect(swlIsHistoryPlay({'event_type': 'FOUL'}), isFalse);
    },
  );

  test('Distingue datos antiguos sin conteo y totales parciales', () {
    final totals = SwlPitchingTotals()..add({'outs': 2});
    expect(totals.pitchLine, 'Pitcheos sin datos');
    expect(totals.innings, '0.2');
    totals.add({
      'pitch_in_play': 0,
      'pitch_count': 1,
      'pitch_balls': 1,
      'pitch_strikes': 0,
    });
    expect(totals.pitchLine, contains('(parcial)'));
  });
  test('La bola en juego suma un pitcheo y conserva las columnas B y S', () {
    final totals = SwlPitchingTotals()
      ..add({
        'pitch_count': 1,
        'pitch_balls': 1,
        'pitch_strikes': 0,
        'pitch_in_play': 0,
      })
      ..add({
        'pitch_count': 1,
        'pitch_balls': 0,
        'pitch_strikes': 1,
        'pitch_in_play': 0,
      })
      ..add({
        'pitch_count': 1,
        'pitch_balls': 0,
        'pitch_strikes': 0,
        'pitch_in_play': 1,
        'hits': 1,
      });
    expect(
      (
        totals.pitches,
        totals.balls,
        totals.strikes,
        totals.inPlay,
        totals.hits,
      ),
      (3, 1, 1, 1, 1),
    );
  });

  test(
    'El conteo del borrador anterior no se mezcla con la nueva clasificación',
    () {
      final totals = SwlPitchingTotals()
        ..add({
          'pitch_count': 1,
          'pitch_balls': 0,
          'pitch_strikes': 1,
          'hits': 1,
        });
      expect(totals.pitchLine, 'Pitcheos sin datos');
      expect(totals.hits, 1);
    },
  );
}
