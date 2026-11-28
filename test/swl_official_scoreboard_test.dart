import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:softball_world_lineup/swl_advanced_scoreboard.dart';
import 'package:softball_world_lineup/swl_game_detail_page.dart';
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
      realtimeClientOptions: const RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: Duration.zero,
      ),
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

  testWidgets('Box Score mantiene nombres y encabezado al desplazar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 460));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    respond = (request) async {
      final table = request.url.path.split('/').last;
      return switch (table) {
        'swl_live_games' => jsonResponse({
          'id': 'game',
          'version': 1,
          'game_pin': 'SWL-378859',
          'home_team_id': 'home',
          'away_team_id': 'away',
          'status': 'IN_PROGRESS',
          'inning': 2,
          'is_top': true,
          'home_runs': 0,
          'away_runs': 0,
          'home_hits': 0,
          'away_hits': 0,
        }),
        'swl_game_lineups' => jsonResponse([
          {
            'team_id': 'away',
            'lineup': [
              for (var i = 1; i <= 12; i++) {'order': i, 'player_id': 'p$i'},
            ],
          },
        ]),
        'players' => jsonResponse([
          for (var i = 1; i <= 12; i++)
            {'id': 'p$i', 'first_name': 'Jugador $i'},
        ]),
        _ => jsonResponse([]),
      };
    };
    await tester.pumpWidget(
      MaterialApp(
        home: SwlGameDetailPage(
          gameId: 'game',
          boxScore: true,
          teamName: (id) => id,
          teamLogo: (_) => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('6'), findsOneWidget);
    expect(find.text('·'), findsWidgets);
    expect(find.text('0*'), findsOneWidget);

    final name = find.text('Jugador 1');
    final header = find.text('Bateo · Pelotero');
    final pa = find.text('PA');
    final original = tester.getTopLeft(name);
    final originalPa = tester.getTopLeft(pa).dx;
    await tester.dragFrom(
      tester.getCenter(pa) + const Offset(100, 0),
      const Offset(-90, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(name), original);
    expect(tester.getTopLeft(pa).dx, lessThan(originalPa));

    final headerY = tester.getTopLeft(header).dy;
    await tester.dragFrom(tester.getCenter(name), const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, headerY);
    await tester.tap(find.widgetWithText(Tab, 'home'));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(800, 440));
    await tester.pumpAndSettle();
    expect(find.text('Pitcheo · Pelotero'), findsOneWidget);
    expect(find.text('Box Score · SWL-378859'), findsOneWidget);
    expect(find.text('Jugador 1'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets(
    'El historial identifica saliente, entrante, equipo y turno o posición',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      respond = (request) async {
        if (request.url.path.endsWith('/swl_game_events')) {
          return jsonResponse([
            {
              'id': 'dp',
              'version': 2,
              'inning': 2,
              'is_top': true,
              'batting_team_id': 'visitante',
              'event_type': 'DOUBLE_PLAY',
              'event_data': {
                'batter_id': 'in',
                'runner_id': 'out',
                'outs_added': 2,
              },
            },
            {
              'id': 'sust',
              'version': 3,
              'inning': 2,
              'is_top': true,
              'batting_team_id': 'visitante',
              'event_type': 'SUBSTITUTION',
              'event_data': {
                'outgoing_player_id': 'out',
                'incoming_player_id': 'in',
                'batting_order': 6,
              },
            },
          ]);
        }
        if (request.url.path.endsWith('/swl_v56_pitching_events')) {
          return jsonResponse([
            {'version': 2, 'pitcher_id': 'p1'},
          ]);
        }
        if (request.url.path.endsWith('/swl_v56_pitcher_changes')) {
          return jsonResponse([
            {
              'team_id': 'local',
              'version': 4,
              'innings_number': 2,
              'old_pitcher_id': 'p1',
              'new_pitcher_id': 'p2',
            },
          ]);
        }
        if (request.url.path.endsWith('/players')) {
          return jsonResponse([
            {'id': 'out', 'first_name': 'Saliente'},
            {'id': 'in', 'first_name': 'Entrante'},
            {'id': 'p1', 'first_name': 'Lanzador A'},
            {'id': 'p2', 'first_name': 'Lanzador B'},
          ]);
        }
        return jsonResponse([]);
      };
      await tester.pumpWidget(
        MaterialApp(
          home: SwlAdvancedScoreboard(
            gamePin: 'SWL-TEST',
            homeTeam: 'Locales',
            awayTeam: 'Visitantes',
            liveSnapshot: SwlLiveScoreboardSnapshot.fromGame({
              'id': 'test',
              'version': 4,
              'inning': 2,
              'is_top': true,
              'home_team_id': 'local',
              'away_team_id': 'visitante',
              'status': 'IN_PROGRESS',
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Visitantes: Sustitución · turno 6 · sale Saliente · entra Entrante',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Locales: Cambio de pitcher · posición P · sale Lanzador A · entra Lanzador B',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Doble play · bateador: Entrante · pitcher: Lanzador A',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Fan consulta la pizarra, equipos separados y jugadas de favoritos',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      methods.clear();
      respond = (request) async {
        if (request.url.path.endsWith('/rpc/swl_v57_spectator_box_source')) {
          return jsonResponse({
            'game': {
              'game_pin': 'SWL-TEST',
              'status': 'OFFICIAL',
              'version': 2,
              'inning': 1,
              'is_top': false,
              'away_team_id': 'away',
              'home_team_id': 'home',
              'away_runs': 0,
              'home_runs': 0,
              'away_hits': 1,
            },
            'events': [
              {
                'event_type': 'HIT',
                'batting_team_id': 'away',
                'inning': 1,
                'version': 1,
                'event_data': {'batter_id': 'away-player', 'batter_base': 2},
              },
            ],
            'pitches': [
              {'version': 1, 'pitcher_id': 'home-player', 'hits': 1, 'outs': 0},
            ],
            'players': [
              {
                'id': 'away-player',
                'first_name': 'Visitante',
                'last_name': 'Uno',
                'jersey_number': 12,
              },
            ],
          });
        }
        if (request.url.path.endsWith('/swl_game_lineups')) {
          return jsonResponse([
            {
              'team_id': 'away',
              'lineup': [
                {'order': 1, 'player_id': 'away-player'},
              ],
              'defensive_positions': {'away-player': '1B'},
            },
          ]);
        }
        if (request.url.path.endsWith('/players')) {
          return jsonResponse([
            {
              'id': 'away-player',
              'first_name': 'Visitante',
              'last_name': 'Uno',
              'jersey_number': 12,
            },
          ]);
        }
        if (request.url.path.endsWith('/swl_game_events')) {
          return jsonResponse([
            {
              'id': 'play',
              'event_type': 'HIT',
              'inning': 1,
              'is_top': true,
              'version': 1,
              'event_data': {'batter_id': 'away-player', 'batter_base': 2},
            },
          ]);
        }
        return jsonResponse([]);
      };
      final favorites = <String>{'player:away-player'};
      var scoringCalls = 0;
      Widget game(int version, bool isTop) => MaterialApp(
        home: SwlAdvancedScoreboard(
          gamePin: 'SWL-TEST',
          awayTeam: 'Visitantes',
          homeTeam: 'Locales',
          liveSnapshot: SwlLiveScoreboardSnapshot.fromGame({
            'id': 'spectator-test',
            'status': 'IN_PROGRESS',
            'version': version,
            'is_top': isTop,
            'inning': 1,
            'away_team_id': 'away',
            'home_team_id': 'home',
            'away_runs': version - 1,
          }),
          onLiveAction: (_, _, _) async {
            scoringCalls++;
          },
          spectator: SwlSpectatorView(
            detailed: true,
            isFavorite: favorites.contains,
            toggleFavorite: (id, _) async {
              favorites.remove(id);
            },
            publicGame: const {
              'lineups': [
                {
                  'team_id': 'away',
                  'id': 'away-player',
                  'order': 1,
                  'name': 'Visitante Uno',
                  'number': 12,
                  'position': '1B',
                },
                {
                  'team_id': 'home',
                  'id': 'home-player',
                  'order': 1,
                  'name': 'Local Uno',
                  'number': 8,
                  'position': 'P',
                },
              ],
            },
          ),
        ),
      );

      await tester.pumpWidget(game(1, true));
      await tester.pumpAndSettle();
      expect(find.textContaining('★ Última jugada:'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.semanticLabel == 'Pelotero favorito al bate',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Doble'), findsWidgets);
      for (final label in ['BOLA', 'STRIKE', 'OUT', 'BATAZO / HIT']) {
        expect(find.widgetWithText(ElevatedButton, label), findsNothing);
      }
      expect(find.byTooltip('Cambios de jugadores'), findsNothing);
      expect(find.byTooltip('Actualizar pizarra'), findsNothing);

      await tester.tap(find.text('Alineaciones'));
      await tester.pumpAndSettle();
      expect(find.text('1. Visitante Uno'), findsOneWidget);
      expect(find.text('#12 · 1B'), findsOneWidget);
      expect(find.text('1. Local Uno'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Locales'));
      await tester.pumpAndSettle();
      expect(find.text('1. Local Uno'), findsOneWidget);
      expect(find.text('1. Visitante Uno'), findsNothing);

      await tester.pumpWidget(game(2, false));
      await tester.pumpAndSettle();
      expect(find.textContaining('BAJA'), findsOneWidget);
      expect(find.text('1. Local Uno'), findsOneWidget);
      await tester.tap(find.text('Estadísticas'));
      await tester.pumpAndSettle();
      expect(find.textContaining('AB 1 · H 1'), findsOneWidget);
      expect(scoringCalls, 0);
      expect(methods.every((method) => method == 'GET'), isTrue);
      await tester.tap(find.text('Box Score'));
      await tester.pumpAndSettle();
      expect(find.text('Box Score · SWL-TEST'), findsOneWidget);
      expect(find.textContaining('Visitante Uno'), findsOneWidget);
      expect(find.text('VB'), findsOneWidget);
      expect(find.byTooltip('Cambios de jugadores'), findsNothing);
      expect(methods.where((method) => method != 'GET'), ['POST']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
      methods.clear();
    },
  );

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
      var reconciliations = 0;
      respond = (request) async {
        if (request.url.path.endsWith('/swl_live_games')) {
          gameReads++;
          return jsonResponse({
            'id': 'partido-prueba',
            'status': 'IN_PROGRESS',
            'version': 2,
            'inning': 1,
            'is_top': false,
          });
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
            onLiveRefresh: () async {
              reconciliations++;
            },
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
      expect(reconciliations, 1);
      expect(find.textContaining('BAJA'), findsOneWidget);
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
