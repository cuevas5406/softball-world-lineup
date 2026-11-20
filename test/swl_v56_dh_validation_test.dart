import 'package:flutter_test/flutter_test.dart';
import '../lib/swl_lineup_draft.dart';

void main() {
  final players = List.generate(11, (i) => 'player-$i');
  final defensive = <String, String>{
    for (var i = 0; i < 9; i++) players[i]:
      swlDefensivePositions[i],
  };

  test('pitcher without batting must not remain in selected order', () {
    final draft = SwlLineupDraft(
      [players[0], ...players.skip(1).take(9)],
      Map.of(defensive),
      pitcherBats: false,
      designatedId: players[9],
    );
    expect(draft.validate(), contains('retíralo'));
  });

  test('DH cannot be a defensive player', () {
    final draft = SwlLineupDraft(
      [...players.skip(1).take(9)],
      Map.of(defensive),
      pitcherBats: false,
      designatedId: players[1],
    );
    expect(draft.validate(), contains('designado'));
  });

  test('valid DH bats and pitcher stays off batting order', () {
    final draft = SwlLineupDraft(
      [...players.skip(1).take(9)],
      Map.of(defensive),
      pitcherBats: false,
      designatedId: players[9],
    );
    expect(draft.validate(), isNull);
  });
}
