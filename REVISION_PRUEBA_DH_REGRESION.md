# Prueba de regresión DH corregida

Se detectó que el caso `cannot send a missing or defensively assigned BD` generaba posiciones defensivas duplicadas y diez defensores, por lo que fallaba por otra razón antes de comprobar el bateador designado. Se reemplazó por una defensa válida con nueve jugadores: pitcher externo al orden, ocho jugadores defensivos en el orden y un DH sin defensa. Se comprueba rechazo del DH que ocupa defensa, aceptación del DH correcto y rechazo al asignar una posición defensiva al DH.

Se corrigió también un comentario obsoleto de otra prueba. Sin cambios de producción ni SQL. No se ejecutaron pruebas Flutter ni se compiló APK.
