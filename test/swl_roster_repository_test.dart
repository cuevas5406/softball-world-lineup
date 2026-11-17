import 'package:flutter_test/flutter_test.dart';
import 'package:softball_world_lineup/swl_roster_repository.dart';

void main() {
  test('conserva UUID real y código universal', () {
    final player = SwlRosterPlayer.fromRows(
      {'player_id': 'p-1', 'is_refuerzo': true},
      {'id': 'p-1', 'universal_id': 'SWL-123', 'first_name': 'Ana',
       'last_name': 'Pérez', 'jersey_number': '8', 'primary_position': 'SS'});
    expect(player.playerId, 'p-1');
    expect(player.universalId, 'SWL-123');
    expect(player.name, 'Ana Pérez');
    expect(player.isRefuerzo, true);
  });

  test('rechaza emparejamiento de roster con otro jugador', () {
    expect(() => SwlRosterPlayer.fromRows({'player_id': 'p-2'}, {'id': 'p-1'}),
      throwsStateError);
  });
}
