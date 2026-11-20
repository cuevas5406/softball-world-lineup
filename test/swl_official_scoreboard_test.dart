import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:softball_world_lineup/swl_advanced_scoreboard.dart';
import 'package:softball_world_lineup/swl_live_scoreboard_snapshot.dart';
import 'package:softball_world_lineup/swl_team_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final methods = <String>[];
  Future<http.Response> Function(http.Request)? respond;
  http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  tearDown(() => respond = null);
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
        final response =
            await (respond?.call(request) ?? Future.value(jsonResponse([])));
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('La pizarra oficial de solo lectura acepta un cambio de turno', (
    tester,
  ) async {
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

  testWidgets(
    'La pizarra ofrece sustitución y actualización manual sin barra',
    (tester) async {
      var substituted = false;
      var gameReads = 0;
      respond = (request) async {
        if (request.url.path.endsWith('/swl_live_games')) {
          gameReads++;
          return jsonResponse([]);
        }
        return jsonResponse([]);
      };
      await tester.pumpWidget(
        MaterialApp(
          home: SwlAdvancedScoreboard(
            gamePin: 'SWL-123456',
            homeTeam: 'Local',
            awayTeam: 'Visitante',
            liveSnapshot: SwlLiveScoreboardSnapshot.fromGame({
              'id': 'partido-prueba',
              'status': 'IN_PROGRESS',
              'version': 1,
              'is_top': true,
            }),
            onLiveSubstitute: () => substituted = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cambios de jugadores'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sustituir bateador'));
      await tester.pumpAndSettle();
      expect(substituted, true);
      await tester.tap(find.byTooltip('Actualizar pizarra'));
      await tester.pumpAndSettle();
      expect(gameReads, greaterThan(0));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Configuración carga y envía cambios con la revisión al guardar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Map<String, dynamic>? sent;
      respond = (request) async {
        if (request.url.path.endsWith('/swl_v57_team_settings')) {
          return jsonResponse({
            'name': 'Los 300',
            'province': 'Santo Domingo',
            'revision': 4,
            'primary_color': '#FFAA00',
            'delegate': 'Delegada',
          });
        }
        if (request.url.path.endsWith('/swl_v57_update_team_settings')) {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse({});
        }
        return jsonResponse([]);
      };
      Map<String, String>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await Navigator.of(context).push<Map<String, String>>(
                    MaterialPageRoute(
                      builder: (_) => const SwlTeamSettings(
                        teamId: 'equipo',
                        name: 'Anterior',
                        province: '',
                      ),
                    ),
                  );
                },
                child: const Text('ABRIR CONFIGURACIÓN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ABRIR CONFIGURACIÓN'));
      await tester.pumpAndSettle();
      expect(find.text('Los 300'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Color principal (#RRGGBB)'),
        '#00aaff',
      );
      final save = find.text('GUARDAR CONFIGURACIÓN');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(sent?['p_expected_revision'], 4);
      expect((sent?['p_data'] as Map)['primary_color'], '#00AAFF');
      expect(saved?['primary_color'], '#00AAFF');
    },
  );

  testWidgets(
    'El historial se recupera aunque falle la consulta de alineaciones',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final firstResponse = Completer<http.Response>();
      var historyReads = 0;
      var connected = true;
      var laterRun = false;
      Map<String, dynamic> play(String type, Map<String, dynamic> data) => {
        'event_type': type,
        'event_data': data,
        'inning': 1,
        'is_top': true,
      };
      final walk = play('BALL', {'plate_appearance_completed': true});
      respond = (request) async {
        if (request.url.path.endsWith('/swl_game_lineups')) {
          return jsonResponse({
            'code': '42501',
            'message': 'Sin acceso a alineaciones',
          }, 403);
        }
        if (request.url.path.endsWith('/swl_game_events')) {
          expect(request.url.queryParameters['game_id'], 'eq.partido-prueba');
          expect(request.url.queryParameters.containsKey('version'), isFalse);
          expect(
            request.url.queryParameters['order'],
            'version.asc.nullslast,id.asc.nullslast',
          );
          historyReads++;
          if (historyReads == 1) return firstResponse.future;
          if (!connected)
            return jsonResponse({
              'code': '42501',
              'message': 'Lectura interrumpida',
            }, 403);
          return jsonResponse([
            play('BALL', {}),
            play('STRIKE', {'plate_appearance_completed': false}),
            walk,
            play('HIT', {'batter_base': '2'}),
            play('STRIKE', {'plate_appearance_completed': true}),
            play('RUNNER_MOVE', {}),
            play('OUT', {}),
            if (laterRun) play('RUN', {}),
          ]);
        }
        return jsonResponse([]);
      };
      Widget scoreboard(int version) => MaterialApp(
        home: SwlAdvancedScoreboard(
          gamePin: 'SWL-123456',
          homeTeam: 'Local',
          awayTeam: 'Visitante',
          liveSnapshot: SwlLiveScoreboardSnapshot.fromGame({
            'id': 'partido-prueba',
            'version': version,
            'inning': 1,
            'is_top': true,
          }),
        ),
      );
      await tester.pumpWidget(scoreboard(1));
      await tester.pump();
      await tester.pumpWidget(scoreboard(2));
      await tester.pump();
      firstResponse.complete(jsonResponse([walk]));
      await tester.pumpAndSettle();
      expect(historyReads, 2);
      expect(find.textContaining('Base por bolas'), findsOneWidget);
      expect(find.textContaining('Doble'), findsOneWidget);
      expect(find.textContaining('Partido: Out'), findsOneWidget);
      expect(find.textContaining('Partido: Bola'), findsNothing);
      expect(find.textContaining('Partido: Strike'), findsNothing);
      expect(find.textContaining('Ver también lanzamientos'), findsNothing);
      expect(find.textContaining('Ponche'), findsOneWidget);
      expect(find.textContaining('Movimiento de corredor'), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining('Base por bolas')).dy,
        lessThan(tester.getTopLeft(find.textContaining('Doble')).dy),
      );
      connected = false;
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reintentando'), findsOneWidget);
      expect(find.textContaining('Doble'), findsOneWidget);

      connected = true;
      laterRun = true;
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.textContaining('Carrera registrada'), findsOneWidget);
      expect(find.textContaining('Reintentando'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(scoreboard(2));
      await tester.pumpAndSettle();
      expect(find.textContaining('Carrera registrada'), findsOneWidget);
      expect(find.textContaining('Doble'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
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
