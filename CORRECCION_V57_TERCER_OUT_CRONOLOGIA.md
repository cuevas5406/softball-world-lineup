# Corrección de carreras en tercer out — V5.7

**Archivo:** `propuestas_lab/13_v57_batazos_y_defensa.sql`

**Hallazgo:** La previsualización Dart (`lib/swl_play_rules.dart`, `hit`) solo considera, en una jugada de tiempo con tercer out no forzado, las carreras de corredores situados por delante del corredor retirado. El SQL previo contabilizaba todas las carreras si el mánager marcaba `count_runs_on_third_out`, creando una discrepancia entre pizarra previa y resultado persistido.

**Corrección:** Al llegar al tercer out, después de comprobar que solo hubo un out de corredor, que no fue forzado y que existe confirmación explícita, el servidor cuenta únicamente los corredores que partieron de bases superiores a la del corredor retirado y terminaron en home. Los otros casos mantienen cero carreras.

**Limitación:** Esto es una regla conservadora para la vista previa; la cronología exacta de una jugada de tiempo compleja necesitaría un modelo explícito de orden de anotación y outs.

**Estado:** cambio en código SQL propuesto, **sin instalación en LAB** ni prueba de PostgreSQL/Flutter. Producción intacta.
