import 'dart:math';
import 'package:flutter/material.dart';
import 'swl_lineup_identity.dart';

// Modelo de Bateador con su historial turno por turno del juego
class SwlScorePlayer {
  final String name;
  final String number;
  // UUID persistente del pelotero. null indica entrada local sin identidad verificada.
  final String? playerId;
  final String battingRole; // REGULAR, DH o AH
  final String defensivePosition; // P, C, 1B, 2B, 3B, SS, LF, CF, RF o SIN
  int ab;   // Turnos oficiales
  int hits; // Hits
  int bb;   // Boletos
  int rbi;  // Carreras empujadas
  List<String> gameLog; // Turno por turno del día

  SwlScorePlayer({
    required this.name,
    required this.number,
    this.playerId,
    this.battingRole = 'REGULAR',
    this.defensivePosition = 'SIN',
    this.ab = 0,
    this.hits = 0,
    this.bb = 0,
    this.rbi = 0,
    List<String>? gameLog,
  }) : gameLog = gameLog ?? [];

  // Cálculo del Promedio de Bateo (AVG)
  String get battingAverage {
    if (ab == 0) return ".---";
    final double avg = hits / ab;
    if (avg >= 1.0) return "1.000";
    return avg.toStringAsFixed(3).replaceFirst("0.", ".");
  }

  SwlScorePlayer copy() => SwlScorePlayer(
        name: name,
        number: number,
        playerId: playerId,
        battingRole: battingRole,
        defensivePosition: defensivePosition,
        ab: ab,
        hits: hits,
        bb: bb,
        rbi: rbi,
        gameLog: List.from(gameLog),
      );
}

// Modelo del SwlScorePitcher (Lanzador)
class SwlScorePitcher {
  final String name;
  final String number;
  final String teamName;
  int outsRecorded; // Se guarda en outs y se muestra como IP (ej. 4 outs = 1.1 IP)
  int strikeouts;   // Ponches (K)
  int walks;        // Bases por bolas (BB)
  int hitsAllowed;  // Hits permitidos
  int runsAllowed;  // Carreras permitidas

  SwlScorePitcher({
    required this.name,
    required this.number,
    required this.teamName,
    this.outsRecorded = 0,
    this.strikeouts = 0,
    this.walks = 0,
    this.hitsAllowed = 0,
    this.runsAllowed = 0,
  });

  // Entradas lanzadas en formato oficial (ej. 5 outs = 1.2 IP)
  String get ip {
    final int fullInnings = outsRecorded ~/ 3;
    final int remainderOuts = outsRecorded % 3;
    return "$fullInnings.$remainderOuts";
  }

  SwlScorePitcher copy() => SwlScorePitcher(
        name: name,
        number: number,
        teamName: teamName,
        outsRecorded: outsRecorded,
        strikeouts: strikeouts,
        walks: walks,
        hitsAllowed: hitsAllowed,
        runsAllowed: runsAllowed,
      );
}

class SwlScorePlayRecord {
  final int inning;
  final bool isTopInning;
  final String description;
  final String notation;
  final String batterName;

  SwlScorePlayRecord({
    required this.inning,
    required this.isTopInning,
    required this.description,
    required this.notation,
    required this.batterName,
  });
}

class SwlScoreGameSnapshot {
  final int balls;
  final int strikes;
  final int outs;
  final int inning;
  final bool isTopInning;
  final bool on1B;
  final bool on2B;
  final bool on3B;
  final List<int?> visitorInningRuns;
  final List<int?> homeInningRuns;
  final int visitorHits;
  final int homeHits;
  final int visitorErrors;
  final int homeErrors;
  final int visitorLineupIndex;
  final int homeLineupIndex;
  final List<SwlScorePlayer> visitorLineup;
  final List<SwlScorePlayer> homeLineup;
  final SwlScorePitcher visitorPitcher;
  final SwlScorePitcher homePitcher;
  final List<SwlScorePlayRecord> plays;

  SwlScoreGameSnapshot({
    required this.balls,
    required this.strikes,
    required this.outs,
    required this.inning,
    required this.isTopInning,
    required this.on1B,
    required this.on2B,
    required this.on3B,
    required this.visitorInningRuns,
    required this.homeInningRuns,
    required this.visitorHits,
    required this.homeHits,
    required this.visitorErrors,
    required this.homeErrors,
    required this.visitorLineupIndex,
    required this.homeLineupIndex,
    required this.visitorLineup,
    required this.homeLineup,
    required this.visitorPitcher,
    required this.homePitcher,
    required this.plays,
  });
}

class SwlAdvancedScoreboard extends StatefulWidget {
  const SwlAdvancedScoreboard({super.key, required this.gamePin, required this.homeTeam, required this.awayTeam});
  final String gamePin;
  final String homeTeam;
  final String awayTeam;

  @override
  State<SwlAdvancedScoreboard> createState() => _ScoreboardScreenState();
}

class _ScoreboardScreenState extends State<SwlAdvancedScoreboard> {
  late String visitorName;
  late String homeName;

  List<int?> visitorInningRuns = [0, null, null, null, null, null];
  List<int?> homeInningRuns = [null, null, null, null, null, null];

  int visitorHits = 0;
  int homeHits = 0;
  int visitorErrors = 0;
  int homeErrors = 0;

  int inning = 1;
  bool isTopInning = true;

  int balls = 0;
  int strikes = 0;
  int outs = 0;

  bool on1B = false;
  bool on2B = false;
  bool on3B = false;

