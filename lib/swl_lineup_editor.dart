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
  String search = "";
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
          return AlertDialog(
            title: Text('Elegir mi alineación · $teamName'),
            content: SizedBox(
              width: 450,
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Text('Selecciona los jugadores. El pitcher que batea y el DH se configuran en la siguiente pantalla.'),
                  const SizedBox(height: 8),
                  Text('Pitcher titular: ${roster[working.pitcherId]?.name ?? "Sin asignar"}'),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar jugador por nombre, número o ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => setDialogState(() => search = value),
                  ),
                  const SizedBox(height: 8),
                  Text('${batting.length}/13 bateadores seleccionados'),
                  const SizedBox(height: 6),
                  for (final player in roster.values.where((player) {
                    final query = search.trim().toLowerCase();
                    return query.isEmpty ||
                        player.name.toLowerCase().contains(query) ||
                        player.number.toString().toLowerCase().contains(query) ||
                        player.universalId.toLowerCase().contains(query);
                  }))
                    CheckboxListTile(
                      key: ValueKey('roster-${player.playerId}'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(player.playerId),
                      title: Text('${player.name} · #${player.number}'),
                      subtitle: Text(player.positionLabel),
                      onChanged: (!working.pitcherBats &&
                                  working.pitcherId == player.playerId &&
                                  !selected.contains(player.playerId)) ||
                              (!selected.contains(player.playerId) &&
                                  working.batting.length >= 13)
                          ? null
                          : (checked) => update(() {
                              working.setBatting(player.playerId, checked == true);
                              if (checked != true &&
                                  working.designatedId == player.playerId) {
                                working.designatedId = null;
                              }
                            }),
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
                child: Text('CONTINUAR · ${batting.length} SELECCIONADOS'),
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
    final batting = widget.draft.batting;
    if (to > from) to -= 1; // Flutter's destination includes the removed row.
    if (to == from || to < 0 || to >= batting.length) return;
    final moved = batting.removeAt(from);
    batting.insert(to, moved);
    setState(() {
      final nonBatters = widget.draft.selected
          .where((id) => !batting.contains(id)).toList();
      widget.draft.selected
        ..clear()
        ..addAll(batting)
        ..addAll(nonBatters);
    });
    widget.onChanged?.call(widget.draft);
  }

  void _assignPosition(String id, String? position) {
    setState(() {
      if (position == 'DH') {
        widget.draft.assign(id, null);
        widget.draft.pitcherBats = false;
        final pitcher = widget.draft.pitcherId;
        if (pitcher != null) widget.draft.selected.remove(pitcher);
        widget.draft.designatedId = id;
      } else {
        widget.draft.assign(id, position);
        if (widget.draft.designatedId == id) widget.draft.designatedId = null;
      }
    });
    widget.onChanged?.call(widget.draft);
  }

  @override
  Widget build(BuildContext context) {
    final batting = widget.draft.batting;
    final error = widget.draft.validate();
    final pitcher = widget.draft.pitcherId;
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(title: const Text('Orden al bate · desliza para ordenar')),
      body: SafeArea(
        child: Column(
          children: [
            if (pitcher != null)
              SwitchListTile(
                title: const Text('El pitcher batea'),
                subtitle: Text(widget.roster[pitcher]?.name ?? 'Pitcher titular'),
                value: widget.draft.pitcherBats,
                onChanged: (value) {
                  setState(() {
                    if (value && !widget.draft.selected.contains(pitcher)) {
                      if (widget.draft.selected.length >= 13) return;
                      widget.draft.selected.add(pitcher);
                    }
                    if (!value) widget.draft.selected.remove(pitcher);
                    widget.draft.pitcherBats = value;
                    if (value) widget.draft.designatedId = null;
                  });
                  widget.onChanged?.call(widget.draft);
                },
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text('Elige DH en el selector de posición. Mantén presionado el icono para deslizar el orden.'),
            ),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: batting.length,
                onReorder: _reorder,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final id = batting[index];
                  return ListTile(
                    key: ValueKey(id),
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(widget.roster[id]!.name),
                    subtitle: Text('Habitual: ${widget.roster[id]!.positionLabel}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 116,
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: widget.draft.designatedId == id
                                ? 'DH' : (widget.draft.positions[id] ?? ''),
                            items: [
                              const DropdownMenuItem(
                                value: '', child: Text('Sin posición', style: TextStyle(fontSize: 11)),
                              ),
                              if (!widget.draft.pitcherBats && id != pitcher)
                                const DropdownMenuItem(value: 'DH', child: Text('DH')),
                              for (final pos in swlDefensivePositions)
                                DropdownMenuItem(value: pos, child: Text(pos)),
                            ],
                            onChanged: (value) => _assignPosition(
                              id, value == '' ? null : value,
                            ),
                          ),
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
