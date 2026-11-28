# Revisión de la instalación de Deshacer DP

El conector devolvió «SQL execution was declined» para la transacción de instalación y pruebas. La comprobación posterior confirmó que `swl_private.v57_dp_undo_state` no existe y que la huella de la RPC de deshacer sigue siendo `9d08bf611ad3bee4eda2f3c574d1deeb`. Las pruebas SQL de esta entrega no se ejecutaron en LAB.

La inspección de solo lectura confirmó que `public.swl_v53_batting_stats(uuid)` cuenta `plate_appearances` mediante `completed` y no excluye los eventos referenciados por `UNDO_OUT`. El DP avanzado guarda `plate_appearance_completed=true` y `14386f9` conserva el evento original para auditoría, por lo que esa consulta seguiría contando la PA. La consulta privada de bateo oficial sí excluye las correcciones y la de pitcheo oficial usa la fila que la propuesta elimina al deshacer.

`excluir_anulaciones_bateo_legacy_propuesta.sql` es una extensión separada, pendiente de autorización. Conserva las reglas existentes del agregado y filtra la versión anulada. Si se autoriza, instalar ambos cambios y correr `pruebas_ampliadas.sql` bajo un savepoint, con la comprobación de integridad de SWL-378859 antes del commit. La prueba ampliada cubre restauración completa, uno, dos y tres corredores, carreras, cambio de mitad, mánager original, rechazo al rival, versión obsoleta, repetición, agregados y out sencillo.

Los dos avisos adicionales corresponden al import de Material del nuevo widget y de su prueba. El SDK instalado los clasifica como información de deprecación. No son errores de compilación.
