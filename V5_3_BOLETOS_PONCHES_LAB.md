# Boletos y ponches integrados en LAB

El RPC `swl_v53_record_play` ahora interpreta la cuarta BALL como boleto (avance forzado, carrera con bases llenas) y el tercer STRIKE como ponche (out, cambio de mitad al tercero). Las carreras del boleto se asignan al inning en la misma transacción. La pantalla Flutter solicita confirmación en ambos casos.

**Límites:** sin estadísticas individuales, corredores identificados, foul con dos strikes, dropped third strike, ni reglas completas de softball. No usar en partido oficial. La función SQL fue actualizada en LAB, pero no se ejecutó una jugada autenticada ni se compiló Flutter.
