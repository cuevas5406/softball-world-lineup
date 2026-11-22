# V5.7 — Jonrón y contrato RPC

- La función propuesta `swl_v57_batted_ball` admite `p_batter_base=4`: suma una carrera del bateador, exige que los corredores ocupantes anoten y no intenta escribir una cuarta posición en los arreglos de bases.
- La misma RPC admite ahora hits sin outs (sencillo, doble, triple y jonrón) y hits con outs.
- La pantalla dirige todos los hits reales por `HIT_WITH_OUT` hacia la RPC V5.7.
- `swl_live_lobby.dart` envía exclusivamente los cinco parámetros definidos por la función para HIT_WITH_OUT/ERROR, con los avances dentro de `p_data`; se evita el rechazo PGRST202 por parámetros planos adicionales.
- Se mantuvieron los demás flujos de anotación.

**Estado:** comprobaciones estáticas Python, no Dart/Flutter ni PostgreSQL. Las funciones no se instalaron en LAB y no se compiló APK. Producción intacta.
