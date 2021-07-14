--
-- Grade IBGE em uma nova representação, minimalista, mais leve para o banco de dados, e com "custo geometria" opcional.
-- Representação orientada às coordenadas XY dos centroides das células da grade.
--

-- -- -- --
-- Operações de preparo, não precisam ser repetidas, podem ser removidas destescript:

CREATE extension IF NOT EXISTS postgis;
DROP SCHEMA IF EXISTS grid_ibge CASCADE;
CREATE SCHEMA IF NOT EXISTS grid_ibge;

-----

CREATE TABLE grid_ibge.censo2010_info (
  xy bigint NOT NULL PRIMARY KEY,  -- x*100000000 + y como centroide de celula de 1 km
  is_200m boolean NOT NULL,        -- excecao ao 1km, celula de 200 metros, espaço urbano.
  pop int NOT NULL,   -- população total dentro da célula
  pop_fem_perc smallint NOT NULL, -- CHECK(pop_fem_perc BETWEEN 0 AND 100), percentual da população feminina
  dom_ocu smallint NOT NULL
);

------

CREATE FUNCTION grid_ibge.coordinate_encode(x bigint, y bigint) RETURNS bigint AS $f$
  SELECT x*100000000::bigint + y
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.coordinate_encode(bigint,bigint)
  IS 'Encodes two valid-range BigInts into one BigInt'
;
CREATE FUNCTION grid_ibge.coordinate_encode(x int, y int) RETURNS bigint AS $wrap$
  SELECT grid_ibge.coordinate_encode(x::bigint, y::bigint)
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.coordinate_encode(int,int)
  IS 'Encodes two valid-range Integers into one BigInt'
;

CREATE FUNCTION grid_ibge.coordinate_decode(xy bigint) RETURNS int[] AS $f$
  SELECT array[ x::int,  (xy - 100000000::bigint * x::bigint)::int]
  FROM ( SELECT floor(xy/100000000::bigint) as x ) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.coordinate_decode(bigint)
  IS 'Decodes a XY valid-range bigint into two integer coordinates, as array'
;
/* TEST with grade_id45, grade_id04, grade_id60, grade_id69, grade_id93:
 SELECT x,y, xy
 FROM (
  SELECT round( ST_x(geom) )::int x, round( ST_y(geom) )::int y
  FROM ( SELECT ST_Transform(  ST_centroid(geom),  952019) AS geom FROM grade_id45 ) t1
 ) t2, LATERAL grid_ibge.coordinate_decode(  grid_ibge.coordinate_encode(x,y)  ) as xy
 WHERE xy[1]!=x OR xy[2]!=y;
*/

CREATE MATERIALIZED VIEW grid_ibge.mvw_censo2010_info_Xsearch AS
  SELECT DISTINCT (grid_ibge.coordinate_decode(xy))[1] AS x
  FROM grid_ibge.censo2010_info
;
CREATE INDEX mvw_censo2010_info_xsearch_xbtree ON grid_ibge.mvw_censo2010_info_xsearch(x);

CREATE MATERIALIZED VIEW grid_ibge.mvw_censo2010_info_Ysearch AS
  SELECT DISTINCT (grid_ibge.coordinate_decode(xy))[2] AS y
  FROM grid_ibge.censo2010_info
;
CREATE INDEX mvw_censo2010_info_ysearch_ybtree ON grid_ibge.mvw_censo2010_info_Ysearch(y);

-----

CREATE FUNCTION grid_ibge.search_cell(p_x int, p_y int) RETURNS bigint AS $f$
 SELECT grid_ibge.coordinate_encode(t1x.x, t1y.y)
 FROM (
  SELECT x FROM (
    (
      SELECT x
      FROM grid_ibge.mvw_censo2010_info_Xsearch
      WHERE x >= p_x ORDER BY x LIMIT 1
    )  UNION ALL (
      SELECT x
      FROM grid_ibge.mvw_censo2010_info_Xsearch
      WHERE x < p_x ORDER BY x DESC LIMIT 1
    )
  ) t0x
  ORDER BY abs(p_x-x) LIMIT 1
) t1x, (
  SELECT y FROM (
    (
      SELECT y
      FROM grid_ibge.mvw_censo2010_info_Ysearch
      WHERE y >= p_y ORDER BY y LIMIT 1
    )  UNION ALL (
      SELECT y
      FROM grid_ibge.mvw_censo2010_info_Ysearch
      WHERE y < p_y ORDER BY y DESC LIMIT 1
    )
  ) t0y
  ORDER BY abs(p_y-y) LIMIT 1
) t1y
$f$ LANGUAGE SQL IMMUTABLE;


-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Reproduzindo a grade original a partir da compacta:

CREATE or replace FUNCTION grid_ibge.xy_to_quadrante(
  x int, -- X, first coordinate of IBGE's Albers Projection
  y int -- Y, second coordinate of IBGE's Albers Projection
) RETURNS int AS $f$
DECLARE
  dx0 int; dy0 int; -- deltas
  i0 int; j0 int;   -- level0 coordinates
  ij int;           -- i0 and j0 as standard quadrant-indentifier.
