# V5.3 — Historial descriptivo de jugadas

El historial de la sala en vivo ahora consulta `event_data` además de los campos existentes. Los hits registrados mediante `swl_v53_apply_hit` se muestran como sencillo, doble, triple o jonrón con las carreras confirmadas por el servidor. Los hits manuales antiguos se distinguen de los hits completos.

Esto **no** equivale a estadísticas individuales: los eventos actuales no contienen identificación persistente de bateador/corredores. No se deben atribuir hits o carreras a peloteros sin un identificador validado y alineaciones persistentes.

No se cambió Supabase LAB ni producción. Flutter no se ha compilado en este entorno.
