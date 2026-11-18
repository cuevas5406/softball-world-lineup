import 'package:flutter_test/flutter_test.dart';
import '../lib/swl_live_scoreboard_snapshot.dart';

void main() {
  Map<String, dynamic> game({bool top = true, String status = 'IN_PROGRESS'}) => {
    'id': 'game-1', 'game_pin': 'SWL-123', 'home_team_id': 'home-uuid',
    'away_team_id': 'away-uuid', 'home_manager_id': 'home-manager',
    'away_manager_id': 'away-manager', 'is_top': top, 'status': status,
    'version': 5, 'inning': 2, 'balls': 1, 'strikes': 2, 'outs': 1,
    'bases_state': {'first': true, 'second': false, 'third': true},
  };

  test('Alta: solo el mánager visitante puede anotar', () {
    final snapshot = SwlLiveScoreboardSnapshot.fromGame(game());
    expect(snapshot.canScore('away-manager'), isTrue);
    expect(snapshot.canScore('home-manager'), isFalse);
    expect(snapshot.battingTeamId, 'away-uuid');
    expect(snapshot.firstOccupied, isTrue);
    expect(snapshot.thirdOccupied, isTrue);
  });

  test('Baja: solo el mánager local puede anotar', () {
    final snapshot = SwlLiveScoreboardSnapshot.fromGame(game(top: false));
    expect(snapshot.canScore('home-manager'), isTrue);
    expect(snapshot.canScore('away-manager'), isFalse);
    expect(snapshot.battingTeamId, 'home-uuid');
  });

  test('Partidos no iniciados o finalizados no admiten anotaciones', () {
    for (final status in ['SCHEDULED', 'FINAL', 'OFFICIAL']) {
      final snapshot = SwlLiveScoreboardSnapshot.fromGame(game(status: status));
      expect(snapshot.canScore('away-manager'), isFalse);
    }
  });

  test('Un espectador no puede anotar', () {
    expect(SwlLiveScoreboardSnapshot.fromGame(game()).canScore('fan'), isFalse);
    expect(SwlLiveScoreboardSnapshot.fromGame(game()).canScore(null), isFalse);
  });
}
