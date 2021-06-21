/**
 * System's Public library (commom for WS and others)
 * PREFIXES: geojson_
 * Extra: PostGIS's Brazilian SRID inserts.
 * See also https://github.com/ppKrauss/SizedBigInt/blob/master/src_sql/step2-sizedNaturals.sql
 *          https://github.com/AddressForAll/WS/blob/master/src/sys_pubLib.sql
 */

CREATE extension IF NOT EXISTS postgis;

DROP SCHEMA IF EXISTS natcode CASCADE;
CREATE SCHEMA natcode;  -- Sized Natural, http://osm.codes/_foundations/art1.pdf

-------------------------------
-- system -generic

CREATE or replace FUNCTION geojson_readfile_headers(
    f text,   -- absolute path and filename
    missing_ok boolean DEFAULT false -- an error is raised, else (if true), the function returns NULL when file not found.
) RETURNS JSONb AS $f$
  SELECT j || jsonb_build_object( 'file',f,  'content_header', pg_read_file(f)::JSONB - 'features' )
  FROM to_jsonb( pg_stat_file(f,missing_ok) ) t(j)
  WHERE j IS NOT NULL
$f$ LANGUAGE SQL;

CREATE or replace FUNCTION  jsonb_objslice(
    key text, j jsonb, rename text default null
) RETURNS jsonb AS $f$
    SELECT COALESCE( jsonb_build_object( COALESCE(rename,key) , j->key ), '{}'::jsonb )
$f$ LANGUAGE SQL IMMUTABLE;  -- complement is f(key text[], j jsonb, rename text[])
COMMENT ON FUNCTION jsonb_objslice(text,jsonb,text)
  IS 'Get the key as encapsulated object, with same or changing name.'
;

-- drop  FUNCTION geojson_readfile_features;
CREATE or replace FUNCTION geojson_readfile_features(f text) RETURNS TABLE (
  fname text, feature_id int, geojson_type text,
  feature_type text, properties jsonb, geom geometry
) AS $f$
   SELECT fname, (ROW_NUMBER() OVER())::int, -- feature_id,
          geojson_type, feature->>'type',    -- feature_type,
          jsonb_objslice('name',feature) || feature->'properties', -- properties and name.
          -- see CRS problems at https://gis.stackexchange.com/questions/60928/
          ST_GeomFromGeoJSON(  crs || (feature->'geometry')  ) AS geom
   FROM (
      SELECT j->>'file' AS fname,
             jsonb_objslice('crs',j) AS crs,
             j->>'type' AS geojson_type,
             jsonb_array_elements(j->'features') AS feature
      FROM ( SELECT pg_read_file(f)::JSONb AS j ) jfile
   ) t2
$f$ LANGUAGE SQL;
COMMENT ON FUNCTION geojson_readfile_features(text)
  IS 'Reads a small GeoJSON file and transforms it into a table with a geometry column.'
;

CREATE or replace FUNCTION geojson_readfile_features_jgeom(file text, file_id int default null) RETURNS TABLE (
  file_id int, feature_id int, feature_type text, properties jsonb, jgeom jsonb
) AS $f$
   SELECT file_id, (ROW_NUMBER() OVER())::int AS subfeature_id,
          subfeature->>'type' AS subfeature_type,
          subfeature->'properties' AS properties,
          crs || subfeature->'geometry' AS jgeom
   FROM (
      SELECT j->>'type' AS geojson_type,
             jsonb_objslice('crs',j) AS crs,
             jsonb_array_elements(j->'features') AS subfeature
      FROM ( SELECT pg_read_file(file)::JSONb AS j ) jfile
   ) t2
$f$ LANGUAGE SQL;
COMMENT ON FUNCTION geojson_readfile_features_jgeom(text,int)
  IS 'Reads a big GeoJSON file and transforms it into a table with a json-geometry column.'
;

--------

