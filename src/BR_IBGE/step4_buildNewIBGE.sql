--
-- Grade IBGE em uma nova representação, mais leve para o banco de dados,
-- baseada apenas nos centroides das células de 1km da grade.
--

DROP TABLE IF EXISTS grade_ibge_1kmcenters cascade;
CREATE TABLE grade_ibge_1kmcenters (
  gid serial NOT NULL PRIMARY KEY,
  ibge_prefix smallint NOT NULL CHECK(ibge_prefix::smallint BETWEEN 0 AND 99),
  pop int NOT NULL,
  pop_fem_perc smallint NOT NULL CHECK(pop_fem_perc BETWEEN 0 AND 100),
  is_urban boolean NOT NULL,
  gx int,
  gy int,
  geom geometry,  -- centro da célula
  UNIQUE(gx,gy)
);

CREATE or replace VIEW vw_grade_ibge_rebuild AS
  SELECT '1KME'|| substr(gx::text,1,4) ||'N'|| substr(gy::text,1,4) AS nome_1km,
         'ID_'|| LPAD(ibge_prefix::text, 2, '0') AS quadrante,
         pop - fem AS masc,
         *,
         ST_Envelope(
            --ST_Transform(  ST_Buffer(ST_Transform(geom,952019),500),  4326  )
            ST_Transform(  ST_Buffer(ST_SetSRID(ST_MakePoint(gx+0,gy+0),952019),495),  4326  )
       )
         AS boxgeom
  FROM (
    SELECT *, ROUND(pop*pop_fem_perc::real/100.0)::int AS fem
    FROM grade_ibge_1kmcenters
  ) t
;
DROP VIEW IF EXISTS vwid45_grade_ibge_rebuild;
CREATE or replace VIEW vwid45_grade_ibge_rebuild AS
  SELECT * FROM vw_grade_ibge_rebuild WHERE ibge_prefix=45
;


-----  INGEST:
CREATE or replace FUNCTION grade_ibge_load(p_tabgrade text) RETURNS text AS $f$
DECLARE
  q0 text;
  r0 int;
BEGIN
  q0 := $$
   coredata AS (
    SELECT quadrante, pop, -- nome_1km,
         round(CASE WHEN pop>0 THEN 100.0*pop_fem::real/pop::real ELSE 0.0 END)::smallint AS pop_fem_perc,
         -- (pop_masc+pop_fem)=pop AS check_popsum,
         is_urban,
         round(ST_x(ST_Transform(geom,952019)))::int gx,  --??
         round(st_y(ST_Transform(geom,952019)))::int gy,
         geom
    FROM (
     SELECT quadrante, nome_1km,
         COUNT(*)>1 AS is_urban, -- 25 subcells
         SUM(masc) AS pop_masc,
         SUM(fem)  AS pop_fem,
         SUM(pop)  AS pop,
         ST_Centroid( ST_Collect(geom) ) AS geom
     FROM tg
     GROUP BY quadrante, nome_1km
     ORDER BY 2
    ) t
   ), ins AS (
   INSERT INTO grade_ibge_1kmcenters(ibge_prefix, pop, pop_fem_perc, is_urban, gx, gy, geom)
     SELECT substr(quadrante,4)::smallint, pop, pop_fem_perc, is_urban, gx, gy, geom
     FROM coredata
   RETURNING 1
   )
   SELECT COUNT(*) FROM ins
 $$;
 EXECUTE format(
    'WITH tg AS (SELECT quadrante, nome_1km, masc, fem, pop, geom FROM %s), %s'
    ,  p_tabgrade, q0
 ) INTO r0;
 -- ... and EXECUTE DROP!
 RETURN p_tabgrade||': '|| r0::text || ' itens inseridos';
END;
$f$ LANGUAGE PLpgSQL;
COMMENT ON FUNCTION grade_ibge_load
 IS 'Insere um quadrante da grade IBGE.';
-----
-- CHECK BY NAME: WHERE NOT( substr(nome_1km,5,4)=substr(gx::text,1,4) AND substr(nome_1km,10,4)=substr(gy::text,1,4) );

-- complete ingestion process:
SELECT  grade_ibge_load(table_name)
FROM information_schema.tables
WHERE table_schema='public' AND table_name LIKE 'grade_id%'
ORDER BY table_name
;

DROP FUNCTION grade_ibge_load;