BEGIN
  dx0 := x - 2800000;  dy0 := y - 7350000; -- encaixa na box dos quadrantes
  -- reduzir 15 e 23,  não são válidos aqui:
  i0 := floor( 15.341::real * dx0::real/7800000.0::real )::int;
  j0 := floor( 23.299::real * dy0::real/12350000.0::real )::int;
  ij := i0 + j0*10;
  IF ij NOT IN ( -- confere se entre os 54 quadrantes do território brasileiro
        4,13,14,15,23,24,25,26,27,33,34,35,36,37,39,42,43,44,45,46,47,50,51,52,53,54,55,56,
        57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,80,81,82,83,84,85,92,93
      ) THEN
    RETURN NULL;
  END IF;
  RETURN ij;
END
$f$ LANGUAGE plpgsql IMMUTABLE;

CREATE FUNCTION grid_ibge.xy_to_quadrante(p_xy bigint) RETURNS int AS $wrap$
  SELECT grid_ibge.xy_to_quadrante(xy[1],xy[2])
  FROM ( SELECT grid_ibge.coordinate_decode(p_xy) xy ) t
$wrap$ LANGUAGE SQL IMMUTABLE;

------

CREATE FUNCTION grid_ibge.draw_cell(
  cx int,  -- Center X
  cy int,  -- Center Y
  d int,   -- diâmetro do circulo inscrito
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
SELECT CASE WHEN p_translate THEN ST_Transform(geom,4326) ELSE geom END
FROM (
  SELECT ST_GeomFromText( format(
    'POLYGON((%s %s,%s %s,%s %s,%s %s,%s %s))',
    cx-d,cy-d, cx-d,cy+d, cx+d,cy+d, cx+d,cy-d, cx-d,cy-d
  ), p_srid) AS geom
) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(int,int,int,boolean,int)
  IS 'Draws a square-cell centered on the requested point, with requested radius (half side) and optional translation and SRID.'
;

CREATE FUNCTION grid_ibge.draw_cell(
  cXY int[], -- centro XY da célula codificado no ID
  d int,    -- diâmetro do circulo inscrito
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $wrap$
  SELECT grid_ibge.draw_cell( cXY[1], cXY[2], $2, $3, $4 )
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(int[],int,boolean,int)
  IS 'Wrap to draw_squarecell(int,int,*).'
;

CREATE FUNCTION grid_ibge.draw_cell(
  cXY bigint, -- centro XY da célula codificado no ID
  d int,    -- diâmetro do circulo inscrito
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $wrap$
  SELECT grid_ibge.draw_cell( xy[1], xy[2], $2, $3, $4 )
  FROM (SELECT grid_ibge.coordinate_decode(cXY) xy ) t
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(bigint,int,boolean,int)
  IS 'Wrap to draw_squarecell(int,int,*) using XY key instead coordinates.'
;

----------------------------

--round( ST_x(ST_Transform(geom,952019)) + iif(is_200m,-100,-500) )::int x,
--round( ST_y(ST_Transform(geom,952019)) + iif(is_200m,+100,-500) )::int y

-- DROP VIEW grid_ibge.vw_original_ibge_rebuild;
CREATE VIEW grid_ibge.vw_original_ibge_rebuild AS
  SELECT xy as gid,
         'idunico' AS id_unico, -- revisar
         'nome_1km' AS nome_1km,  --revisar
         grid_ibge.xy_to_quadrante(xy) quadrante,
         pop-fem AS masc,
         fem,
         pop,
         dom_ocu,
         grid_ibge.draw_cell(xy, CASE WHEN is_200m THEN 200 ELSE 1000 END) geom
  FROM (
   SELECT *,
          ROUND(pop*pop_fem_perc::real/100.0)::int AS fem
          --,grid_ibge.coordinate_decode(xy) x_y
   FROM grid_ibge.censo2010_info
  ) t
;


/*
  SELECT '1KME'|| substr(gx::text,1,4) ||'N'|| substr(gy::text,1,4) AS nome_1km,
         'ID_'|| LPAD(ibge_prefix::text, 2, '0') AS quadrante,
         pop - fem AS masc,
         *,
         ibge_grid_cell(gx,gy,500,true) AS boxgeom
  FROM (
    SELECT *, ROUND(pop*pop_fem_perc::real/100.0)::int AS fem
    FROM grid_ibge.censo2010_info
  ) t
;

DROP VIEW IF EXISTS vwid45_grade_ibge_rebuild;
CREATE or replace VIEW vwid45_grade_ibge_rebuild AS
  SELECT * FROM vw_grade_ibge_rebuild WHERE ibge_prefix=45
;
*/

-----------------------------

--CREATE MATERIALIZED VIEW grid_ibge.kx_censo2010_geomcell AS -- xy, quadrante, geom.
--CREATE UNIQUE INDEX grid_ibge_kx_censo2010_geomcell
--  ON grid_ibge.kx_censo2010_geomcell (xy);
--CREATE MATERIALIZED VIEW grid_ibge.kx_censo2010_geomcenter AS -- xy, quadrante, geom.
--CREATE UNIQUE INDEX grid_ibge_kx_censo2010_geomcenter
--  ON grid_ibge.kx_censo2010_geomcenter (xy);


-----
-- CHECK BY NAME: WHERE NOT( substr(nome_1km,5,4)=substr(gx::text,1,4) AND substr(nome_1km,10,4)=substr(gy::text,1,4) );