CREATE or replace FUNCTION ST_AsGeoJSONb( -- ST_AsGeoJSON_complete
  -- st_asgeojsonb(geometry, integer, integer, bigint, jsonb
  p_geom geometry,
  p_decimals int default 6,
  p_options int default 1,  -- 1=better (implicit WGS84) tham 5 (explicit)
  p_id text default null,
  p_properties jsonb default null,
  p_name text default null,
  p_title text default null,
  p_id_as_int boolean default false
) RETURNS JSONb AS $f$
-- Do ST_AsGeoJSON() adding id, crs, properties, name and title
  SELECT ST_AsGeoJSON(p_geom,p_decimals,p_options)::jsonb
       || CASE
          WHEN p_properties IS NULL OR jsonb_typeof(p_properties)!='object' THEN '{}'::jsonb
          ELSE jsonb_build_object('properties',p_properties)
          END
       || CASE
          WHEN p_id IS NULL THEN '{}'::jsonb
          WHEN p_id_as_int THEN jsonb_build_object('id',p_id::bigint)
          ELSE jsonb_build_object('id',p_id)
          END
       || CASE WHEN p_name IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('name',p_name) END
       || CASE WHEN p_title IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('title',p_title) END
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION ST_AsGeoJSONb IS $$
  Enhances ST_AsGeoJSON() PostGIS function.
  Use ST_AsGeoJSONb( geom, 6, 1, osm_id::text, stable.element_properties(osm_id) - 'name:' ).
$$;


-------
-- INDEXADORES ESPACIAIS.


CREATE or replace FUNCTION hex_to_varbit(h text) RETURNS varbit as $f$
  SELECT ('X' || $1)::varbit
$f$ LANGUAGE SQL IMMUTABLE;

------------------------
-- Workarounds for postgresqt cast ...

CREATE or replace FUNCTION varbit_to_int( b varbit, blen int DEFAULT NULL) RETURNS int AS $f$
  SELECT (  (b'0'::bit(32) || b) << COALESCE(blen,bit_length(b))   )::bit(32)::int
$f$ LANGUAGE SQL IMMUTABLE;
-- select b'010101'::bit(32) left_copy, varbit_to_int(b'010101')::bit(32) right_copy;

CREATE OR REPLACE FUNCTION varbit_to_bigint( b varbit )
RETURNS bigint AS $f$
  -- see https://stackoverflow.com/a/56119825/287948
  SELECT ( (b'0'::bit(64) || b) << bit_length(b) )::bit(64)::bigint
$f$  LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION bigint_usedbits( b bigint ) RETURNS int AS $f$
-- max bit_length(b) = 61!
-- LOSS of 1 bit, cant use negative neither b>4611686018427387904
  -- time_performance ~0.25 * time_performance of floor(log(2.0,x)).
  SELECT 63 - x
  FROM generate_series(1,62) t1(x)  -- stop ith 61?
  -- constant = b'01'::bit(64)::bigint
  WHERE ( 4611686018427387904 & (b << x) ) = 4611686018427387904
  -- not use! constant = b'1'::bit(64)::bigint
  -- WHERE ( -9223372036854775808 & (b << x) ) = -9223372036854775808
  LIMIT 1
$f$ LANGUAGE SQL IMMUTABLE;


------------------------
-- Outros algoritmos para PostgreSQL
--  https://github.com/ppKrauss/SizedBigInt
--  https://ppkrauss.github.io/Sfc4q/


-- datatypes prefixes: jsonb, bigint, vbit, pair, numpair

CREATE TYPE natcode.pair AS ( -- used only for final convertions
  n smallint, -- NOT NULL DEFAULT 0,--  CHECK(n>=0),  -- num. of bits, <32767
  v bigint -- 64 bit value
);

/**
 * Converts bit string to text, using base2h, base4h, base8h or base16h.
 * Uses letters "G" and "H" to sym44bolize non strandard bit strings (0 for44 bases44)
 * Uses extended alphabet (with no letter I,O,U W or X) for base8h and base16h.
 * @see http://osm.codes/_foundations/art1.pdf
 * @version 1.0.1.
 */
CREATE FUNCTION natcode.vbit_to_baseh(
  p_val varbit,  -- input
  p_base int DEFAULT 4, -- selecting base2h, base4h, base8h, or base16h.
  p_size int DEFAULT 0
) RETURNS text AS $f$
DECLARE
    vlen int;
    pos0 int;
    ret text := '';
    blk varbit;
    blk_n int;
    bits_per_digit int;
    tr int[] := '{ {1,2,0,0}, {1,3,4,0}, {1,3,5,6} }'::int[]; -- --4h(bits,pos), 8h(bits,pos)
    tr_selected JSONb;
    trtypes JSONb := '{"2":[1,1], "4":[1,2], "8":[2,3], "16":[3,4]}'::JSONb; -- TrPos,bits
    trpos int;
    baseh "char"[] := array[
      '[0:15]={G,H,x,x,x,x,x,x,x,x,x,x,x,x,x,x}'::"char"[], --1. 4h,8h,16h 1bit
      '[0:15]={0,1,2,3,x,x,x,x,x,x,x,x,x,x,x,x}'::"char"[], --2. 4h 2bit
      '[0:15]={J,K,L,M,x,x,x,x,x,x,x,x,x,x,x,x}'::"char"[], --3. 8h,16h 2bit
      '[0:15]={0,1,2,3,4,5,6,7,x,x,x,x,x,x,x,x}'::"char"[], --4. 8h 3bit
      '[0:15]={N,P,Q,R,S,T,V,Z,x,x,x,x,x,x,x,x}'::"char"[], --5. 16h 3bit
      '[0:15]={0,1,2,3,4,5,6,7,8,9,a,b,c,d,e,f}'::"char"[]  --6. 16h 4bit
    ]; -- jumpping I,O and U,W,X letters!
       -- the standard alphabet is https://tools.ietf.org/html/rfc4648#section-6
BEGIN
  vlen := bit_length(p_val);
  tr_selected := trtypes->(p_base::text);
  IF p_val IS NULL OR tr_selected IS NULL OR vlen=0 THEN
    RETURN NULL; -- or  p_retnull;
  END IF;
  IF p_base=2 THEN
    RETURN $1::text; --- direct bit string as string
  END IF;
  bits_per_digit := (tr_selected->>1)::int;
  blk_n := vlen/bits_per_digit;  -- poderia controlar p_size por aqui
  pos0  := (tr_selected->>0)::int;
  trpos := tr[pos0][bits_per_digit];
  FOR counter IN 1..blk_n LOOP
      blk := substring(p_val FROM 1 FOR bits_per_digit);
      ret := ret || baseh[trpos][ varbit_to_int(blk,bits_per_digit) ];
      p_val := substring(p_val FROM bits_per_digit+1); -- same as p_val<<(bits_per_digit*blk_n)
  END LOOP;
  vlen := bit_length(p_val);
  IF p_val!=b'' THEN -- vlen % bits_per_digit>0
    trpos := tr[pos0][vlen];
    ret := ret || baseh[trpos][ varbit_to_int(p_val,vlen) ];
  END IF;
  IF p_size>0 THEN
    ret := substr(ret,1,p_size);
  END IF;
  RETURN ret;
END
$f$ LANGUAGE plpgsql IMMUTABLE;

-------

CREATE or replace FUNCTION strchar_interlace(p_x text, p_y text) RETURNS text AS $f$
   SELECT string_agg(x||y,'')
   FROM
   ( SELECT * FROM regexp_split_to_table(p_x::text,'') WITH ORDINALITY ) tx(x,ix)
   INNER JOIN
   ( SELECT * FROM regexp_split_to_table(p_y::text,'') WITH ORDINALITY ) ty(y,iy)
   ON tx.ix=ty.iy
$f$ language SQL IMMUTABLE;
COMMENT ON FUNCTION strchar_interlace(text,text)
 IS 'Interlaces characters of two equal-size strings.'
;

CREATE or replace FUNCTION strchar_interlace_decimal(p_x int, p_y int, p_digits int DEFAULT 7) RETURNS text AS $wrap$
     SELECT strchar_interlace( LPAD(p_x::text,p_digits,'0'), LPAD(p_y::text,p_digits,'0') )
$wrap$ language SQL IMMUTABLE;
COMMENT ON FUNCTION strchar_interlace(int,int,int)
 IS 'Wrap for strchar_interlace(text,text), default lpad 7.'
;
CREATE or replace FUNCTION interlace_24bits_pair(  p_x int, p_y int  ) RETURNS varbit AS $f$
     SELECT strchar_interlace( p_x::bit(24)::text, p_y::bit(24)::text )::bit(48)::varbit
$f$ language SQL IMMUTABLE;
COMMENT ON FUNCTION interlace_24bits_pair(int,int)
 IS 'Bit interlace and varbit copnversion, default 24 bit pair resulting in 48 interlaced bits.'
;
CREATE or replace FUNCTION interlace_31bits_pair(  p_x int, p_y int  ) RETURNS varbit AS $f$
     SELECT strchar_interlace( p_x::bit(31)::text, p_y::bit(31)::text )::bit(62)::varbit
$f$ language SQL IMMUTABLE;
COMMENT ON FUNCTION interlace_31bits_pair(int,int)
 IS 'Bit interlace and varbit copnversion, default 31 bits pair resulting in 62 interlaced bits.'
;

CREATE or replace FUNCTION ggeohash_br_b16h_62bits(  p_x real, p_y real, p_size int DEFAULT 7  ) RETURNS text AS $f$
     SELECT natcode.vbit_to_baseh( interlace_31bits_pair(x,y), 16, p_size)
     FROM (
       SELECT floor( (2.0^31)::real * (p_x - 2800000.0::real)/7650000.0::real )::int as x,
              floor( (2.0^31)::real * (p_y - 7400000.0::real)/12000000.0::real )::int as y
     ) quantized
$f$ language SQL IMMUTABLE;
COMMENT ON FUNCTION ggeohash_br_b16h_62bits(real,real,int)
 IS 'Generalized Geohash base 16h, from X/Y of IBGE projection.'
;

CREATE or replace FUNCTION ggeohash_br_vbits(  x real, y real, size int DEFAULT 62  ) RETURNS varbit AS $f$
     SELECT interlace_31bits_pair(x,y) -- cut for size<62
     FROM (
       SELECT floor( (2.0^31)::real * (x - 2800000.0::real)/7650000.0::real )::int as x,
              floor( (2.0^31)::real * (y - 7400000.0::real)/12000000.0::real )::int as y
     ) quantized
$f$ language SQL IMMUTABLE;
COMMENT ON FUNCTION ggeohash_br_vbits(real,real,int)
 IS 'Generalized Geohash varbit, from X/Y of IBGE projection.'
;
-- select ggeohash_br_vbits(gx,gy) from grade_ibge_hierarq TABLESAMPLE SYSTEM(1);
-- 00100011111100101101011101100111000001011110000011000100000000
-- remover os ultimos 6 00100011111100101101011101100111000001011110000011000100000000
-- e testar .. usando  substring(x from 1 for x)
-- select count(*) n, count(DISTINCT ggeohash_br_vbits(gx,gy)>>8) n_cut from grade_ibge_hierarq;
-- ... Vai determinar qual o mínimo de bits para células de 1km.
--  8860553 | 8860553
select count(*) n, count(DISTINCT substring(ggeohash_br_vbits(gx,gy) FROM 1 for 54)) n_cut from grade_ibge_hierarq;

CREATE TABLE grade_teste2 AS
  SELECT ggeohash_br_vbits(gx,gy) as key0 FROM grade_ibge_hierarq;


-- -- -- -- --
-- PostGIS complements, !future PubLib-postgis

-- Project digital-preservation-BR:
INSERT into spatial_ref_sys (srid, auth_name, auth_srid, proj4text, srtext)
 -- POSTGIS: SRID on demand, see Eclusa and Digital Preservation project demands.
 -- see https://wiki.openstreetmap.org/wiki/Brazil/Oficial/Carga#Adaptando_SRID
 -- after max(srid)=900913
VALUES
  ( 952013, 'BR-RS-POA', null,
   '+proj=tmerc +lat_0=0 +lon_0=-51 +k=0.999995 +x_0=300000 +y_0=5000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
   null
  ),
  ( 952019, 'BR:IBGE', 52019,
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