  @override
  void initState() {
    super.initState();
    visitorName = widget.awayTeam;
    homeName = widget.homeTeam;
    visitorPitcher = SwlScorePitcher(name: 'Lanzador visitante', number: '-', teamName: visitorName);
    homePitcher = SwlScorePitcher(name: 'Lanzador local', number: '-', teamName: homeName);
  }

  // Lanzadores abridores
  late SwlScorePitcher visitorPitcher;
  late SwlScorePitcher homePitcher;

  // SwlScorePitcher activo en la loma (el que defiende)
  SwlScorePitcher get activePitcher => isTopInning ? homePitcher : visitorPitcher;

  List<SwlScorePlayer> visitorLineup = List.generate(9, (i) => SwlScorePlayer(name: "Bateador ${i + 1}", number: "-"));

  List<SwlScorePlayer> homeLineup = List.generate(9, (i) => SwlScorePlayer(name: "Bateador ${i + 1}", number: "-"));

  int visitorLineupIndex = 0;
  int homeLineupIndex = 0;

  SwlScorePlayer get currentBatter => isTopInning ? visitorLineup[visitorLineupIndex] : homeLineup[homeLineupIndex];

  // V5.3: configuración independiente del orden al bate en modo local.
  Future<void> _editLineup(bool visitor) async {
    if (playsLog.isNotEmpty || _history.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Configura la alineación antes de comenzar a anotar.')));
      return;
    }
    final source = visitor ? visitorLineup : homeLineup;
    final names = List.generate(13, (i) => TextEditingController(
      text: i < source.length ? source[i].name : 'Bateador ${i + 1}'));
    final numbers = List.generate(13, (i) => TextEditingController(
      text: i < source.length ? source[i].number : '-'));
    final roles = List.generate(13, (i) =>
        i < source.length ? source[i].battingRole : 'REGULAR');
    final positions = List.generate(13, (i) =>
        i < source.length ? source[i].defensivePosition : 'SIN');
    int count = source.length;
    try {
      final result = await showDialog<List<SwlScorePlayer>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            backgroundColor: const Color(0xFF16202C),
            title: Text('ALINEACIÓN · ${visitor ? visitorName : homeName}',
                style: const TextStyle(color: Colors.amber, fontSize: 17)),
            content: SizedBox(width: 440, height: 440, child: Column(children: [
              DropdownButton<int>(
                value: count,
                dropdownColor: const Color(0xFF16202C),
                style: const TextStyle(color: Colors.white),
                items: List.generate(5, (i) => DropdownMenuItem(
                  value: i + 9, child: Text('${i + 9} bateadores'))),
                onChanged: (value) => update(() => count = value ?? count),
              ),
              const Text('Defensa: P, C, 1B, 2B, 3B, SS, LF, CF, RF. DH/AH sin defensa.',
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
              const Text('Orden al bate · configuración local antes del partido',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
              Expanded(child: ListView.builder(itemCount: count, itemBuilder: (_, i) =>
                Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 465, child: Row(children: [
                  SizedBox(width: 28, child: Text('${i + 1}.',
                      style: const TextStyle(color: Colors.amber))),
                  Expanded(child: TextField(controller: names[i],
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Nombre', isDense: true,
                        labelStyle: TextStyle(color: Colors.white70)))),
                  const SizedBox(width: 6),
                  SizedBox(width: 91, child: DropdownButton<String>(
                    isExpanded: true,
                    value: roles[i],
                    dropdownColor: const Color(0xFF16202C),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    items: const [
                      DropdownMenuItem(value: 'REGULAR', child: Text('Normal')),
                      DropdownMenuItem(value: 'DH', child: Text('DH')),
                      DropdownMenuItem(value: 'AH', child: Text('AH')),
                    ],
                    onChanged: (value) => update(() =>
                        roles[i] = value ?? 'REGULAR'),
                  )),
                  const SizedBox(width: 4),
                  SizedBox(width: 62, child: DropdownButton<String>(
                    isExpanded: true,
                    value: positions[i],
                    dropdownColor: const Color(0xFF16202C),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    items: const ['SIN', 'P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF']
                        .map((position) => DropdownMenuItem(
                          value: position, child: Text(position))).toList(),
                    onChanged: (value) => update(() => positions[i] = value ?? 'SIN'),
                  )),
                  const SizedBox(width: 4),
                  SizedBox(width: 46, child: TextField(controller: numbers[i],
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: '#', isDense: true,
                        labelStyle: TextStyle(color: Colors.white70)))),
                ])))),
              )),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCELAR')),
              FilledButton(onPressed: () {
                if (List.generate(count, (i) => names[i].text.trim())
                    .any((name) => name.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Todos los bateadores deben tener nombre.')));
                  return;
                }
                final normalizedNames = List.generate(count,
                    (i) => names[i].text.trim().toLowerCase());
                if (normalizedNames.toSet().length != count) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('No repitas el mismo bateador en la alineación.')));
                  return;
                }
                final assignedNumbers = List.generate(count,
                    (i) => numbers[i].text.trim())
                    .where((number) => number.isNotEmpty && number != '-')
                    .toList();
                if (assignedNumbers.toSet().length != assignedNumbers.length) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('No repitas números de uniforme en la alineación.')));
                  return;
                }
                if (roles.take(count).where((role) => role == 'DH').length > 1) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Solo puede haber un DH por alineación.')));
                  return;
                }
                // DH y AH son roles exclusivamente ofensivos en la alineación inicial.
                // Si existe DH, el pitcher no puede ocupar un turno en este orden.
                final hasDh = roles.take(count).contains('DH');
                if (hasDh && positions.take(count).contains('P')) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Con DH, el pitcher no debe figurar como bateador.')));
                  return;
                }
                for (var i = 0; i < count; i++) {
                  if (roles[i] == 'DH' && positions[i] != 'SIN') {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('El DH no puede tener posición defensiva inicial.')));
                    return;
                  }
                }
                final assignedPositions = positions.take(count)
                    .where((position) => position != 'SIN').toList();
                if (assignedPositions.toSet().length != assignedPositions.length) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('No puedes asignar la misma posición defensiva dos veces.')));
                  return;
                }
                for (var i = 0; i < count; i++) {
                  if (roles[i] == 'AH' && positions[i] != 'SIN') {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Un AH no debe tener posición defensiva inicial.')));
                    return;
                  }
                }
                final ids = source.take(count).map((p) => p.playerId).whereType<String>().toList();
                if (ids.toSet().length != ids.length) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Hay IDs de peloteros duplicados.')));
                  return;
                }
                Navigator.pop(dialogContext, List.generate(count, (i) =>
                  SwlScorePlayer(name: names[i].text.trim(),
                    playerId: i < source.length &&
                      source[i].name == names[i].text.trim() &&
                      source[i].number == (numbers[i].text.trim().isEmpty ? '-' : numbers[i].text.trim())
                        ? source[i].playerId : null,
                    defensivePosition: positions[i],
                    battingRole: roles[i],
                    number: numbers[i].text.trim().isEmpty ? '-' : numbers[i].text.trim())));
              }, child: const Text('GUARDAR')),
            ],
          ),
        ),
      );
      if (!mounted || result == null) return;
      setState(() {
        if (visitor) { visitorLineup = result; visitorLineupIndex = 0; }
        else { homeLineup = result; homeLineupIndex = 0; }
      });
    } finally {
      for (final c in names) { c.dispose(); }
      for (final c in numbers) { c.dispose(); }
    }
  }

  // V5.3: sustitución local de bateador, sin alterar turnos ya registrados.
  Future<void> _substituteBatter(bool visitor) async {
    final lineup = visitor ? visitorLineup : homeLineup;
    int selected = visitor ? visitorLineupIndex : homeLineupIndex;
    final name = TextEditingController();
    final number = TextEditingController();
    try {
      final replacement = await showDialog<SwlScorePlayer>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            backgroundColor: const Color(0xFF16202C),
            title: const Text('SUSTITUCIÓN DE BATEADOR',
                style: TextStyle(color: Colors.amber, fontSize: 17)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<int>(
                isExpanded: true,
                value: selected,
                dropdownColor: const Color(0xFF16202C),
                style: const TextStyle(color: Colors.white),
                items: List.generate(lineup.length, (i) => DropdownMenuItem(
                  value: i,
                  child: Text('${i + 1}. ${lineup[i].name}', overflow: TextOverflow.ellipsis),
                )),
                onChanged: (value) => update(() => selected = value ?? selected),
              ),
              TextField(controller: name,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Nombre del sustituto',
                  labelStyle: TextStyle(color: Colors.white70))),
              TextField(controller: number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Número del sustituto',
                  labelStyle: TextStyle(color: Colors.white70))),
              const SizedBox(height: 8),
              const Text('El sustituto ocupará el mismo turno y rol. '
                  'Las estadísticas previas permanecen en el historial de jugadas.',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCELAR')),
              FilledButton(onPressed: () {
                final newName = name.text.trim();
                final newNumber = number.text.trim();
                if (newName.isEmpty ||
                    lineup.asMap().entries.any((entry) =>
                      entry.key != selected &&
                      entry.value.name.toLowerCase() == newName.toLowerCase()) ||
                    (newNumber.isNotEmpty && newNumber != '-' &&
                     lineup.asMap().entries.any((entry) =>
                       entry.key != selected && entry.value.number == newNumber))) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Revisa el nombre y número: no deben estar vacíos ni repetidos.')));
                  return;
                }
                Navigator.pop(dialogContext, SwlScorePlayer(
                  name: newName,
                  number: newNumber.isEmpty ? '-' : newNumber,
                  battingRole: lineup[selected].battingRole,
                  defensivePosition: lineup[selected].defensivePosition,
                ));
              }, child: const Text('SUSTITUIR')),
            ],
          ),
        ),
      );
      if (!mounted || replacement == null) return;
      _saveState();
      setState(() {
        if (visitor) {
          visitorLineup[selected] = replacement;
        } else {
          homeLineup[selected] = replacement;
        }
      });
    } finally {
      name.dispose();
      number.dispose();
    }
  }

  final List<SwlScorePlayRecord> playsLog = [];
  final List<SwlScoreGameSnapshot> _history = [];

  int get currentInningsCount => max(6, max(visitorInningRuns.length, inning));
  int get visitorTotalRuns => visitorInningRuns.whereType<int>().fold(0, (a, b) => a + b);
  int get homeTotalRuns => homeInningRuns.whereType<int>().fold(0, (a, b) => a + b);

  void _saveState() {
    _history.add(SwlScoreGameSnapshot(
      balls: balls,
      strikes: strikes,
      outs: outs,
      inning: inning,
      isTopInning: isTopInning,
      on1B: on1B,
      on2B: on2B,
      on3B: on3B,
      visitorInningRuns: List.from(visitorInningRuns),
      homeInningRuns: List.from(homeInningRuns),
      visitorHits: visitorHits,
      homeHits: homeHits,
      visitorErrors: visitorErrors,
      homeErrors: homeErrors,
      visitorLineupIndex: visitorLineupIndex,
      homeLineupIndex: homeLineupIndex,
      visitorLineup: visitorLineup.map((p) => p.copy()).toList(),
      homeLineup: homeLineup.map((p) => p.copy()).toList(),
      visitorPitcher: visitorPitcher.copy(),
      homePitcher: homePitcher.copy(),
      plays: List.from(playsLog),
    ));
    if (_history.length > 30) _history.removeAt(0);
  }

  void _undo() {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    setState(() {
      balls = last.balls;
      strikes = last.strikes;
      outs = last.outs;
      inning = last.inning;
      isTopInning = last.isTopInning;
      on1B = last.on1B;
      on2B = last.on2B;
      on3B = last.on3B;
      visitorInningRuns = List.from(last.visitorInningRuns);
      homeInningRuns = List.from(last.homeInningRuns);
      visitorHits = last.visitorHits;
      homeHits = last.homeHits;
      visitorErrors = last.visitorErrors;
      homeErrors = last.homeErrors;
      visitorLineupIndex = last.visitorLineupIndex;
      homeLineupIndex = last.homeLineupIndex;
      visitorLineup = last.visitorLineup.map((p) => p.copy()).toList();
      homeLineup = last.homeLineup.map((p) => p.copy()).toList();
      visitorPitcher = last.visitorPitcher.copy();
      homePitcher = last.homePitcher.copy();
      playsLog.clear();
      playsLog.addAll(last.plays);
    });
  }

  void _resetCount() {
    balls = 0;
    strikes = 0;
  }

  void _nextBatter() {
    if (isTopInning) {
      visitorLineupIndex = (visitorLineupIndex + 1) % visitorLineup.length;
    } else {
      homeLineupIndex = (homeLineupIndex + 1) % homeLineup.length;
    }
  }

  void _nextHalfInning() {
    _resetCount();
    on1B = false;
    on2B = false;
    on3B = false;
    outs = 0;

    if (isTopInning) {
      isTopInning = false;
      while (homeInningRuns.length < inning) {
        homeInningRuns.add(null);
      }
      homeInningRuns[inning - 1] ??= 0;
    } else {
      isTopInning = true;
      inning++;
      while (visitorInningRuns.length < inning) {
        visitorInningRuns.add(null);
      }
      while (homeInningRuns.length < inning) {
        homeInningRuns.add(null);
      }
      visitorInningRuns[inning - 1] = 0;
    }
  }

  void _addRunsToCurrentInning(int runs) {
    if (runs <= 0) return;
    activePitcher.runsAllowed += runs; // Se le cargan al lanzador en la loma
    final idx = inning - 1;
    if (isTopInning) {
      while (visitorInningRuns.length <= idx) visitorInningRuns.add(null);
      visitorInningRuns[idx] = (visitorInningRuns[idx] ?? 0) + runs;
    } else {
      while (homeInningRuns.length <= idx) homeInningRuns.add(null);
      homeInningRuns[idx] = (homeInningRuns[idx] ?? 0) + runs;
    }
  }

  // MODAL AL TOCAR EL PITCHER
  void _showPitcherDetailsModal() {
    final p = activePitcher;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(backgroundColor: Colors.amber, radius: 18, child: Icon(Icons.sports, color: Colors.black, size: 20)),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${p.name} #${p.number}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text("Lanzador de ${p.teamName}", style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              const Text("ESTADÍSTICAS DEL DÍA:", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statTile("IP (Entradas)", p.ip, Colors.amberAccent),
                  _statTile("K (Ponches)", "${p.strikeouts}", Colors.redAccent),
                  _statTile("BB (Boletos)", "${p.walks}", Colors.tealAccent),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statTile("H (Hits)", "${p.hitsAllowed}", Colors.blueAccent),
                  _statTile("C (Carreras)", "${p.runsAllowed}", Colors.orangeAccent),
                  _statTile("Outs Hechos", "${p.outsRecorded}", Colors.white70),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // MODAL AL TOCAR EL BATEADOR
  void _showBatterDetailsModal() {
    final b = currentBatter;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(backgroundColor: Colors.blueAccent, radius: 18, child: Icon(Icons.sports_baseball, color: Colors.white, size: 20)),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${b.name} #${b.number}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(isTopInning ? visitorName : homeName, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(color: Colors.white24, height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statTile("Turnos (AB)", "${b.ab}", Colors.white),
                  _statTile("Hits (H)", "${b.hits}", Colors.greenAccent),
                  _statTile("BB (Bolas)", "${b.bb}", Colors.tealAccent),
                  _statTile("PROMEDIO", b.battingAverage, Colors.amberAccent),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              const Text("TURNO POR TURNO EN ESTE JUEGO:", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: b.gameLog.isEmpty
                    ? const Center(child: Text("Aún no ha completado su primer turno.", style: TextStyle(color: Colors.white38, fontSize: 12)))
                    : ListView.builder(
                        itemCount: b.gameLog.length,
                        itemBuilder: (ctx, i) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(4)),
                                  child: Text("${i + 1}° Turno", style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(b.gameLog[i], style: const TextStyle(color: Colors.white70, fontSize: 12))),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Container(
      width: 95,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // ACCIÓN: BASE POR BOLAS (BB)
  void _recordWalk() {
    final batter = currentBatter;
    final pitcher = activePitcher;

    batter.bb++;
    pitcher.walks++; // Suma boleto al lanzador

    final String logDesc = "${inning}ra ${isTopInning ? 'Alta' : 'Baja'} · Base por Bolas (BB)";
    batter.gameLog.add(logDesc);

    playsLog.insert(0, SwlScorePlayRecord(
      inning: inning,
      isTopInning: isTopInning,
      description: "Recibió Base por Bolas (BB)",
      notation: "BB",
      batterName: "${batter.name} #${batter.number}",
    ));

    _resetCount();
    _nextBatter();

    if (on1B && on2B && on3B) {
      _addRunsToCurrentInning(1);
    } else if (on1B && on2B) {
      on3B = true;
    } else if (on1B) {
      on2B = true;
    }
    on1B = true;
  }

  // ACCIÓN: ERROR
  void _recordErrorByOpponent(String posCode, String posName) {
    _saveState();
    setState(() {
      final batter = currentBatter;
      batter.ab++;

      if (isTopInning) {
        homeErrors++;
      } else {
        visitorErrors++;
      }

      final String logDesc = "${inning}ra ${isTopInning ? 'Alta' : 'Baja'} · Llegó por Error del $posName (E$posCode)";
      batter.gameLog.add(logDesc);

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: "Llegó a salvo por Error del $posName ($posCode)",
        notation: "E$posCode",
        batterName: "${batter.name} #${batter.number}",
      ));

      _resetCount();
      _nextBatter();

      if (on1B && on2B && on3B) {
        _addRunsToCurrentInning(1);
      } else if (on1B && on2B) {
        on3B = true;
      } else if (on1B) {
        on2B = true;
      }
      on1B = true;
    });
  }

  // ACCIÓN: OUT DETALLADO
  void _recordOutWithDetails(
    String notation,
    String description, {
    bool isSacrifice = false,
    bool isDoublePlay = false,
    bool isStrikeout = false,
  }) {
    _saveState();
    setState(() {
      final batter = currentBatter;
      final pitcher = activePitcher;

      if (!isSacrifice) {
        batter.ab++;
      }

      if (isStrikeout) {
        pitcher.strikeouts++; // Ponche sumado al lanzador
      }

      final String logDesc = "${inning}ra ${isTopInning ? 'Alta' : 'Baja'} · $description ($notation)";
      batter.gameLog.add(logDesc);

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: description,
        notation: notation,
        batterName: "${batter.name} #${batter.number}",
      ));

      _resetCount();
      _nextBatter();

      if (isSacrifice && on3B) {
        _addRunsToCurrentInning(1);
        on3B = false;
      }

      if (isDoublePlay) {
        pitcher.outsRecorded += 2; // El pitcher suma 2 outs
        if (on1B) on1B = false;
        else if (on2B) on2B = false;
        else if (on3B) on3B = false;

        if (outs + 2 >= 3) {
          _nextHalfInning();
        } else {
          outs += 2;
        }
      } else {
        pitcher.outsRecorded += 1; // El pitcher suma 1 out
        if (outs < 2) {
          outs++;
        } else {
          _nextHalfInning();
        }
      }
    });
  }

  // ACCIÓN: HIT
  void recordHit(String type, String desc) {
    _saveState();
    setState(() {
      final batter = currentBatter;
      final pitcher = activePitcher;

      batter.ab++;
      batter.hits++;
      pitcher.hitsAllowed++; // El pitcher permite un hit

      if (isTopInning) {
        visitorHits++;
      } else {
        homeHits++;
      }

      final String logDesc = "${inning}ra ${isTopInning ? 'Alta' : 'Baja'} · Conectó $desc ($type)";
      batter.gameLog.add(logDesc);

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: desc,
        notation: type,
        batterName: "${batter.name} #${batter.number}",
      ));

      _resetCount();
      _nextBatter();

      int runsScored = 0;
      if (type == "H") {
        if (on3B) { runsScored++; on3B = false; }
        if (on2B) { on3B = true; on2B = false; }
        if (on1B) { on2B = true; }
        on1B = true;
      } else if (type == "H2") {
        if (on3B) { runsScored++; on3B = false; }
        if (on2B) { runsScored++; }
        if (on1B) { on3B = true; on1B = false; }
        on2B = true;
      } else if (type == "H3") {
        if (on3B) runsScored++;
        if (on2B) runsScored++;
        if (on1B) runsScored++;
        on1B = false;
        on2B = false;
        on3B = true;
      } else if (type == "HR") {
        runsScored = 1;
        if (on1B) runsScored++;
        if (on2B) runsScored++;
        if (on3B) runsScored++;
        on1B = false;
        on2B = false;
        on3B = false;
      }

      _addRunsToCurrentInning(runsScored);
    });
  }

  void _openRunnerActionModal(int base) {
    final String baseName = base == 1 ? "1ra Base" : (base == 2 ? "2da Base" : "3ra Base");

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("CORREDOR EN $baseName", style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Text("¿Qué ocurrió con este corredor?", style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 14),
              const Text("OUT EN LAS BASES (SUMA OUT Y QUITA CORREDOR):", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.cancel, color: Colors.white, size: 18),
                      label: const Text("Out Robando (CS)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _recordBaseOut(base, "CS", "Out Robando en $baseName (CS)");
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900, padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.flash_on, color: Colors.white, size: 18),
                      label: const Text("Sorprendido / Viraje", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _recordBaseOut(base, "PO", "Sorprendido en $baseName por viraje (PO)");
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text("AVANCES Y CARRERAS:", style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (base < 3)
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), padding: const EdgeInsets.symmetric(vertical: 12)),
                        icon: const Icon(Icons.directions_run, color: Colors.white, size: 18),
                        label: Text("Robó ${base == 1 ? '2da (SB)' : '3ra (SB)'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _advanceRunner(base, isSteal: true);
                        },
                      ),
                    ),
                  if (base < 3) const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.sports_baseball, color: Colors.white, size: 18),
                      label: const Text("Anotó Carrera", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _scoreRunner(base);
                      },
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 18),
                  label: const Text("Solo quitar corredor (Error de dedo / Sin out)", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _saveState();
                    setState(() {
                      if (base == 1) on1B = false;
                      if (base == 2) on2B = false;
                      if (base == 3) on3B = false;
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _recordBaseOut(int base, String notation, String description) {
    _saveState();
    setState(() {
      activePitcher.outsRecorded += 1;
      if (base == 1) on1B = false;
      if (base == 2) on2B = false;
      if (base == 3) on3B = false;

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: description,
        notation: notation,
        batterName: "Corredor en base",
      ));

      if (outs < 2) {
        outs++;
      } else {
        _nextHalfInning();
      }
    });
  }

  void _advanceRunner(int base, {bool isSteal = false}) {
    _saveState();
    setState(() {
      if (base == 1) { on1B = false; on2B = true; }
      else if (base == 2) { on2B = false; on3B = true; }

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: isSteal ? "Robó base con éxito" : "Avanzó de base",
        notation: "SB",
        batterName: "Corredor en base",
      ));
    });
  }

  void _scoreRunner(int base) {
    _saveState();
    setState(() {
      if (base == 1) on1B = false;
      if (base == 2) on2B = false;
      if (base == 3) on3B = false;

      _addRunsToCurrentInning(1);

      playsLog.insert(0, SwlScorePlayRecord(
        inning: inning,
        isTopInning: isTopInning,
        description: "Anotó carrera en jugada de corrido",
        notation: "CARRERA",
        batterName: "Corredor en base",
      ));
    });
  }

  void _openBatazoSelector() {
    String? selectedFielder;
    final bool hasRunners = on1B || on2B || on3B;
    final bool canDoublePlay = hasRunners && outs < 2;
    final bool canSacrifice = on3B && outs < 2;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: 550,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("REGISTRO DE BATAZO / JUGADA", style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),

                    const Text("FALLO AL CAMPO (OUT DE 1 TOQUE):", style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _quickOutChip(ctx, "Fallo al 8 (Center)", "F8"),
                        _quickOutChip(ctx, "Fallo al 7 (Left)", "F7"),
                        _quickOutChip(ctx, "Fallo al 9 (Right)", "F9"),
                        _quickOutChip(ctx, "Fallo al 3 (1B)", "F3"),
                        _quickOutChip(ctx, "Fallo al 4 (2B)", "F4"),
                        _quickOutChip(ctx, "Fallo al 5 (3B)", "F5"),
                        _quickOutChip(ctx, "Fallo al 6 (Siore)", "F6"),
                      ],
                    ),

                    if (canDoublePlay || canSacrifice) ...[
                      const SizedBox(height: 10),
                      const Text("JUGADAS ESPECIALES:", style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (canDoublePlay)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _recordOutWithDetails("DP", "Doble Play", isDoublePlay: true);
                              },
                              child: const Text("Doble Play (DP)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          if (canSacrifice)
                            _quickOutChip(ctx, "SF8 (Sacrificio al 8)", "SF8", isSac: true),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade900.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade800),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                "ERROR (SE LE CARGA AL CONTRARIO: ${isTopInning ? homeName.toUpperCase() : visitorName.toUpperCase()}):",
                                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _errorChip(ctx, "E5 (3ra)", "5", "3ra Base"),
                              _errorChip(ctx, "E6 (Siore)", "6", "Campocorto"),
                              _errorChip(ctx, "E4 (2da)", "4", "Segunda Base"),
                              _errorChip(ctx, "E3 (1ra)", "3", "Primera Base"),
                              _errorChip(ctx, "E1 (Picher)", "1", "Lanzador"),
                              _errorChip(ctx, "E2 (Quech)", "2", "Receptor"),
                              _errorChip(ctx, "E7 (Left)", "7", "Left Field"),
                              _errorChip(ctx, "E8 (Center)", "8", "Center Field"),
                              _errorChip(ctx, "E9 (Right)", "9", "Right Field"),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Divider(color: Colors.white24, height: 20),

                    const Text("ROLATA O TIRO A CUALQUIER BASE (2 TOQUES):", style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),

                    Text(
                      selectedFielder == null ? "1️⃣ Toca quién fildeó la pelota:" : "Pelota fildeada por: $selectedFielder",
                      style: TextStyle(color: selectedFielder == null ? Colors.white70 : Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _fielderBtn("1", "1", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                        const SizedBox(width: 4),
                        _fielderBtn("5", "5", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                        const SizedBox(width: 4),
                        _fielderBtn("6", "6", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                        const SizedBox(width: 4),
                        _fielderBtn("4", "4", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                        const SizedBox(width: 4),
                        _fielderBtn("3", "3", selectedFielder, (val) => setModalState(() => selectedFielder = val)),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      selectedFielder == null ? "2️⃣ Luego elige a dónde tiró:" : "2️⃣ ¿A qué base tiró el $selectedFielder?:",
                      style: TextStyle(color: selectedFielder != null ? Colors.amber : Colors.white30, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _targetBaseBtn(ctx, "A Home (2)", "2", "Tiro a Home", selectedFielder),
                        _targetBaseBtn(ctx, "A 1ra (3)", "3", "Tiro a Primera", selectedFielder),
                        _targetBaseBtn(ctx, "A 2da (4)", "4", "Tiro a Segunda", selectedFielder),
                        _targetBaseBtn(ctx, "A 2da (6)", "6", "Tiro a Segunda vía Siore", selectedFielder),
                        _targetBaseBtn(ctx, "A 3ra (5)", "5", "Tiro a Tercera", selectedFielder),
                        _targetBaseBtn(ctx, "Pisa base (Solo)", "U", "Out sin asistencia (Pisó la base)", selectedFielder),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _errorChip(BuildContext ctx, String label, String posCode, String posName) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6)),
      onPressed: () {
        Navigator.pop(ctx);
        _recordErrorByOpponent(posCode, posName);
      },
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _quickOutChip(BuildContext ctx, String label, String not, {bool isSac = false}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: isSac ? const Color(0xFF059669) : const Color(0xFF334155), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
      onPressed: () {
        Navigator.pop(ctx);
        _recordOutWithDetails(not, label, isSacrifice: isSac);
      },
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _fielderBtn(String label, String code, String? selected, Function(String) onSelect) {
    final isSelected = selected == code;
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.amber : const Color(0xFF0F172A),
          foregroundColor: isSelected ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          side: BorderSide(color: isSelected ? Colors.amber : Colors.white24),
        ),
        onPressed: () => onSelect(code),
        child: Text(code, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _targetBaseBtn(BuildContext ctx, String label, String baseCode, String desc, String? selectedFielder) {
    final isEnabled = selectedFielder != null;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isEnabled ? const Color(0xFF2563EB) : Colors.white10,
        foregroundColor: isEnabled ? Colors.white : Colors.white24,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
      onPressed: !isEnabled ? null : () {
        Navigator.pop(ctx);
        String finalNotation = baseCode == "U" ? "${selectedFielder}U" : "$selectedFielder-$baseCode";
        String finalDesc = baseCode == "U" ? "Rolata al $selectedFielder (Pisa la base)" : "Rolata del $selectedFielder · $desc ($finalNotation)";
        _recordOutWithDetails(finalNotation, finalDesc);
      },
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final batter = currentBatter;
    final pitcher = activePitcher;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1118),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16202C),
        elevation: 0,
        title: const Text("⚾ PIZARRA · PRUEBA LOCAL", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sustituciones',
            icon: const Icon(Icons.swap_horiz, color: Colors.amber),
            onSelected: (value) => _substituteBatter(value == 'visitor'),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'visitor', child: Text('Sustituir · $visitorName')),
              PopupMenuItem(value: 'home', child: Text('Sustituir · $homeName')),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Configurar alineaciones',
            icon: const Icon(Icons.groups, color: Colors.amber),
            onSelected: (value) => _editLineup(value == 'visitor'),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'visitor', child: Text('Alineación · $visitorName')),
              PopupMenuItem(value: 'home', child: Text('Alineación · $homeName')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.amber, size: 26),
            tooltip: "Deshacer",
            onPressed: _history.isEmpty ? null : _undo,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text('PIN: ${widget.gamePin} · SOLO DEMOSTRACIÓN LOCAL · SIN SINCRONIZACIÓN',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            _buildMlbLineScore(),
            _buildCountAndBases(),

            // BARRA INTERACTIVA: DUELO BATEADOR VS PITCHER (AMBOS CON CLIC)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                children: [
                  // 1. TARJETA CLICKEABLE DEL BATEADOR
                  Expanded(
                    flex: 6,
                    child: InkWell(
                      onTap: _showBatterDetailsModal,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16202C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueGrey.shade800),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.sports_baseball, color: Colors.amber, size: 14),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    "${batter.name} #${batter.number}",
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                const Icon(Icons.info_outline, color: Colors.white38, size: 13),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "de ${batter.ab}-${batter.hits} (${batter.battingAverage})",
                              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // 2. TARJETA CLICKEABLE DEL PITCHER EN LA LOMA
                  Expanded(
                    flex: 5,
                    child: InkWell(
                      onTap: _showPitcherDetailsModal,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16202C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueGrey.shade800),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.sports, color: Colors.tealAccent, size: 14),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    "P: ${pitcher.name}",
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                const Icon(Icons.info_outline, color: Colors.white38, size: 13),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${pitcher.ip} IP · ${pitcher.strikeouts} K",
                              style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            _buildMainButtons(),

            const SizedBox(height: 4),

            Expanded(
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF16202C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueGrey.shade800),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("HISTORIAL JUGADA A JUGADA:", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                    const Divider(color: Colors.white24, height: 10),
                    Expanded(
                      child: playsLog.isEmpty
                          ? const Center(child: Text("Esperando primera jugada...", style: TextStyle(color: Colors.white38, fontSize: 13)))
                          : ListView.builder(
                              itemCount: playsLog.length,
                              itemBuilder: (context, index) {
                                final p = playsLog[index];
                                final isHit = p.notation.startsWith("H");
                                final isError = p.notation.startsWith("E");
                                final isWalk = p.notation == "BB";
                                final isBaseOut = p.notation == "CS" || p.notation == "PO";

                                Color badgeColor = Colors.amber.shade700;
                                if (p.notation == "DP" || isBaseOut) badgeColor = Colors.red.shade700;
                                else if (isHit || p.notation == "CARRERA") badgeColor = Colors.green.shade700;
                                else if (isError) badgeColor = Colors.orange.shade800;
                                else if (isWalk) badgeColor = Colors.teal.shade700;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)),
                                        child: Text(p.notation, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "${p.inning}ra ${p.isTopInning ? 'Alta' : 'Baja'} · ${p.batterName}: ${p.description}",
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMlbLineScore() {
    final int count = currentInningsCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF16202C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade800),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 340),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24))),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: Text("EQUIPO", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  for (int i = 1; i <= count; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text(
                          "$i",
                          style: TextStyle(
                            color: inning == i ? Colors.amber : (i > 6 ? Colors.orangeAccent : Colors.white60),
                            fontWeight: inning == i ? FontWeight.bold : FontWeight.normal,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("C", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("H", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("E", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)))),
                ],
              ),
              TableRow(
                decoration: BoxDecoration(color: isTopInning ? Colors.white.withOpacity(0.04) : Colors.transparent),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                    child: Row(
                      children: [
                        if (isTopInning) const Icon(Icons.arrow_right, color: Colors.amber, size: 14),
                        Text(visitorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  for (int i = 0; i < count; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text(
                          (i < visitorInningRuns.length && visitorInningRuns[i] != null) ? "${visitorInningRuns[i]}" : "-",
                          style: TextStyle(
                            color: (i < visitorInningRuns.length && visitorInningRuns[i] != null) ? Colors.white : Colors.white24,
                            fontWeight: (i < visitorInningRuns.length && visitorInningRuns[i] != null && visitorInningRuns[i]! > 0) ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$visitorTotalRuns", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 13)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$visitorHits", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$visitorErrors", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)))),
                ],
              ),
              TableRow(
                decoration: BoxDecoration(color: !isTopInning ? Colors.white.withOpacity(0.04) : Colors.transparent),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                    child: Row(
                      children: [
                        if (!isTopInning) const Icon(Icons.arrow_right, color: Colors.amber, size: 14),
                        Text(homeName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  for (int i = 0; i < count; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text(
                          (i < homeInningRuns.length && homeInningRuns[i] != null) ? "${homeInningRuns[i]}" : "-",
                          style: TextStyle(
                            color: (i < homeInningRuns.length && homeInningRuns[i] != null) ? Colors.white : Colors.white24,
                            fontWeight: (i < homeInningRuns.length && homeInningRuns[i] != null && homeInningRuns[i]! > 0) ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$homeTotalRuns", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 13)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$homeHits", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text("$homeErrors", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountAndBases() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: const Color(0xFF16202C), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIndicator("B", balls, 3, Colors.greenAccent),
              const SizedBox(height: 5),
              _buildIndicator("S", strikes, 2, Colors.redAccent),
              const SizedBox(height: 5),
              _buildIndicator("O", outs, 2, Colors.amberAccent),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1118),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: inning > 6 ? Colors.orangeAccent : Colors.amber.shade700),
            ),
            child: Row(
              children: [
                Icon(isTopInning ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.amber, size: 26),
                Text(
                  "${inning}ra ${inning > 6 ? 'EXTRA' : (isTopInning ? 'ALTA' : 'BAJA')}",
                  style: TextStyle(color: inning > 6 ? Colors.orangeAccent : Colors.amber, fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ],
            ),
          ),
          _buildDiamond(),
        ],
      ),
    );
  }

  Widget _buildIndicator(String l, int cur, int max, Color col) {
    return Row(children: [
      SizedBox(width: 18, child: Text(l, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
      ...List.generate(max, (i) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        width: 13, height: 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: i < cur ? col : Colors.black54,
          border: Border.all(color: i < cur ? col : Colors.white24, width: 1.5),
        ),
      )),
    ]);
  }

  Widget _buildDiamond() {
    return SizedBox(
      width: 75, height: 65,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(
          top: 0,
          child: _baseNode(on2B, () {
            if (on2B) _openRunnerActionModal(2);
            else { _saveState(); setState(() => on2B = true); }
          }),
        ),
        Positioned(
          left: 4,
          top: 20,
          child: _baseNode(on3B, () {
            if (on3B) _openRunnerActionModal(3);
            else { _saveState(); setState(() => on3B = true); }
          }),
        ),
        Positioned(
          right: 4,
          top: 20,
          child: _baseNode(on1B, () {
            if (on1B) _openRunnerActionModal(1);
            else { _saveState(); setState(() => on1B = true); }
          }),
        ),
        const Positioned(bottom: 2, child: Icon(Icons.home, color: Colors.white38, size: 18)),
      ]),
    );
  }

  Widget _baseNode(bool occupied, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: pi / 4,
        child: Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: occupied ? Colors.amber : const Color(0xFF0B1118),
            borderRadius: BorderRadius.circular(2.5),
            border: Border.all(color: occupied ? Colors.white : Colors.white54, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildMainButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: _actionBtn("BOLA", const Color(0xFF10B981), () {
              _saveState();
              setState(() {
                if (balls < 3) {
                  balls++;
                } else {
                  _recordWalk();
                }
              });
            })),
            const SizedBox(width: 6),
            Expanded(child: _actionBtn("STRIKE", const Color(0xFFEF4444), () {
              _saveState();
              setState(() {
                if (strikes < 2) {
                  strikes++;
                } else {
                  _recordOutWithDetails("K", "Ponche (Tirándole)", isStrikeout: true);
                }
              });
            })),
            const SizedBox(width: 6),
            Expanded(
              child: _actionBtn("BATAZO / JUGADA", const Color(0xFFF59E0B), _openBatazoSelector),
            ),
          ]),

          const SizedBox(height: 8),

          Row(children: [
            Expanded(child: _hitBtn("H", "Sencillo", () => recordHit("H", "Sencillo (Hit)"))),
            const SizedBox(width: 6),
            Expanded(child: _hitBtn("H2", "Doble", () => recordHit("H2", "Doble"))),
            const SizedBox(width: 6),
            Expanded(child: _hitBtn("H3", "Triple", () => recordHit("H3", "Triple"))),
            const SizedBox(width: 6),
            Expanded(child: _hitBtn("HR", "Jonrón", () => recordHit("HR", "Jonrón"), isHr: true)),
          ]),
        ],
      ),
    );
  }

  Widget _actionBtn(String title, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
    );
  }

  Widget _hitBtn(String title, String subtitle, VoidCallback onTap, {bool isHr = false}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isHr ? const Color(0xFF8B5CF6) : const Color(0xFF223040),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
          Text(subtitle, style: const TextStyle(fontSize: 9, color: Colors.white60)),
        ],
      ),
    );
  }
}