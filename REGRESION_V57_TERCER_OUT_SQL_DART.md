# V5.7 — regresión del tercer out

Se agregaron dos pruebas Dart a `test/swl_play_rules_test.dart`: 
- Tercer out no forzado en segunda, con carreras desde primera y tercera: únicamente la carrera de tercera puede acreditarse al confirmar el tiempo.
- Tercer out forzado: cero carreras aunque se marque la confirmación.

Se añadió `test/test_v57_batted_ball_contract.py` con tres comprobaciones de orden de validación, regla del tercer out y persistencia de eventos/versiones. **Las tres pruebas Python pasaron** en este entorno.

**Las pruebas Dart no se ejecutaron**, ya que no hay Flutter/Dart SDK disponible aquí. Tampoco se instalaron migraciones SQL en LAB ni se compiló la APK. Producción intacta.
