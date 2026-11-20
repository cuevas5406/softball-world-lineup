import 'dart:convert';

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
  final original = jsonEncode(draft.toLocalJson());
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
              TextButton(
                onPressed: () async {
                  final dirty = original != jsonEncode(working.toLocalJson());
                  final discard =
                      !dirty ||
                      await showDialog<bool>(
                            context: dialog,
                            builder: (warning) => AlertDialog(
                              title: const Text('¿Descartar cambios?'),
                              content: const Text(
                                'Se recuperará la alineación o el borrador con el que entraste.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(warning, false),
                                  child: const Text('SEGUIR EDITANDO'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(warning, true),
                                  child: const Text('DESCARTAR'),
                                ),
                              ],
                            ),
                          ) ==
                          true;
                  if (discard && dialog.mounted) Navigator.pop(dialog);
                },
                child: const Text('CANCELAR'),
              ),
              if (onDraftChanged != null)
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('CONTINUAR DESPUÉS'),
                ),
              FilledButton(
                onPressed: () async {
                  final save = await Navigator.of(dialog).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => _SwlBattingOrderPage(
                        draft: working,
                        roster: roster,
                        onChanged: onDraftChanged,
                      ),
                    ),
                  );
                  if (!dialog.mounted) return;
                  if (save != true) {
                    setDialogState(() {});
                    return;
                  }
                  draft.selected
                    ..clear()
                    ..addAll(working.selected);
                  draft.positions
                    ..clear()
                    ..addAll(working.positions);
                  draft.pitcherBats = working.pitcherBats;
                  draft.designatedId = working.designatedId;
                  Navigator.pop(dialog, true);
                },
                child: Text('ORDEN AL BATE · ${batting.length}'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _SwlBattingOrderPage extends StatefulWidget {
  const _SwlBattingOrderPage({
    required this.draft,
    required this.roster,
    this.onChanged,
  });

  final SwlLineupDraft draft;
  final Map<String, SwlRosterPlayer> roster;
  final ValueChanged<SwlLineupDraft>? onChanged;

  @override
  State<_SwlBattingOrderPage> createState() => _SwlBattingOrderPageState();
}

class _SwlBattingOrderPageState extends State<_SwlBattingOrderPage> {
  void _reorder(int from, int to) {
    final wholeOrder = widget.draft.selected;
    final batting = widget.draft.batting;
    if (to == from) return;
    final player = batting.removeAt(from);
    batting.insert(to, player);
    setState(() {
      wholeOrder
        ..clear()
        ..addAll(batting);
    });
    widget.onChanged?.call(widget.draft);
  }

  @override
  Widget build(BuildContext context) {
    final batting = widget.draft.batting;
    final error = widget.draft.validate();
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(title: const Text('Orden al bate')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ReorderableListView.builder(
                itemCount: batting.length,
                onReorderItem: _reorder,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final id = batting[index];
                  return ListTile(
                    key: ValueKey(id),
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(widget.roster[id]!.name),
                    subtitle: Text(
                      widget.draft.designatedId == id
                          ? 'DH'
                          : widget.draft.positions[id] ?? 'Solo bateo',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Subir en el orden',
                          onPressed: index > 0
                              ? () => _reorder(index, index - 1)
                              : null,
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        IconButton(
                          tooltip: 'Bajar en el orden',
                          onPressed: index + 1 < batting.length
                              ? () => _reorder(index, index + 1)
                              : null,
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                        ReorderableDelayedDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: error == null
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('GUARDAR ALINEACIÓN'),
            ),
          ],
        ),
      ),
    );
  }
}
