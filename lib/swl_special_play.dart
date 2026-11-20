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
}) {
  switch (action) {
    case 'GHOST_RUNNER':
      if (state.inning < 6 || state.second)
        throw StateError('Segunda debe estar libre, desde la sexta.');
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
      return state.runnerOut(base: source ?? 0);
    case 'RUNNER_MOVE':
      if (source == null ||
          !swlBaseOccupied(state, source) ||
          destination == null ||
          destination < 0 ||
          destination > 3) {
        throw StateError('Origen o destino inválido.');
      }
      if (source == destination) return state;
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
