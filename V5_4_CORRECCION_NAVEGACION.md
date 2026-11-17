# V5.4 — Corrección inicial de navegación y PIN

## Cambios en Flutter
- Se eliminó el selector visual «PARTIDO POR PIN / PRUEBA LOCAL»; Pizarra abre el lobby real.
- El PIN ingresado desde Inicio se entrega al lobby, que ejecuta `swl_v5_join_game`.
- El acceso rápido «Crear partido» abre el formulario real en lugar de anunciar un PIN aleatorio que no se guarda.
- Se valida el formato de PIN real `SWL-` + seis dígitos.
- Se retiraron algunos rótulos técnicos de la vista deportiva sin modificar la lógica de anotación.

## Limitaciones importantes
- No se modificó Supabase, no se ejecutó SQL ni se desplegó nada.
- No se compiló la APK ni se ejecutaron pruebas Flutter en este entorno.
- La creación real actual requiere que ambos equipos estén registrados y seleccionados; un rival escrito manualmente en otros formularios no equivale necesariamente a un equipo persistente.
- La autorización de managers, las alineaciones y la sincronización entre dispositivos deben probarse en LAB.
- La pizarra real existente no es idéntica a la pizarra avanzada de demostración; esta corrección prioriza impedir que se confundan los dos sistemas.

## Prueba sugerida
1. Compilar rama de pruebas en GitHub Actions.
2. Instalar APK en ambos dispositivos.
3. Crear partido desde Pizarra con dos equipos registrados y anotar PIN de seis dígitos.
4. Unirse desde Inicio o desde Pizarra con el PIN.
5. Verificar ambos managers, nombres reales y acceso a sus alineaciones.
