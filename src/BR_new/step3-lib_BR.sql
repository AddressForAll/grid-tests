--  a proposta é funcionar com PostgreSQL padrão, mas alguns testes e teorias podem ser testados com
-- o uso de inteiros sem sinal, https://github.com/petere/pguint
-- o tipo padrao por hora é o varbit.

DROP SCHEMA IF EXISTS osmcodes_br CASCADE; -- to restart all lib and dependencies.
CREATE SCHEMA osmcodes_br;


---
CREATE or replace FUNCTION osmcodes_br.ij_to_xy(quadrante_ij int) RETURNS int[] AS $f$
  SELECT array[
    2734000 + (quadrante_ij-j0*10)*512000,  -- coordenada x0_min do quadrante (j0,i0)
    7320000 + j0*512000                     -- coordenada y0_min do quadrante (j0,i0)
  ] FROM ( SELECT quadrante_ij/10 ) t(j0)
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION osmcodes_br.ij_to_xy(int)
 IS 'Coordenadas Albers do canto inferior esquerdo (minX,minY) do quadrante, conforme seu identificador ij (j0,i0).'
;
CREATE FUNCTION osmcodes_br.quadrant_to_xybounds( quadrante_ij int ) RETURNS int[] AS $f$
  SELECT array[ ij[1], ij[2],  ij[1]+512000, ij[2]+512000 ]
  FROM ( SELECT osmcodes_br.ij_to_xy(quadrante_ij) ) t(ij)
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.quadrant_to_xybounds(int)
 IS 'Extremidades da diagonal da origem do quadrante_ij, expressas em Albers.'
;
CREATE FUNCTION osmcodes_br.quadrant_to_xybounds( geohash_or_prefix text ) RETURNS int[] AS $wrap$
  SELECT osmcodes_br.quadrant_to_xybounds( substr(geohash_or_prefix,1,2)::int )
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.quadrant_to_xybounds(text)
 IS 'Wrap function. Extremidades da diagonal da origem do quadrante_ij, expressas em Albers.'
;

----
-- -- -- --
-- Geradores de geometria da célula:

CREATE FUNCTION OSMcodes_br.cellgeom_xy( x int, y int, r int DEFAULT 256000 ) RETURNS geometry AS $f$
    SELECT ST_GeomFromText( format(
     'POLYGON((%s %s,%s %s,%s %s,%s %s,%s %s))',
          x-r,y-r, x-r,y+r, x+r,y+r, x+r,y-r, x-r,y-r
     ), 952019) AS geom
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.cellgeom_xy(int,int,int)
 IS 'Geometria da célula expressa em projeção Albers (xy), no input e output. Centro e raio inscrito são inputs.'
;
CREATE FUNCTION OSMcodes_br.cellgeom_xy( xy int[], r int DEFAULT 256000 ) RETURNS geometry AS $wrap$
  SELECT OSMcodes_br.cellgeom_xy(xy[1], xy[2], r)
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION OSMcodes_br.cellgeom_xy_bycorner( cx int, cy int, s int DEFAULT 512000 ) RETURNS geometry AS $f$
    SELECT ST_GeomFromText( format(
     'POLYGON((%s %s,%s %s,%s %s,%s %s,%s %s))',
          cx,cy, cx,cy+s, cx+s,cy+s, cx+s,cy, cx,cy
     ), 952019) AS geom
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.cellgeom_xy_bycorner(int,int,int)
 IS 'Geometria da célula expressa em projeção Albers (xy), no input e output. Canto inferior esqerdo (min XY) e lado (side size) são inputs.'
;

CREATE FUNCTION OSMcodes_br.cellgeom_from_ij( quadrante_ij int ) RETURNS geometry AS $f$
  SELECT OSMcodes_br.cellgeom_xy_bycorner(xy[1],xy[2],512000)
  FROM (SELECT osmcodes_br.ij_to_xy(quadrante_ij) xy) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.cellgeom_from_ij(int)
 IS 'Geometria do quadrante expressa em projeção Albers (xy).'
;

/* falha se não incluir flag para célula retangular:
CREATE FUNCTION OSMcodes_br.cellgeom_uxy( quadrante_ij int, c_ux int, c_uy int, s int DEFAULT 512000) RETURNS geometry AS $f$
  SELECT OSMcodes_br.cellgeom_xy(xy0[1]+c_ux*s, xy0[2]+c_uy*s, s/2)
  FROM ( SELECT osmcodes_br.ij_to_xy(quadrante_ij) ) t(xy0)
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.cellgeom_uxy(int,int,int,int)
 IS 'Geometria da célula expressa em Albers, tomando como entradas o quadrante, as coordenadas Unit Box do centro da célula no quadrante e o lado (side size) da célula.'
;
*/

