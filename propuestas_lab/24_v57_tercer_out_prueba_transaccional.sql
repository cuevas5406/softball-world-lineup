-- Prueba transaccional de la regla del tercer out. No altera partidos.
-- Ejecutada correctamente en Supabase LAB el 2026-11-23.
BEGIN;
DO $$
DECLARE
  origins integer[]; destinations integer[]; retired integer; confirmed boolean;
  forced boolean; scored integer; expected integer; scenario integer; i integer;
BEGIN
 FOR scenario IN 1..5 LOOP
  CASE scenario
   WHEN 1 THEN origins:=ARRAY[1,0,1]; destinations:=ARRAY[-3,NULL,0]; confirmed:=true; expected:=1;
   WHEN 2 THEN origins:=ARRAY[1,1,1]; destinations:=ARRAY[0,-3,0]; confirmed:=true; expected:=0;
   WHEN 3 THEN origins:=ARRAY[1,0,1]; destinations:=ARRAY[-3,NULL,0]; confirmed:=false; expected:=0;
   WHEN 4 THEN origins:=ARRAY[1,1,1]; destinations:=ARRAY[0,-4,0]; confirmed:=true; expected:=1;
   WHEN 5 THEN origins:=ARRAY[1,1,1]; destinations:=ARRAY[0,-4,0]; confirmed:=false; expected:=0;
  END CASE;
  retired:=array_position(ARRAY[coalesce(destinations[1]<0,false),coalesce(destinations[2]<0,false),coalesce(destinations[3]<0,false)],true);
  forced:=destinations[retired]=-(retired+1)
    AND (retired=1 OR (origins[1]=1 AND (retired=2 OR origins[2]=1)));
  scored:=0;
  IF confirmed AND NOT forced THEN
   FOR i IN (retired+1)..3 LOOP
    IF destinations[i]=0 THEN scored:=scored+1; END IF;
   END LOOP;
  END IF;
  IF scored<>expected THEN RAISE EXCEPTION 'scenario %: expected %, got %',scenario,expected,scored; END IF;
 END LOOP;
END $$;
ROLLBACK;
