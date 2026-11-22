import 'swl_play_rules.dart';

bool swlBaseOccupied(SwlPlayState state, int base) => switch (base) {
  1 => state.first,
  2 => state.second,
  3 => state.third,
  _ => false,
};

/// Previsualización para los menús en vivo. La escritura requiere un RPC
/// transaccional que vuelva a aplicar las mismas comprobaciones.
SwlPlayState swlPreviewSpecial(
  SwlPlayState state,
  String action, {
  int? source,
  int? destination,
  int? firstTo,
  int? secondTo,
  int? thirdTo,
  int regulationInnings = 6,
}) {
  // Rechazar estados corruptos antes de simular cualquier jugada especial.
  if (state.balls < 0 || state.balls > 3 ||
      state.strikes < 0 || state.strikes > 2 ||
      state.outs < 0 || state.outs > 2 ||
      state.inning < 1 || state.homeRuns < 0 || state.awayRuns < 0) {
    throw StateError('Estado de partido inválido.');
  }
  switch (action) {
    case 'GHOST_RUNNER':
      if (regulationInnings < 1) throw StateError('Entradas reglamentarias inválidas.');
      if (state.inning <= regulationInnings || state.outs != 0 ||
          state.balls != 0 || state.strikes != 0 ||
          state.first || state.second || state.third ||
          state.homeRuns != state.awayRuns)
        throw StateError('Corredor fantasma solo al inicio de extras empatados y con bases vacías.');
      return state.copy(second: true);
    case 'SACRIFICE_FLY':
      if (!state.third || state.outs >= 2 || thirdTo != 0) {
        throw StateError(
          'El sacrificio requiere carrera desde tercera y menos de dos outs.',
        );
      }
      final moves = [
        firstTo,
        secondTo,
        thirdTo,
      ].whereType<int>().map((base) => base == 0 ? 4 : base).toList();
      for (var index = 1; index < moves.length; index++) {
        if (moves[index] < moves[index - 1])
          throw StateError('Un corredor no puede rebasar a otro.');
      }
      return state.sacrificeFly(
        firstTo: firstTo,
        secondTo: secondTo,
        thirdTo: thirdTo,
      );
    case 'DOUBLE_PLAY':
      return state.batterRunnerDoublePlay(runnerBase: source ?? 0);
    case 'RUNNER_REPLACE':
      if (!swlBaseOccupied(state, source ?? 0))
        throw StateError('No hay corredor en esa base.');
      return state;
    case 'RUNNER_OUT':
      if (source == null || !swlBaseOccupied(state, source) ||
          destination == null || destination < 0 || destination > 3 ||
          (destination != 0 && destination < source)) {
        throw StateError('Origen o lugar del out inválido.');
      }
      return state.runnerOut(base: source);
    case 'RUNNER_MOVE':
      if (source == null ||
          !swlBaseOccupied(state, source) ||
          destination == null ||
          destination < 0 ||
          destination > 3) {
        throw StateError('Origen o destino inválido.');
      }
      if (source == destination) {
        throw StateError('El corredor debe avanzar a una base distinta.');
      }
      if (destination != 0 && destination < source) {
        throw StateError('Un corredor no puede retroceder de base.');
      }
      final effectiveDestination = destination == 0 ? 4 : destination;
      final low = source < effectiveDestination ? source : effectiveDestination;
      final high = source > effectiveDestination
          ? source
          : effectiveDestination;
      for (var base = low; base <= high; base++) {
        if (base != source && swlBaseOccupied(state, base)) {
          throw StateError(
            'Hay un corredor en el destino o entre ambas bases.',
          );
        }
      }
      return state.copy(
        first: destination == 1 || (source != 1 && state.first),
        second: destination == 2 || (source != 2 && state.second),
        third: destination == 3 || (source != 3 && state.third),
        homeRuns: state.homeRuns + (!state.isTop && destination == 0 ? 1 : 0),
        awayRuns: state.awayRuns + (state.isTop && destination == 0 ? 1 : 0),
      );
    default:
      throw StateError('Jugada especial desconocida.');
  }
}
