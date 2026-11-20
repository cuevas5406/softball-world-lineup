# Revisión de posición secundaria (propuesta, no ejecutada)

- Se normaliza la posición principal a mayúsculas y se valida su pertenencia al catálogo.
- Se impide que la posición secundaria sea igual a la principal.
- El registro falla explícitamente si la RPC anterior no devuelve el ID del pelotero; la transacción revierte el registro.
- La propuesta 12 depende de verificar en LAB la firma y retorno de `swl_register_player` y los permisos de `swl_can_manage_roster`.
- Se debe verificar también la firma de las funciones de alineación y cambio de pitcher, además de los permisos efectivos.
- No se ejecutó SQL ni se alteró Supabase. No se ejecutaron pruebas Flutter ni se compiló APK en esta revisión.
