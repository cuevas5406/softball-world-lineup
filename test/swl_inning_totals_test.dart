import 'package:flutter_test/flutter_test.dart';
import '../lib/swl_inning_totals.dart';
void main() {
  const empty = SwlInningTotals(home: [], away: []);
  test('Carrera visitante en alta de primera', () {
    final t = empty.record(inningBefore:1,topBefore:true,
      inningAfter:1,topAfter:true,homeBefore:0,awayBefore:0,
      homeAfter:0,awayAfter:1);
    expect(t.away,[1]); expect(t.home,[0]);
  });
  test('Carrera local en baja y cambio a segunda', () {
    final t = empty.record(inningBefore:1,topBefore:false,
      inningAfter:2,topAfter:true,homeBefore:0,awayBefore:0,
      homeAfter:2,awayAfter:0);
    expect(t.home,[2]); expect(t.away,[0]);
  });
  test('Tercer out sin carrera conserva entrada previa', () {
    final t = empty.record(inningBefore:1,topBefore:true,
      inningAfter:1,topAfter:false,homeBefore:0,awayBefore:0,
      homeAfter:0,awayAfter:0);
    expect(t.home,[0]); expect(t.away,[0]);
  });
  test('Rechaza carrera del equipo que no batea', () {
    expect(() => empty.record(inningBefore:1,topBefore:true,
      inningAfter:1,topAfter:true,homeBefore:0,awayBefore:0,
      homeAfter:1,awayAfter:0),throwsStateError);
  });
  test('Rechaza salto de entrada', () {
    expect(() => empty.record(inningBefore:1,topBefore:true,
      inningAfter:3,topAfter:true,homeBefore:0,awayBefore:0,
      homeAfter:0,awayAfter:0),throwsStateError);
  });
  test('Rechaza marcador desactualizado frente al desglose', () {
    const totals = SwlInningTotals(home:[1], away:[2]);
    expect(() => totals.record(inningBefore:2,topBefore:true,
      inningAfter:2,topAfter:true,homeBefore:1,awayBefore:1,
      homeAfter:1,awayAfter:2),throwsStateError);
  });
  test('Rechaza entradas futuras', () {
    const totals = SwlInningTotals(home:[0,0],away:[0,0]);
    expect(() => totals.record(inningBefore:1,topBefore:true,
      inningAfter:1,topAfter:true,homeBefore:0,awayBefore:0,
      homeAfter:0,awayAfter:0),throwsStateError);
  });
  test('Acepta continuidad de carreras en segunda entrada', () {
    const totals = SwlInningTotals(home:[1],away:[2]);
    final next = totals.record(inningBefore:2,topBefore:true,
      inningAfter:2,topAfter:true,homeBefore:1,awayBefore:2,
      homeAfter:1,awayAfter:3);
    expect(next.home,[1,0]); expect(next.away,[2,1]);
  });

}
