/// Motor puro para previsualizar jugadas antes de enviarlas a LAB.
/// No modifica Supabase y NO reemplaza la validación transaccional del servidor.
class SwlPlayState {
  final int balls, strikes, outs, inning, homeRuns, awayRuns;
  final bool isTop, first, second, third;
  const SwlPlayState({required this.balls, required this.strikes,
    required this.outs, required this.inning, required this.homeRuns,
    required this.awayRuns, required this.isTop, required this.first,
    required this.second, required this.third});

  SwlPlayState copy({int? balls, int? strikes, int? outs, int? inning,
    int? homeRuns, int? awayRuns, bool? isTop, bool? first,
    bool? second, bool? third}) => SwlPlayState(
      balls: balls ?? this.balls, strikes: strikes ?? this.strikes,
      outs: outs ?? this.outs, inning: inning ?? this.inning,
      homeRuns: homeRuns ?? this.homeRuns, awayRuns: awayRuns ?? this.awayRuns,
      isTop: isTop ?? this.isTop, first: first ?? this.first,
      second: second ?? this.second, third: third ?? this.third);

  /// Verifica invariantes antes de simular una jugada local.
  /// El servidor sigue siendo la autoridad para registrar el resultado.
  void _validateGameState() {
    if (balls < 0 || balls > 3 || strikes < 0 || strikes > 2 ||
        outs < 0 || outs > 2 || inning < 1 ||
        homeRuns < 0 || awayRuns < 0) {
      throw StateError('Estado de partido inválido');
    }
  }

  /// Cuarta bola: solo avanzan los corredores forzados.
  SwlPlayState walk() {
    _validateGameState();
    if (balls != 3) throw StateError('El boleto requiere tres bolas previas');
    final scores = first && second && third ? 1 : 0;
    return copy(balls: 0, strikes: 0, first: true,
      second: first || second, third: (first && second) || third,
      homeRuns: homeRuns + (!isTop ? scores : 0),
      awayRuns: awayRuns + (isTop ? scores : 0));
  }

  /// Hit con destinos explícitos para los corredores presentes.
  /// 0 = anota, 1/2/3 = base y -2/-3/-4 = out en segunda, tercera o home.
  /// Solo se adjudican carreras en un tercer out de tiempo confirmado.
  /// Esta previsualización no sustituye la operación atómica del servidor.
  SwlPlayState hit({required int batterBase, int? firstTo,
    int? secondTo, int? thirdTo, bool countRunsOnThirdOut = false}) {
    _validateGameState();
    if (batterBase < 1 || batterBase > 4) {
      throw ArgumentError.value(batterBase, 'batterBase', 'Base del bateador inválida.');
    }
    final moves = [firstTo, secondTo, thirdTo];
    final bases = [first, second, third];
    final outCount = moves.whereType<int>().where((d) => d < 0).length;
    if (outs + outCount > 3) throw StateError('La jugada supera los tres outs.');
    if (batterBase == 4 && moves.whereType<int>().any((d) => d != 0)) {
      throw StateError('En un jonrón todos los corredores anotan.');
    }
    final occupied = <int>{if (batterBase < 4) batterBase};
    var previous = batterBase;
    var runs = batterBase == 4 ? 1 : 0;
    for (var i = 0; i < moves.length; i++) {
      final dest = moves[i];
      if (bases[i] != (dest != null)) throw StateError('Indica cada avance.');
      if (dest == null) continue;
      if (dest > 3) throw ArgumentError.value(dest, 'dest', 'Destino inválido.');
      if (dest < 0) {
        if (-dest <= i + 1 || -dest > 4) throw StateError('Base del out inválida.');
        continue;
      }
      if (dest == 0) {
        previous = 4;
        runs++;
      } else {
        final minimum = i + 1 + ((i == 0 || (first && (i == 1 || second))) ? 1 : 0);
        if (dest < minimum || dest > 3 || dest < previous || !occupied.add(dest)) {
          throw StateError('Avance, orden o base de destino inválidos.');
        }
        previous = dest;
      }
    }
    final terminal = outs + outCount == 3;
    if (terminal) {
      final retired = moves.indexWhere((dest) => dest != null && dest < 0);
      final forced = moves[retired] == -(retired + 2) &&
          (retired == 0 || (first && (retired == 1 || second)));
      runs = countRunsOnThirdOut && outCount == 1 && !forced
          ? moves.skip(retired + 1).where((dest) => dest == 0).length : 0;
    }
    return copy(balls: 0, strikes: 0, outs: terminal ? 0 : outs + outCount,
      inning: terminal && !isTop ? inning + 1 : inning,
      isTop: terminal ? !isTop : isTop,
      first: !terminal && occupied.contains(1),
      second: !terminal && occupied.contains(2),
      third: !terminal && occupied.contains(3),
      homeRuns: homeRuns + (isTop ? 0 : runs),
      awayRuns: awayRuns + (isTop ? runs : 0));
  }