-- encode!
CREATE or replace FUNCTION osmcodes_br.xy_to_ggeohash(
  x int, -- X, first coordinate of IBGE's Albers Projection
  y int, -- Y, second coordinate of IBGE's Albers Projection
  precisao int, -- precisão depois do prefixo; number of digits in the geocode (of base_bitsize)
  base_bitsize int default 4  -- base4 = 2 bits, base16 = 4 bits, base32 = 5 bits
) RETURNS text AS $f$
DECLARE
  dx0 int; dy0 int; -- deltas
  i0 int; j0 int;   -- level0 coordinates
  ij int;           -- i0 and j0 as standard quadrant-indentifier.
  x0 int; y0 int;   -- Quadrant geometry corner coordinates
  ux real; uy real; -- unitary box coordinates
  ux_id bigint; uy_id bigint; -- (ux,uy) quantized as positive integers
  geohash text;     -- the final Unitary Box Geocode.
  xyMin int[];
  qbounds real[];
BEGIN
  dx0 := x - 2734000;  dy0 := y - 7320000; -- encaixa na box dos quadrantes
  i0 := floor( 15.341::real * dx0::real/7854000.0::real )::int;
  j0 := floor( 23.299::real * dy0::real/11928000.0::real )::int;
  ij := i0 + j0*10;
  IF ij NOT IN ( -- confere se entre os 54 quadrantes do território brasileiro
        4,13,14,15,23,24,25,26,27,33,34,35,36,37,39,42,43,44,45,46,47,50,51,52,53,54,55,
        56,57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,80,81,82,83,84,85
      ) THEN
    RETURN NULL;
  END IF;
  qbounds := osmcodes_br.quadrant_to_xybounds(ij);
  RETURN osmcodes_common.xy_to_ggeohash(x, y, qbounds, precisao, lpad(ij::text,2,'0'), base_bitsize);
END
$f$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.xy_to_ggeohash(int,int,int,int)
 IS 'Geocódigo de um ponto. Entradas: as coordenadas XY Albers do ponto, o número de dígitos desejados e a notação desada.'
;

-- DECODE!
CREATE or replace FUNCTION osmcodes_br.ggeohash_to_xybounds(
  geohash text,  -- completo, com quadrante no prefixo
  base_bitsize int default 4  -- base4 = 2 bits, base16 = 4 bits, base32 = 5 bits
) RETURNS text AS $f$
DECLARE
  xyMin int[];
  qbounds real[];
  bounds real[];
BEGIN
  qbounds := osmcodes_br.quadrant_to_xybounds(geohash);
  RETURN osmcodes_common.ggeohash_to_xybounds(qbounds, substr(geohash,3), base_bitsize);
END
$f$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.ggeohash_to_xybounds(text,int)
 IS 'Coordenadas MinMax Albers de um GGeohash BR.'
;

-- falta usar ggeohash_to_xybounds para produzir cellcenter e cellgeom

/* OLD LIXO
CREATE FUNCTION osmcodes_br.xy_to_ggeohash(
  x int, -- X, first coordinate of IBGE's Albers Projection
  y int, -- Y, second coordinate of IBGE's Albers Projection
  precisao int, -- number of digits in the geocode (of base_bitsize)
  base_bitsize int default 4  -- base4=2 bits, base16=4 bits.
) RETURNS text AS $f$
DECLARE
  dx0 int; dy0 int; -- deltas
  i0 int; j0 int;   -- level0 coordinates
  ij int;           -- i0 and j0 as standard quadrant-indentifier.
  x0 int; y0 int;   -- Quadrant geometry corner coordinates
  ux real; uy real; -- unitary box coordinates
  ux_id bigint; uy_id bigint; -- (ux,uy) quantized as positive integers
  geohash text;     -- the final Unitary Box Geocode.
BEGIN
  dx0 := x - 2734000;  dy0 := y - 7320000; -- encaixa na box dos quadrantes
  i0 := floor( 15.341::real * dx0::real/7854000.0::real )::int;
  j0 := floor( 23.299::real * dy0::real/11928000.0::real )::int;
  ij := i0 + j0*10;
  IF ij NOT IN ( -- confere se entre os 54 quadrantes do território brasileiro
        4,13,14,15,23,24,25,26,27,33,34,35,36,37,39,42,43,44,45,46,47,50,51,52,53,54,55,
        56,57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,80,81,82,83,84,85
      ) THEN
    RETURN NULL;
  END IF;
  -- centro da célula:
  x0 := 2734000 + i0*512000; -- coordenada x0_min do quadrante (j0,i0)
  y0 := 7320000 + j0*512000; -- coordenada y0_min do quadrante (j0,i0)
  -- coordenadas dentro do quadrante, como box unitária, valores de ~0.00001 a ~0.999999:
  ux := (x-x0)::real / 512000.0::real;   -- unit X
  uy := (y-y0)::real / 512000.0::real;  -- unit Y
  geohash := osmcode_common.uxy_to_ggeohash(ux, uy, precisao, base_bitsize);
  RETURN lpad(ij::text,2,'0') || geohash;
END
$f$ LANGUAGE plpgsql IMMUTABLE;
*/




