--
-- Grade IBGE em uma nova representação, minimalista, mais leve para o banco de dados, e com "custo geometria" opcional.
-- Representação orientada às coordenadas XY dos centroides das células da grade.
--

CREATE or replace FUNCTION iIF(
    condition boolean,       -- IF condition
    true_result anyelement,  -- THEN
    false_result anyelement  -- ELSE
    -- See https://stackoverflow.com/a/53750984/287948
) RETURNS anyelement AS $f$
  SELECT CASE WHEN condition THEN true_result ELSE false_result END
$f$  LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION iif
  IS 'Immediate IF. Sintax sugar for the most frequent CASE-WHEN. Avoid with text, need explicit cast.'
;
-- -- -- --
-- Operações de preparo, não precisam ser repetidas, podem ser removidas destescript:

CREATE EXTENSION IF NOT EXISTS postgis;

DROP SCHEMA IF EXISTS gridtools CASCADE;
DROP SCHEMA IF EXISTS grid_ibge CASCADE;

-- SRID number convention for Project DigitalGuard-BR:
INSERT into spatial_ref_sys (srid, auth_name, auth_srid, proj4text, srtext)
VALUES (
  952019,
  'BR:IBGE',
  52019,
  '+proj=aea +lat_0=-12 +lon_0=-54 +lat_1=-2 +lat_2=-22 +x_0=5000000 +y_0=10000000 +ellps=WGS84 +units=m +no_defs',
  $$PROJCS[
"Conica_Equivalente_de_Albers_Brasil",
GEOGCS["GCS_SIRGAS2000",
DATUM["D_SIRGAS2000",
SPHEROID["Geodetic_Reference_System_of_1980",6378137,298.2572221009113]],
PRIMEM["Greenwich",0],
UNIT["Degree",0.017453292519943295]],
PROJECTION["Albers"],
PARAMETER["standard_parallel_1",-2],
PARAMETER["standard_parallel_2",-22],
PARAMETER["latitude_of_origin",-12],
PARAMETER["central_meridian",-54],
PARAMETER["false_easting",5000000],
PARAMETER["false_northing",10000000],
UNIT["Meter",1]
]$$
  )
ON CONFLICT DO NOTHING;

---------------------

CREATE SCHEMA IF NOT EXISTS gridtools;
CREATE SCHEMA IF NOT EXISTS grid_ibge;

CREATE TABLE grid_ibge.censo2010_info (
  xy bigint NOT NULL PRIMARY KEY,  -- "x*10000000 + y" como centroide de célula de 1 km
  is_200m boolean NOT NULL, -- exceção ao 1km, célula de 200 metros, espaço urbano.
  pop int NOT NULL,   -- população total dentro da célula
  pop_fem_perc smallint NOT NULL -- CHECK(pop_fem_perc BETWEEN 0 AND 100), percentual da população feminina
);

-------------------

--CREATE MATERIALIZED VIEW grid_ibge.kx_censo2010_geomcell AS -- xy, quadrante, geom.
--CREATE UNIQUE INDEX grid_ibge_kx_censo2010_geomcell
--  ON grid_ibge.kx_censo2010_geomcell (xy);
--CREATE MATERIALIZED VIEW grid_ibge.kx_censo2010_geomcenter AS -- xy, quadrante, geom.
--CREATE UNIQUE INDEX grid_ibge_kx_censo2010_geomcenter
--  ON grid_ibge.kx_censo2010_geomcenter (xy);


CREATE FUNCTION gridtools.draw_squarecell(
  cx int, -- Center X
  cy int, -- Center Y
  d int,  -- diâmetro do circulo inscrito
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019         -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
  SELECT CASE WHEN p_translate THEN ST_Transform(geom,4326) ELSE geom END
  FROM (
    SELECT ST_GeomFromText( format(
     'POLYGON((%s %s,%s %s,%s %s,%s %s,%s %s))',
          cx-d,cy-d, cx-d,cy+d, cx+d,cy+d, cx+d,cy-d, cx-d,cy-d
     ), p_srid) AS geom
  ) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION gridtools.draw_squarecell(int,int,int,boolean,int)
  IS 'Draws a square-cell centered on the requested point, with requested radius (half side) and optional translation and SRID.'
;

CREATE or replace FUNCTION gridtools.draw_squarecell(
  cXY bigint, -- centro XY da célula codificado no ID
  d int,  -- diâmetro do circulo inscrito
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019         -- SRID da grade (default IBGE)
) RETURNS geometry AS $wrap$
  SELECT gridtools.draw_squarecell( x::int, (cXY-x*10000000::bigint)::int, $2, $3, $4 )
  FROM ( floor(cxy/10000000::bigint) x ) t
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION gridtools.draw_squarecell(bigint,int,boolean,int)
  IS 'Wrap to draw_squarecell(int,int,*).'
;





----------------------------

DROP VIEW IF EXISTS vw_grade_ibge_rebuild;
CREATE or replace VIEW vw_grade_ibge_rebuild AS

10000000

  SELECT '1KME'|| substr(gx::text,1,4) ||'N'|| substr(gy::text,1,4) AS nome_1km,
         'ID_'|| LPAD(ibge_prefix::text, 2, '0') AS quadrante,
         pop - fem AS masc,
         *,
         ibge_grid_cell(gx,gy,500,true) AS boxgeom
  FROM (
    SELECT *, ROUND(pop*pop_fem_perc::real/100.0)::int AS fem
    FROM grid_ibge.censo2010_center
  ) t
;
DROP VIEW IF EXISTS vwid45_grade_ibge_rebuild;
CREATE or replace VIEW vwid45_grade_ibge_rebuild AS
  SELECT * FROM vw_grade_ibge_rebuild WHERE ibge_prefix=45
;

-----------------------------


-----  INGEST:
CREATE or replace FUNCTION grade_ibge_load(p_tabgrade text) RETURNS text AS $f$
DECLARE
  q0 text;
  r0 int;
BEGIN
  q0 := $$
   coredata AS (
    SELECT quadrante, pop, -- nome_1km,
         substr(id_unico,1,4)='200M' AS is_200m
         round(CASE WHEN pop>0 THEN 100.0*pop_fem::real/pop::real ELSE 0.0 END)::smallint AS pop_fem_perc,
         round(ST_x(ST_Transform(geom,952019)))::int gx,  --??
         round(st_y(ST_Transform(geom,952019)))::int gy,
         geom
    FROM (
     SELECT quadrante, id_unico, ST_Centroid(geom) AS geom FROM tg ORDER BY 1,2
    ) t
   ),
   ins AS (
   INSERT INTO grade_ibge_1kmcenters(ibge_prefix, pop, pop_fem_perc, is_200m, gx, gy, geom)
     SELECT substr(quadrante,4)::smallint, pop, pop_fem_perc, is_urban, gx, gy, geom
     FROM coredata
   RETURNING 1
   )
   SELECT COUNT(*) FROM ins
 $$;
 EXECUTE format(
    'WITH tg AS (SELECT quadrante, id_unico, masc, fem, pop, geom FROM %s), %s'
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