  /// Avance de corredores sin bateador (robo, wild pitch, passed ball).
  /// 0 = anota; 1/2/3 = nueva base. Los corredores que no avanzan
  /// pueden conservar su base. El tipo oficial de jugada lo determina
  /// el anotador y deberá validarse en el servidor.
  SwlPlayState advanceRunners({int? firstTo, int? secondTo, int? thirdTo}) {
    _validateGameState();
    if (outs < 0 || outs > 2 || balls < 0 || balls > 3 ||
        strikes < 0 || strikes > 2) {
      throw StateError('Conteo de partido inválido');
    }
    if (first != (firstTo != null) || second != (secondTo != null) ||
        third != (thirdTo != null)) {
      throw StateError('Debe indicarse destino para cada corredor presente');
    }
    final moves = <int, int>{
      if (firstTo != null) 1: firstTo,
      if (secondTo != null) 2: secondTo,
      if (thirdTo != null) 3: thirdTo,
    };
    for (final entry in moves.entries) {
      if (entry.value != 0 &&
          (entry.value < entry.key || entry.value > 3)) {
        throw StateError('Destino de corredor inválido');
      }
    }
    final occupied = moves.values.where((v) => v != 0).toList();
    if (occupied.toSet().length != occupied.length) {
      throw StateError('Dos corredores no pueden ocupar la misma base');
    }
    final runs = moves.values.where((v) => v == 0).length;
    return copy(first: occupied.contains(1),
      second: occupied.contains(2), third: occupied.contains(3),
      homeRuns: homeRuns + (isTop ? 0 : runs),
      awayRuns: awayRuns + (isTop ? runs : 0));
  }

  /// Elevado de sacrificio: el bateador es out y los corredores pueden
  /// avanzar o anotar. Si es el tercer out, no se contabilizan carreras
  /// en esta previsualización (no modela apelaciones ni jugadas de tiempo).
  /// Destino 0 = anota; 1,2,3 = base; se debe informar cada corredor.
  SwlPlayState sacrificeFly({int? firstTo, int? secondTo, int? thirdTo}) {
    _validateGameState();
    if (outs < 0 || outs > 2) throw StateError('Outs inválidos');
    if (first != (firstTo != null) || second != (secondTo != null) ||
        third != (thirdTo != null)) {
      throw StateError('Debe indicarse destino para cada corredor presente');
    }
    final moves = <int, int>{
      if (firstTo != null) 1: firstTo,
      if (secondTo != null) 2: secondTo,
      if (thirdTo != null) 3: thirdTo,
    };
    for (final e in moves.entries) {
      if (e.value != 0 && (e.value < e.key || e.value > 3)) {
        throw StateError('Destino inválido');
      }
    }
    final occupied = moves.values.where((d) => d != 0).toList();
    if (occupied.toSet().length != occupied.length) {
      throw StateError('Dos corredores en una base');
    }
    if (outs == 2) {
      // El tercer out por el bateador impide carreras en esta jugada.
      if (moves.values.contains(0)) {
        throw StateError('Carrera inválida en tercer out del bateador');
      }
      return copy(balls: 0, strikes: 0, outs: 0,
        inning: isTop ? inning : inning + 1, isTop: !isTop,
        first: false, second: false, third: false);
    }
    final runs = moves.values.where((d) => d == 0).length;
    return copy(balls: 0, strikes: 0, outs: outs + 1,
      first: occupied.contains(1), second: occupied.contains(2),
      third: occupied.contains(3),
      homeRuns: homeRuns + (isTop ? 0 : runs),
      awayRuns: awayRuns + (isTop ? runs : 0));
  }

  /// Corredor retirado intentando avanzar (caught stealing/pickoff).
  /// [base] indica la base que ocupaba: 1, 2 o 3.
  /// El turno del bateador continúa con el mismo conteo, salvo que sea
  /// el tercer out, en cuyo caso se cambia de mitad de entrada.
  /// No permite sumar carreras simultáneas: esas jugadas requieren un
  /// evento compuesto y adjudicación específica del anotador.
  SwlPlayState runnerOut({required int base}) {
    _validateGameState();
    if (base < 1 || base > 3) {
      throw ArgumentError.value(base, 'base', 'Base inválida');
    }
    if (outs < 0 || outs > 2) throw StateError('Outs inválidos');
    final occupied = base == 1 ? first : base == 2 ? second : third;
    if (!occupied) throw StateError('No hay corredor en esa base');
    if (outs == 2) {
      return copy(balls: 0, strikes: 0, outs: 0,
        inning: isTop ? inning : inning + 1, isTop: !isTop,
        first: false, second: false, third: false);
    }
    return copy(outs: outs + 1,
      first: base == 1 ? false : first,
      second: base == 2 ? false : second,
      third: base == 3 ? false : third);
  }

  /// Doble play sencillo: bateador y UN corredor existente son retirados.
  /// No incluye avances ni carreras, ni pretende modelar todas las variantes
  /// de doble matanza (por ejemplo, dos corredores retirados).
  SwlPlayState batterRunnerDoublePlay({required int runnerBase}) {
    _validateGameState();
    if (runnerBase < 1 || runnerBase > 3) {
      throw ArgumentError.value(runnerBase, 'runnerBase', 'Base inválida');
    }
    if (outs < 0 || outs > 2) throw StateError('Outs inválidos');
    if (outs == 2) throw StateError('Con dos outs no pueden registrarse dos outs nuevos');
    final occupied = runnerBase == 1 ? first : runnerBase == 2 ? second : third;
    if (!occupied) throw StateError('No hay corredor en la base indicada');
    if (outs == 1) {
      return copy(balls: 0, strikes: 0, outs: 0,
        inning: isTop ? inning : inning + 1, isTop: !isTop,
        first: false, second: false, third: false);
    }
    return copy(balls: 0, strikes: 0, outs: 2,
      first: runnerBase == 1 ? false : first,
      second: runnerBase == 2 ? false : second,
      third: runnerBase == 3 ? false : third);
  }

  /// Tercer strike: ponche, con cambio de mitad en el tercer out.
  /// No contempla tercer strike no retenido; requiere evento separado.
  SwlPlayState strikeout() {
    _validateGameState();
    if (strikes != 2) throw StateError('El ponche requiere dos strikes previos');
    if (outs < 2) return copy(balls: 0, strikes: 0, outs: outs + 1);
    return copy(balls: 0, strikes: 0, outs: 0,
      inning: isTop ? inning : inning + 1, isTop: !isTop,
      first: false, second: false, third: false);
  }
}
