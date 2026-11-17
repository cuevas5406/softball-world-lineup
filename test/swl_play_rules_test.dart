import 'package:flutter_test/flutter_test.dart';
import '../lib/swl_play_rules.dart';
void main() {
  SwlPlayState state({int balls=3, int strikes=2, int outs=0,
    bool top=true, bool first=false, bool second=false, bool third=false}) =>
    SwlPlayState(balls: balls, strikes: strikes, outs: outs, inning: 1,
      homeRuns: 0, awayRuns: 0, isTop: top, first: first,
      second: second, third: third);
  test('Boleto con bases vacías ocupa primera', () {
    final s=state().walk();
    expect(s.first, true); expect(s.second, false);
    expect(s.awayRuns, 0); expect(s.balls, 0);
  });
  test('Boleto con corredor en segunda no lo fuerza', () {
    final s=state(second:true).walk();
    expect(s.first, true); expect(s.second, true);
    expect(s.third, false);
  });
  test('Boleto con primera y segunda fuerza tercera', () {
    final s=state(first:true,second:true).walk();
    expect(s.third, true); expect(s.awayRuns, 0);
  });
  test('Boleto con bases llenas anota carrera visitante', () {
    final s=state(first:true,second:true,third:true).walk();
    expect(s.awayRuns, 1); expect(s.homeRuns, 0);
  });
  test('Boleto con bases llenas anota carrera local', () {
    final s=state(top:false,first:true,second:true,third:true).walk();
    expect(s.homeRuns, 1);
  });
  test('Ponche con dos outs cambia de alta a baja', () {
    final s=state(outs:2,first:true).strikeout();
    expect(s.isTop, false); expect(s.inning, 1);
    expect(s.outs, 0); expect(s.first, false);
  });
  test('Ponche en baja con dos outs avanza entrada', () {
    final s=state(top:false,outs:2).strikeout();
    expect(s.isTop, true); expect(s.inning, 2);
  });
  test('No se permite boleto prematuro', () {
    expect(() => state(balls:2).walk(), throwsStateError);
  });
  test('Sencillo con bases vacías deja bateador en primera', () {
    final s=state(balls:1,strikes:1).hit(batterBase:1);
    expect(s.first, true); expect(s.awayRuns, 0);
    expect(s.balls, 0); expect(s.strikes, 0);
  });
  test('Doble con corredor en primera que anota', () {
    final s=state(first:true).hit(batterBase:2,firstTo:0);
    expect(s.second, true); expect(s.first, false);
    expect(s.awayRuns, 1);
  });
  test('Jonrón con bases llenas suma cuatro carreras', () {
    final s=state(first:true,second:true,third:true).hit(
      batterBase:4,firstTo:0,secondTo:0,thirdTo:0);
    expect(s.awayRuns, 4); expect(s.first, false);
    expect(s.second, false); expect(s.third, false);
  });
  test('Rechaza dos corredores en la misma base', () {
    expect(() => state(first:true).hit(batterBase:2,firstTo:2),
      throwsStateError);
  });
  test('Rechaza hit sin destino de corredor existente', () {
    expect(() => state(first:true).hit(batterBase:1), throwsStateError);
  });
  test('Rechaza corredor que permanece en primera', () {
    expect(() => state(first:true).hit(batterBase:2,firstTo:1),
      throwsStateError);
  });

  test('Robo de segunda conserva conteo de bateador', () {
    final s=state(balls:2,strikes:1,first:true)
        .advanceRunners(firstTo:2);
    expect(s.first, false); expect(s.second, true);
    expect(s.balls, 2); expect(s.strikes, 1);
  });
  test('Avance desde tercera anota sin cambiar conteo', () {
    final s=state(third:true).advanceRunners(thirdTo:0);
    expect(s.awayRuns, 1); expect(s.third, false);
  });
  test('Rechaza dos corredores en segunda', () {
    expect(() => state(first:true,second:true)
        .advanceRunners(firstTo:2,secondTo:2), throwsStateError);
  });
  test('Rechaza avance sin declarar todos los corredores', () {
    expect(() => state(first:true,second:true)
        .advanceRunners(firstTo:2), throwsStateError);
  });
  test('Rechaza retroceso de tercera a segunda', () {
    expect(() => state(third:true)
        .advanceRunners(thirdTo:2), throwsStateError);
  });

  test('Elevado de sacrificio anota corredor de tercera', () {
    final s=state(third:true,balls:1,strikes:1)
        .sacrificeFly(thirdTo:0);
    expect(s.awayRuns, 1); expect(s.outs, 1);
    expect(s.balls, 0); expect(s.strikes, 0);
  });
  test('Elevado de sacrificio conserva corredor que no avanza', () {
    final s=state(first:true,third:true)
        .sacrificeFly(firstTo:1,thirdTo:0);
    expect(s.first, true); expect(s.third, false);
    expect(s.awayRuns, 1);
  });
  test('Tercer out en elevado cambia la mitad', () {
    final s=state(outs:2,third:true).sacrificeFly(thirdTo:3);
    expect(s.isTop, false); expect(s.outs, 0);
    expect(s.third, false);
  });
  test('No acredita carrera en tercer out del bateador', () {
    expect(() => state(outs:2,third:true)
        .sacrificeFly(thirdTo:0), throwsStateError);
  });
  test('Rechaza ocupación duplicada tras elevado', () {
    expect(() => state(first:true,second:true)
        .sacrificeFly(firstTo:2,secondTo:2), throwsStateError);
  });

  test('Cogido robando primera: elimina corredor y conserva conteo', () {
    final s=state(balls:2,strikes:1,first:true).runnerOut(base:1);
    expect(s.first,false);expect(s.outs,1);
    expect(s.balls,2);expect(s.strikes,1);
  });
  test('Corredor retirado en segunda conserva corredores restantes', () {
    final s=state(first:true,second:true).runnerOut(base:2);
    expect(s.first,true);expect(s.second,false);expect(s.outs,1);
  });
  test('Tercer out en alta limpia bases y cambia a baja', () {
    final s=state(outs:2,first:true,third:true).runnerOut(base:3);
    expect(s.isTop,false);expect(s.inning,1);expect(s.outs,0);
    expect(s.first,false);expect(s.third,false);
  });
  test('Tercer out en baja avanza entrada', () {
    final s=state(top:false,outs:2,second:true).runnerOut(base:2);
    expect(s.isTop,true);expect(s.inning,2);
  });
  test('No se puede retirar corredor inexistente', () {
    expect(() => state().runnerOut(base:1),throwsStateError);
  });
  test('Rechaza base fuera de rango', () {
    expect(() => state(first:true).runnerOut(base:4),throwsArgumentError);
  });

  test('Doble play con cero outs registra dos outs', () {
    final s = state(first:true, balls:2, strikes:1)
        .batterRunnerDoublePlay(runnerBase:1);
    expect(s.outs, 2); expect(s.first, false);
    expect(s.balls, 0); expect(s.strikes, 0);
  });
  test('Doble play con un out termina media entrada', () {
    final s = state(outs:1, first:true, third:true)
        .batterRunnerDoublePlay(runnerBase:1);
    expect(s.outs, 0); expect(s.isTop, false);
    expect(s.first, false); expect(s.third, false);
  });
  test('Doble play exige corredor real', () {
    expect(() => state().batterRunnerDoublePlay(runnerBase:1), throwsStateError);
  });
  test('Doble play rechaza dos outs previos', () {
    expect(() => state(outs:2, first:true)
        .batterRunnerDoublePlay(runnerBase:1), throwsStateError);
  });
  test('Doble play no elimina otros corredores con cero outs', () {
    final s = state(first:true, third:true)
        .batterRunnerDoublePlay(runnerBase:1);
    expect(s.third, true); expect(s.awayRuns, 0);
  });

  test('Hit rechaza corredor que usa 4 en vez de 0 para anotar', () {
    expect(() => state(first:true).hit(batterBase:1,firstTo:4),
      throwsArgumentError);
  });
  test('Hit permite jonrón de bateador con corredor que anota con 0', () {
    final s=state(first:true).hit(batterBase:4,firstTo:0);
    expect(s.awayRuns, 2);
    expect(s.first, false);
  });
  test('Avance de corredores rechaza conteo de outs inválido', () {
    expect(() => state(outs:3,first:true).advanceRunners(firstTo:2),
      throwsStateError);
  });

  test('Jonrón con corredor en primera exige que anote', () {
    expect(() => state(first:true).hit(batterBase:4,firstTo:2),
      throwsStateError);
  });
  test('Jonrón con bases llenas no deja corredores en base', () {
    final s = state(first:true,second:true,third:true)
      .hit(batterBase:4,firstTo:0,secondTo:0,thirdTo:0);
    expect(s.awayRuns, 4);
    expect(s.first || s.second || s.third, false);
  });

  test('Boleto rechaza outs inválidos', () {
    expect(() => state(outs:3).walk(), throwsStateError);
  });
  test('Hit rechaza strikes inválidos', () {
    expect(() => state(strikes:3).hit(batterBase:1), throwsStateError);
  });
  test('Ponche rechaza inning inválido', () {
    final s = SwlPlayState(balls:0,strikes:2,outs:0,inning:0,
      homeRuns:0,awayRuns:0,isTop:true,first:false,second:false,third:false);
    expect(() => s.strikeout(), throwsStateError);
  });
  test('Doble play rechaza marcador negativo', () {
    final s = SwlPlayState(balls:0,strikes:0,outs:0,inning:1,
      homeRuns:-1,awayRuns:0,isTop:true,first:true,second:false,third:false);
    expect(() => s.batterRunnerDoublePlay(runnerBase:1), throwsStateError);
  });

  test('Sencillo permite corredor en segunda quedarse si no forzado', () {
    final next = state(second: true).hit(batterBase: 1, secondTo: 2);
    expect(next.first, true); expect(next.second, true);
  });
  test('Sencillo obliga corredor de primera a avanzar', () {
    expect(() => state(first: true).hit(batterBase: 1, firstTo: 1), throwsStateError);
  });
  test('Bases llenas fuerzan corredor de tercera a anotar', () {
    expect(() => state(first: true, second: true, third: true)
      .hit(batterBase: 1, firstTo: 2, secondTo: 3, thirdTo: 3), throwsStateError);
  });
  test('Sencillo permite corredor de tercera quedarse', () {
    final next = state(third: true).hit(batterBase: 1, thirdTo: 3);
    expect(next.first, true); expect(next.third, true);
  });

}
