import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:softball_world_lineup/swl_advanced_scoreboard.dart';
import 'package:softball_world_lineup/swl_live_scoreboard_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final methods = <String>[];
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://swl-test.invalid',
      publishableKey: 'test-only',
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
        persistSession: false,
        pkceAsyncStorage: _TestAuthStorage(),
        autoRefreshToken: false,
      ),
      httpClient: MockClient((request) async {
        methods.add(request.method);
        return http.Response('[]', 200, headers: {
          'content-type': 'application/json',
        });
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('La pizarra oficial de solo lectura acepta un cambio de turno',
      (tester) async {
    Widget scoreboard(int version, bool top) => MaterialApp(
      home: SwlAdvancedScoreboard(
        gamePin: 'SWL-123456',
        homeTeam: 'Equipo local',
        awayTeam: 'Equipo visitante',
        liveSnapshot: SwlLiveScoreboardSnapshot.fromGame({
          'id': 'partido-prueba',
          'home_team_id': 'local',
          'away_team_id': 'visitante',
          'home_manager_id': 'manager-local',
          'away_manager_id': 'manager-visitante',
          'status': 'IN_PROGRESS',
          'inning': 1,
          'is_top': top,
          'version': version,
        }),
      ),
    );

    await tester.pumpWidget(scoreboard(1, true));
    await tester.pumpAndSettle();
    expect(find.textContaining('SOLO LECTURA'), findsOneWidget);
    expect(find.textContaining('ALTA'), findsOneWidget);
    for (final label in ['BOLA', 'STRIKE', 'OUT', 'BATAZO / HIT']) {
      final button = find.widgetWithText(ElevatedButton, label);
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    }

    await tester.pumpWidget(scoreboard(2, false));
    await tester.pumpAndSettle();
    expect(find.textContaining('BAJA'), findsOneWidget);
    await tester.pumpWidget(scoreboard(1, true));
    await tester.pumpAndSettle();
    expect(find.textContaining('BAJA'), findsOneWidget);

    expect(methods, isNotEmpty);
    expect(methods.every((method) => method == 'GET'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _TestAuthStorage extends GotrueAsyncStorage {
  const _TestAuthStorage();

  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> setItem({required String key, required String value}) async {}

  @override
  Future<void> removeItem({required String key}) async {}
}
