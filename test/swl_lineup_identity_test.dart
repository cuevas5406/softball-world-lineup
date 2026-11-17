import 'package:flutter_test/flutter_test.dart';
import 'package:softball_world_lineup/swl_lineup_identity.dart';

List<SwlLineupEntry> sample() => List.generate(9, (i) => SwlLineupEntry(
  playerId: 'player-$i', name: 'Jugador $i', number: '$i',
  role: 'REGULAR', position: ['P','C','1B','2B','3B','SS','LF','CF','RF'][i]));

void main() {
  test('Alineación de nueve con IDs únicos produce orden 1 a 9', () {
    final data = SwlLineupIdentity.payload(sample());
    expect(data.length, 9);
    expect(data.first['batting_order'], 1);
    expect(data.last['player_id'], 'player-8');
  });
  test('No permite IDs duplicados', () {
    final list = sample();
    list[1] = SwlLineupEntry(playerId: 'player-0', name: 'Nuevo', number: '44',
      role: 'REGULAR', position: 'C');
    expect(() => SwlLineupIdentity.validate(list), throwsStateError);
  });
  test('No atribuye estadísticas sin ID', () {
    final list = sample();
    list[0] = const SwlLineupEntry(playerId: null, name: 'Local', number: '30',
      role: 'REGULAR', position: 'P');
    expect(() => SwlLineupIdentity.payload(list), throwsStateError);
    expect(() => SwlLineupIdentity.validate(list), returnsNormally);
  });
  test('DH no puede coexistir con pitcher en orden al bate', () {
    final list = sample();
    list[8] = const SwlLineupEntry(playerId: 'player-8', name: 'DH', number: '8',
      role: 'DH', position: 'SIN');
    expect(() => SwlLineupIdentity.validate(list), throwsStateError);
  });
  test('No permite repetir posición defensiva', () {
    final list = sample();
    list[8] = const SwlLineupEntry(playerId: 'player-8', name: 'RF nuevo', number: '8',
      role: 'REGULAR', position: 'C');
    expect(() => SwlLineupIdentity.validate(list), throwsStateError);
  });
  test('Serialización conserva identidad', () {
    final entry = sample().first;
    final restored = SwlLineupEntry.fromJson(entry.toJson());
    expect(restored.playerId, entry.playerId);
    expect(restored.name, entry.name);
  });
}