/* bug
CREATE FUNCTION osmcodes_br.ggeohash_to_xybounds(
  geohash text, -- the BR geocode.
  base_bitsize int default 5 -- supposed input type, base4=2 bits, base16=4 bits, base32=5.
) RETURNS int[] AS $f$
  -- como fazer os bounds se não é quadrado? falta entender se a proporção vai funcionar no unitário!
  -- no Geohash de nível meio precisa tratar como retângulo.
  SELECT array[
    -- debug ij[1], ij[2], side_size,
    ij[1] + side_size*uxy[1],  ij[2] + side_size*uxy[2],  -- (x,y) do canto inferior esquerdo (minXY)
    ij[1] + side_size*uxy[3],  ij[2] + side_size*uxy[4]   -- (x,y) do canto superior direito (maxXY)
  ]
  FROM (
    SELECT osmcodes_br.ij_to_xy(substr(geohash,1,2)::int) as ij,
           CASE
             WHEN length(geohash)>2 THEN osmcodes_common.ggeohash_to_uxybounds(substr(geohash,3),base_bitsize)
             ELSE array[0.0, 0.0, 0.0, 0.0]
           END as uxy
  ) t1, (SELECT 512000.0/(2^(length(geohash)*base_bitsize/2.0))::real AS side_size) t2
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.ggeohash_to_xybounds(text,int)
 IS 'Extremidades da diagonal da célula expressas em Albers, tomando como entradas o geohash completo e a notação esperada.'
;


CREATE FUNCTION osmcodes_br.ggeohash_to_xy(
  geohash text, -- the BR geocode.
  base_bitsize int default 5 -- supposed input type, base4=2 bits, base16=4 bits, base32=5.
) RETURNS int[] AS $f$
  SELECT array[ (xy[1]+xy[3])/2,  (xy[2]+xy[4])/2 ]
  FROM ( SELECT osmcodes_br.ggeohash_to_xybounds($1,$2) ) t(xy)
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION OSMcodes_br.ggeohash_to_xybounds(text,int)
 IS 'Centro da célula expressas em Albers, tomando como entradas o geohash completo e a notação esperada.'
;

*/

-----
CREATE FUNCTION osmcodes_br.point_to_ggeohash(
  p geometry, -- point geometry, any SRID
  precisao int, -- number of digits in the geocode (of base_bitsize)
  base_bitsize int default 4  -- base4=2 bits, base16=4 bits.
) RETURNS text AS $f$
  SELECT osmcodes_br.xy_to_ggeohash(
    round( ST_X(geom) )::int,  -- round or trunc to meters
    round( ST_Y(geom) )::int,
    precisao,
    base_bitsize
  )
  FROM (SELECT ST_Transform(p,952019)) t(geom)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION osmcodes_br.latlon_to_ggeohash(
  x real, y real,
  precisao int, -- number of digits in the geocode (of base_bitsize)
  base_bitsize int default 4
) RETURNS text AS $f$
  SELECT osmcodes_br.point_to_ggeohash( ST_SetSRID(ST_MakePoint(x,y),4326), precisao, base_bitsize )
$f$ LANGUAGE SQL IMMUTABLE;


------------------------------
/*  testing
CREATE or replace FUNCTION osmcodes.br_xy_to_ggeohash_v2( x int, y int) RETURNS varbit AS $f$
DECLARE
  dx0 int; dy0 int; -- deltas
  i0 int; j0 int;
  x0 int; y0 int;
  ux real; uy real;
  ux_id bigint; uy_id bigint; -- ux e uy quantizados como inteiros positivos
BEGIN
  dx0 := x - 2734000;  dy0 := y - 7320000;
  i0 := floor( 15.341::real * dx0::real/7854000.0::real )::int;
  j0 := floor( 23.299::real * dy0::real/11928000.0::real )::int;
  -- confere se ebtre is 54 quadrantes do território brasileiro:
  IF (i0+j0*10) NOT IN (4,13,14,15,23,24,25,26,27,33,34,35,36,37,39,42,43,44,45,46,47,50,51,52,53,54,55,56,57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,80,81,82,83,84,85) THEN
    -- não ganha velocidade nem economiza memória ao remover apenas 12 com (i0 between 4 and 6 AND j0 between 3 and 6)
    RETURN NULL;
  END IF;
  -- centro da célula:
  x0 := 2734000 + i0*512000; -- coordenada x0_min do quadrante (j0,i0)
  y0 := 7320000 + j0*512000; -- coordenada y0_min do quadrante (j0,i0)
  -- coordenadas dentro do quadrante, como box unitária, valores de ~0.00001 a ~0.999999:
  ux:= ( (x-x0)::real / 512000.0::real );   -- unit X
  uy := ( (y-y0)::real / 512000.0::real );  -- unit Y
  ux_id := floor(ux*(2.0^32)::real);
  uy_id := floor(uy*(2.0^32)::real);
  -- inteiro de 32 bits positivo fica com 31 bits:
  RETURN interlace_32bits_pair(ux_id,uy_id);
END
$f$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION osmcodes.br_xy_to_ggeohash_v2
 IS 'Encodes varbit (string of bits) into Base4h, Base8h or Base16h. See http://osm.codes/_foundations/art1.pdf'
;
-- conclusão: usando só centroides da grade de 1km temos 20  bits, por exemplo '00000000001100011111' que são
*/
