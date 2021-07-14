--
-- Grade IBGE em uma nova representação, ingestão a partir da grade original. Ver makefile para o processo completo.
--

-- -- -- -- -- -- -- -- -- -- --
-- Processo de ingestão completo:

CREATE or replace FUNCTION grid_ibge.censo2010_info_load(p_tabgrade text) RETURNS text AS $f$
DECLARE
  q0 text;
  r0 int;
BEGIN
  q0 := $$
   coredata AS (
    SELECT quadrante, pop,
         substr(id_unico,1,4)='200M' AS is_200m,
         round(CASE WHEN pop>0 THEN 100.0*fem::real/pop::real ELSE 0.0 END)::smallint AS pop_fem_perc,
         dom_ocu,
         round( ST_X(geom2) ) gx,
         round( ST_Y(geom2) ) gy,
         geom
    FROM (
     SELECT *, ST_Transform( ST_Centroid(geom), 952019 ) AS geom2 FROM tg
    ) t
   ),
   ins AS (
   INSERT INTO grid_ibge.censo2010_info(xy, is_200m, pop, pop_fem_perc, dom_ocu)
     SELECT grid_ibge.coordinate_encode(gx::bigint,gy::bigint), is_200m, pop, pop_fem_perc, dom_ocu::smallint
     FROM coredata
     ORDER BY 1
   RETURNING 1
   )
   SELECT COUNT(*) FROM ins
 $$;
 EXECUTE format(
    'WITH tg AS (SELECT * FROM %s), %s'
    ,  p_tabgrade, q0
 ) INTO r0;
 -- ... and EXECUTE DROP!
 RETURN p_tabgrade||': '|| r0::text || ' itens inseridos';
END;
$f$ LANGUAGE PLpgSQL;
COMMENT ON FUNCTION grid_ibge.censo2010_info_load
 IS 'Insere todas as células de um quadrante da Grade Estatística IBGE.';

SELECT  grid_ibge.censo2010_info_load(table_name)
FROM information_schema.tables
WHERE table_schema='public' AND table_name LIKE 'grade_id%'
ORDER BY table_name
;
-- DROP FUNCTION grid_ibge.censo2010_info_load;
-- COPY grid_ibge.censo2010_info TO '/tmp/grid_ibge_censo2010_info.csv' CSV HEADER;
