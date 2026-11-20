import 'package:flutter/material.dart';

import 'swl_lineup_draft.dart';
import 'swl_roster_repository.dart';

Future<bool?> showSwlLineupEditor(
  BuildContext context, {
  required String teamName,
  required Map<String, SwlRosterPlayer> roster,
  required SwlLineupDraft draft,
  ValueChanged<SwlLineupDraft>? onDraftChanged,
}) {
  // Edit a detached copy: cancelling the dialog must never mutate the draft.
  final working = SwlLineupDraft(
    List<String>.of(draft.selected),
    Map<String, String>.of(draft.positions),
    pitcherBats: draft.pitcherBats,
    designatedId: draft.designatedId,
  );
  final selected = working.selected;
  final positions = working.positions;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => PopScope(
      canPop: false,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          void update(VoidCallback change) {
            setDialogState(change);
            onDraftChanged?.call(working);
          }

          final batting = working.batting;
          final designated = batting
              .where((id) => !positions.containsKey(id))
              .toList();
          final error = working.validate();
          return AlertDialog(
            title: Text('Elegir mi alineación · $teamName'),
            content: SizedBox(
              width: 450,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'Pitcher titular: ${roster[working.pitcherId]?.name ?? "Sin asignar"}',
                  ),
                  if (working.pitcherId != null)
                    SwitchListTile(
                      title: const Text('El pitcher batea'),
                      value: working.pitcherBats,
                      subtitle: !working.pitcherBats && batting.length == 13
                          ? const Text(
                              'Libera un turno para que batee el pitcher.',
                            )
                          : null,
                      onChanged: !working.pitcherBats && batting.length == 13
                          ? null
                          : (value) => update(() {
                              final pitcher = working.pitcherId;

                              working.pitcherBats = value;
                              if (!value && pitcher != null) {
                                working.setBatting(pitcher, false);
                              } else if (value && pitcher != null) {
                                working.setBatting(pitcher, true);
                              }
                              working.designatedId = null;
                            }),
                    ),
                  if (!working.pitcherBats)
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        designated.contains(working.designatedId)
                            ? working.designatedId
                            : null,
                      ),
                      initialValue: designated.contains(working.designatedId)
                          ? working.designatedId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Bateador designado',
                      ),
                      items: [
                        for (final id in designated)
                          DropdownMenuItem(
                            value: id,
                            child: Text(roster[id]!.name),
                          ),
                      ],
                      onChanged: (id) =>
                          update(() => working.designatedId = id),
                    ),
                  ExpansionTile(
                    title: Text('Orden al bate · ${batting.length}'),
                    initiallyExpanded: true,
                    children: [
                      for (var index = 0; index < batting.length; index++)
                        ListTile(
                          key: ValueKey(batting[index]),
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(roster[batting[index]]!.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Subir en el orden',
                                icon: const Icon(Icons.keyboard_arrow_up),
                                onPressed: index == 0
                                    ? null
                                    : () => update(
                                        () => working.moveBatter(index, -1),
                                      ),
                              ),
                              IconButton(
                                tooltip: 'Bajar en el orden',
                                icon: const Icon(Icons.keyboard_arrow_down),
                                onPressed: index == batting.length - 1
                                    ? null
                                    : () => update(
                                        () => working.moveBatter(index, 1),
                                      ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Jugadores y defensa'),
                    initiallyExpanded: true,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final position in swlDefensivePositions)
                            Chip(
                              label: Text(
                                '$position · ${roster[positions.entries.where((entry) => entry.value == position).firstOrNull?.key]?.name ?? "Libre"}',
                              ),
                            ),
                        ],
                      ),
                      for (final player in roster.values) ...[
                        CheckboxListTile(
                          key: ValueKey('roster-${player.playerId}'),
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(player.playerId),
                          title: Text(
                            '${player.name} · #${player.number} · Batea',
                          ),
                          subtitle: Text(
                            '${player.positionLabel} · ${player.universalId}',
                          ),
                          onChanged:
                              (!working.pitcherBats &&
                                  working.pitcherId == player.playerId &&
                                  !selected.contains(player.playerId))
                              ? null
                              : !selected.contains(player.playerId) &&
                                    working.batting.length >= 13
                              ? null
                              : (checked) => update(() {
                                  working.setBatting(
                                    player.playerId,
                                    checked == true,
                                  );
                                  if (checked != true &&
                                      working.designatedId == player.playerId) {
                                    working.designatedId = null;
                                  }
                                }),
                        ),
                        // Any active player may defend, even when not batting.
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final position in swlDefensivePositions)
                              ChoiceChip(
                                label: Text(position),
                                selected:
                                    positions[player.playerId] == position,
                                // An occupied position can be selected:
                                // the draft swaps the two fielders safely.
                                onSelected: (on) => update(
                                  () => working.assign(
                                    player.playerId,
                                    on ? position : null,
                                  ),
                                ),
                              ),
                            ActionChip(
                              label: const Text('Sin posición'),
                              onPressed: () => update(
                                () => working.assign(player.playerId, null),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('CANCELAR'),
              ),
              if (onDraftChanged != null)
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('CONTINUAR DESPUÉS'),
                ),
              FilledButton(
                onPressed: error == null
                    ? () {
                        draft.selected
                          ..clear()
                          ..addAll(working.selected);
                        draft.positions
                          ..clear()
                          ..addAll(working.positions);
                        draft.pitcherBats = working.pitcherBats;
                        draft.designatedId = working.designatedId;
                        Navigator.pop(dialog, true);
                      }
                    : null,
                child: const Text('GUARDAR ALINEACIÓN'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
