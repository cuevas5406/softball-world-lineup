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
  /// 0 = anota, 1/2/3 = base de destino. No se permite dejar un
  /// corredor en la misma base ni retroceder; tampoco ocupar dos veces
  /// una base. El bateador alcanza la base indicada por [batterBase].
  /// Esta previsualización no sustituye la operación atómica del servidor.
  SwlPlayState hit({required int batterBase, int? firstTo,
    int? secondTo, int? thirdTo}) {
    _validateGameState();
    if (batterBase < 1 || batterBase > 4) {
      throw ArgumentError('La base del bateador debe estar entre 1 y 4');
    }
    if (first != (firstTo != null) || second != (secondTo != null) ||
        third != (thirdTo != null)) {
      throw StateError('Debe indicarse destino para cada corredor presente');
    }
    // Un jonrón válido obliga a anotar a todos los corredores en base.
    // Rechazar destinos distintos evita dejar bases ocupadas tras el HR.
    if (batterBase == 4 &&
        [firstTo, secondTo, thirdTo].whereType<int>().any((d) => d != 0)) {
      throw StateError('En un jonrón todos los corredores deben anotar');
    }
    final destinations = <int>[batterBase, if (firstTo != null) firstTo,
      if (secondTo != null) secondTo, if (thirdTo != null) thirdTo];
    // Un corredor puede conservar su base si no está forzado a avanzar.
    // Primera siempre está forzada por el bateador; segunda lo está si
    // primera estaba ocupada; tercera si primera y segunda lo estaban.
    if ((firstTo != null && firstTo != 0 && firstTo < 2) ||
        (secondTo != null && secondTo != 0 &&
            secondTo < (first ? 3 : 2)) ||
        (thirdTo != null && thirdTo != 0 &&
            thirdTo < (first && second ? 4 : 3))) {
      throw StateError('Avance forzado incumplido o corredor retrocediendo');
    }
    // El bateador solo puede anotar con 4 (jonrón); los corredores
    // existentes solo pueden anotar con 0. Evita dos convenciones
    // incompatibles que podrían generar carreras erróneas en el RPC.
    if ([firstTo, secondTo, thirdTo].whereType<int>()
        .any((d) => d < 0 || d > 3)) {
      throw ArgumentError('Destino de corredor fuera de rango (0 a 3)');
    }
    // 4 representa home para el bateador; 0 representa home para
    // corredores existentes. Ambos suman una carrera.
    final occupied = destinations.where((d) => d >= 1 && d <= 3).toList();
    if (occupied.toSet().length != occupied.length) {
      throw StateError('Dos corredores no pueden ocupar la misma base');
    }
    final runs = destinations.where((d) => d == 0 || d == 4).length;
    return copy(balls: 0, strikes: 0,
      first: occupied.contains(1), second: occupied.contains(2),
      third: occupied.contains(3),
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
