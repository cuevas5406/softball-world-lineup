import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softball_world_lineup/swl_lineup_draft.dart';
import 'package:softball_world_lineup/swl_lineup_editor.dart';
import 'package:softball_world_lineup/swl_roster_repository.dart';

void main() {
  testWidgets('defensa incompleta y advertencia antes de descartar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(850, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final roster = {
      for (var i = 1; i <= 9; i++)
        '$i': SwlRosterPlayer(
          playerId: '$i',
          universalId: 'SWL-$i',
          name: 'Jugador $i',
          number: '$i',
          position: 'LF',
          secondaryPosition: '1B',
          isRefuerzo: false,
        ),
    };
    final draft = SwlLineupDraft(roster.keys.toList(), {});
    Map<String, dynamic>? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await showSwlLineupEditor(
                  context,
                  teamName: 'Equipo',
                  roster: roster,
                  draft: draft,
                );
                if (result == true) {
                  confirmed = draft.saveParameters(
                    gameId: 'match',
                    teamId: 'team',
                    revision: 1,
                    extended: true,
                  );
                }
              },
              child: const Text('ABRIR'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    final firstPitcher = find.widgetWithText(ChoiceChip, 'P').first;
    await tester.ensureVisible(firstPitcher);
    await tester.tap(firstPitcher);
    await tester.pumpAndSettle();
    expect(draft.pitcherId, isNull);
    expect(find.text('LF / 1B · SWL-1'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('Pitcher titular: Jugador 1'), findsOneWidget);

    await tester.tap(find.text('ORDEN AL BATE · 9'));
    await tester.pumpAndSettle();
    final save = find.text('GUARDAR ALINEACIÓN');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
    expect(find.textContaining('9 y 10 posiciones'), findsWidgets);
    expect(draft.batting, roster.keys.toList());
    expect(draft.pitcherId, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar cambios?'), findsOneWidget);
    await tester.tap(find.text('DESCARTAR'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(draft.batting, roster.keys.toList());
    expect(draft.positions, isEmpty);
  });

  testWidgets('guardar confirma defensa completa y conserva el orden editado', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(850, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final roster = {
      for (var i = 1; i <= 9; i++)
        '$i': SwlRosterPlayer(
          playerId: '$i',
          universalId: 'SWL-$i',
          name: 'Jugador $i',
          number: '$i',
          position: 'LF',
          secondaryPosition: '1B',
          isRefuerzo: false,
        ),
    };
    final positions = <String, String>{
      for (var i = 1; i <= 9; i++) '$i': swlDefensivePositions[i - 1],
    };
    final draft = SwlLineupDraft(roster.keys.toList(), positions);
    bool? confirmed;
    List<String>? savedDraft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                confirmed = await showSwlLineupEditor(
                  context,
                  teamName: 'Equipo',
                  roster: roster,
                  draft: draft,
                  onDraftChanged: (working) => savedDraft = working.batting,
                );
              },
              child: const Text('ABRIR'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ORDEN AL BATE · 9'));
    await tester.pumpAndSettle();
    final handles = find.byType(ReorderableDelayedDragStartListener);
    final first = tester.getCenter(handles.at(0));
    final third = tester.getCenter(handles.at(2));
    final drag = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 700));
    await drag.moveTo(third);
    await drag.up();
    await tester.pumpAndSettle();
    expect(savedDraft?.take(2), ['2', '1']);
    expect(draft.batting.take(2), ['1', '2']);
    final save = find.text('GUARDAR ALINEACIÓN');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(draft.batting.take(2), ['2', '1']);
    expect(draft.pitcherId, '1');
    expect(draft.validate(), isNull);
  });
}
