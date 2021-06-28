--
-- OSM CODES, common implementations, for all jurisdictions.
--
-- Foundations: Natural Codes and Generalized Geohashes.
--   Natural Codes as http://osm.codes/_foundations/art1.pdf
--   Generalized Geohashes as https://ppkrauss.github.io/Sfc4q/
--

DROP SCHEMA IF EXISTS osmcodes_common CASCADE; -- to restart all lib and dependencies.
CREATE SCHEMA osmcodes_common;

--CREATE TYPE osmcodes_common.cell_xy     (x int, y int);        -- Cell center, for projections like Albers
--CREATE TYPE osmcodes_common.cell_latlon (lat real, lon real);  -- Cell center, for WGS84 latitude/longitude
--CREATE TYPE osmcodes_common.cell_uxy    (ux real, uy real);    -- Cell center, for Unit Box coordinates, range [0,1].

/**
 * Converts bit string to text, using base2h, base4h, base8h or base16h.
 * Uses letters "G" and "H" to sym44bolize non strandard bit strings (0 for44 bases44)
 * Uses extended alphabet (with no letter I,O,U W or X) for base8h and base16h.
 * @see http://osm.codes/_foundations/art1.pdf
 * @version 1.0.1.
 */
CREATE FUNCTION osmcodes_common.vbit_to_baseh(
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
COMMENT ON FUNCTION osmcodes_common.vbit_to_baseh(varbit,int,int)
 IS 'Encodes varbit (string of bits) into Base4h, Base8h or Base16h. See http://osm.codes/_foundations/art1.pdf'
;

-----------
--- ENCODE/DECODE: can be by "unitary box" (ux,uy), but not using it

CREATE or replace FUNCTION osmcodes_common.xy_to_ggeohash(
  x real, -- X. First coordinate
  y real, -- Y. Second coordinate.
  qbounds real[], -- minXY, maxXY. Prefix or Quadrant bounds
  precisao int, -- number of digits in the geocode (of base_bitsize)
  prefix text DEFAULT '', -- Geocode of the "parent cell", non-unitary.
  base_bitsize int default 4  -- base4=2 bits, base16=4 bits. Base32=5 bits.
) RETURNS text AS $f$
DECLARE
  alphabet text;
  idx int;
  bitct int;
  evenBit boolean;
  geohash text;
  xOrigMin real; xOrigMax real;
  yOrigMin real; yOrigMax real;
  xMid real; yMid real;
BEGIN
  alphabet := '0123456789abcdef'; -- hexadecimal é análogo de notação científica para geocódigos.
  IF base_bitsize=5 THEN  -- alphabet do NOVO CEP
    alphabet := '0123456789BCDFGHJKLMNPQRSTUVWXYZ';  -- no-Volgal, NVU Alphabet.
  END IF;
  idx := 0; -- index into base32 map
  bitct := 0; -- each char holds 5 bits
  evenBit := true;
  geohash := '';
  xOrigMin := qbounds[1]; yOrigMin := qbounds[2]; -- minXY
  xOrigMax := qbounds[3]; yOrigMax := qbounds[4]; -- maxXY
  WHILE length(geohash) < precisao LOOP
    IF evenBit THEN
      -- bisect E-W y
      yMid := (yOrigMin + yOrigMax) / 2.0;
      IF y >= yMid THEN
          idx := idx*2 + 1;
          yOrigMin := yMid;
      ELSE
          idx := idx*2;
          yOrigMax := yMid;
      END IF;
    ELSE -- not evenBit:
      -- bisect N-S x
      xMid := (xOrigMin + xOrigMax) / 2.0;
      IF x >= xMid THEN
        idx = idx*2 + 1;
        xOrigMin = xMid;
      ELSE
        idx := idx*2;
        xOrigMax := xMid;
      END IF;
    END IF;
    evenBit := NOT(evenBit);
    bitct := bitct + 1;
    IF bitct = base_bitsize THEN
        geohash := geohash || substr(alphabet, idx+1, 1);
        bitct := 0;
        idx := 0;
    END IF;
  END LOOP;
  -- Calculate the ERROR ON USE geocode as central position:  SQRT( (x-(xOrigMin+xOrigMax)/2)^2 + (y-(yOrigMin+yOrigMax)/2)^2 )
  RETURN prefix || geohash;
END
$f$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION osmcodes_common.xy_to_ggeohash(real,real,real[],int,text,int)
 IS 'Encodes XY coodinates into a Generalized Geohash with specified precision, prefix and baseByBits (2, 4 or 5). Non-optimized algorithm, v1.'
;

/*  BUG: avoid because some cells are not squares!
CREATE or replace FUNCTION osmcodes_common.uxy_to_ggeohash(
  ux real, -- Unitary X. First coordinate in the "unitary box".
  uy real, -- Unitary Y. Second coordinate in the "unitary box".
  precisao int, -- number of digits in the geocode (of base_bitsize)
  prefix text DEFAULT '', -- Geocode of the "parent cell", non-unitary.
  base_bitsize int default 4  -- base4=2 bits, base16=4 bits. Base32=5 bits.
) RETURNS text AS $f$
  SELECT osmcodes_common.xy_to_ggeohash($1,$2,array[0.0,1.0, 0.0,1.0],$3,$4,$5)
$f$ LANGUAGE plpgsql IMMUTABLE;
*/

-- DECODE
CREATE or replace FUNCTION osmcodes_common.ggeohash_to_xybounds(
  qbounds real[], -- minXY, maxXY. Prefix or Quadrant (prefix) bounds
  internal_geohash text, -- a geocode, without prefix
  base_bitsize int default 5  -- supposed input type, base4=2 bits, base16=4 bits, base32=5 bits.
) RETURNS real[] AS $f$
DECLARE
  alphabet text     := '0123456789abcdef'; -- base4, base8 ou hexadecimal
  evenBit  boolean  := true;
  idx int;
  chr char;
  bitN int;
  i int; n int;
  xMin real; xMax real;
  yMin real; yMax real;
  xMid real; yMid real;
BEGIN
  IF base_bitsize=5 THEN  -- alfabeto do NOVO CEP
    alphabet := '0123456789BCDFGHJKLMNPQRSTUVWXYZ';  -- NVU Alphabet - "No-Volgal except U".
    internal_geohash := upper(internal_geohash);
  ELSE
    internal_geohash := lower(internal_geohash);
  END IF;
  IF length(internal_geohash)=0 THEN
    RAISE NOTICE 'Invalid (empty) geohash';
    RETURN NULL;
  END IF;
  xMin := qbounds[1]; yMin := qbounds[2]; -- minXY
  xMax := qbounds[3]; yMax := qbounds[4]; -- maxXY
  -- falta testar com varbit direto.
  FOR i IN 1..length(internal_geohash) LOOP -- scan dos dígitos
    chr = substr(internal_geohash,i,1);
    idx = position(chr in alphabet);
    IF idx=0 THEN
      RAISE NOTICE 'Invalid geohash: %', internal_geohash;
      RETURN NULL;
    END IF;
    FOR n IN REVERSE (base_bitsize-1)..0 LOOP -- scan dos bits do dígito conforme sua base
        bitN := (idx >> n) & 1;
        IF evenBit THEN -- Y:
            yMid = (yMin+yMax) / 2.0;
            IF bitN = 1 THEN  yMin := yMid; ELSE yMax := yMid; END IF;
        ELSE  -- X:
            xMid = (xMin+xMax) / 2.0;
            IF bitN = 1 THEN  xMin := xMid; ELSE xMax := xMid; END IF;
        END IF;
        evenBit = NOT(evenBit);
        -- RAISE NOTICE '%-Bit=% IN i=% | chr=% | idx=%', n, bitN, i, chr, idx;
    END LOOP; -- FOR n
  END LOOP; -- FOR i
  RETURN array[xMin,yMin, xMax,yMax];
END
$f$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION osmcodes_common.ggeohash_to_xybounds(real[],text,int)
 IS 'Decodes Generalized Geohash into XY coodinates, supposing specified quadrant and baseByBits (2, 4 or 5). Non-optimized algorithm, v1.'
;

-----
/* not common, use jurisdiction specific
CREATE or replace FUNCTION osmcodes_common.ggeohash_to_uxy(
  code text, -- A Generalized Geohash code.
  prefix int default 0, -- lenth of a prefix to be ignorated.
  base_bitsize int default 4  -- base4=2 bits, base16=4 bits. Base32=5 bits.
) RETURNS real[] AS $f$
BEGIN
  RETURN NULL;
END
$f$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION osmcodes_common.ggeohash_to_uxy(text,int,int)
 IS 'Decodes a Generalized Geohash into Unitary-XY coodinates. Non-optimized algorithm, v1.'
;
*/

/*
---------------------
-- NEW VERSION ALGORITHMS: needs evolutions v2 and v3 to better performance and check datatype use.

CREATE or replace FUNCTION osmcodes_common.uxy_to_ggeohash_varbit(
  ux real,       -- Unitary X. First coordinate in the "unitary box".
  uy real,       -- Unitary Y. Second coordinate in the "unitary box".
  precisao int,  -- number of bits to stop
  prefix varbit DEFAULT b''  -- Geocode of the "parent cell", non-unitary.
) RETURNS varbit AS $f$
DECLARE
  idx int; -- using base4: 0, 1, 2, or 3.
  bitct int;
  evenBit boolean;
  geohash varbit;
  xOrigMin real; xOrigMax real;
  yOrigMin real; yOrigMax real;
  xMid real; yMid real;
BEGIN
  idx := 0; -- index into base32 map
  bitct := 0; -- each char holds 5 bits
  evenBit := true;
  geohash := B'';  -- bit string
  xOrigMin := 0; xOrigMax := 1;
  yOrigMin := 0; yOrigMax := 1;
  WHILE length(geohash) < precisao LOOP
    IF evenBit THEN
      yMid := (yOrigMin + yOrigMax) / 2.0;
      IF uy >= yMid THEN
          idx := idx*2 + 1;
          yOrigMin := yMid;
      ELSE
          idx := idx*2;
          yOrigMax := yMid;
      END IF;
    ELSE -- not evenBit:
      xMid := (xOrigMin + xOrigMax) / 2.0;
      IF ux >= xMid THEN
        idx = idx*2 + 1;
        xOrigMin = xMid;
      ELSE
        idx := idx*2;
        xOrigMax := xMid;
      END IF;
    END IF;
    evenBit := NOT(evenBit);
    bitct := bitct + 1;
    IF bitct = 2 THEN
      geohash := geohash || idx::bit(2);
      bitct := 0;
      idx := 0;
    END IF;
  END LOOP;
  RETURN prefix || geohash;
END
$f$ LANGUAGE plpgsql IMMUTABLE;
*/

-- -- -- --
-- NAIVE ALGORITHMS, ONLY FOR TEST AND PROOF OF CONCEPT
-- See good implementations at https://mmcloughlin.com/posts/geohash-assembly
-- See also https://github.com/petere/pguint
-- -- -- --

CREATE or replace FUNCTION osmcodes_common.str_interlace(p_x text, p_y text) RETURNS text AS $f$
   SELECT string_agg(x||y,'')
   FROM
   ( SELECT * FROM regexp_split_to_table(p_x::text,'') WITH ORDINALITY ) tx(x,ix)
   INNER JOIN
   ( SELECT * FROM regexp_split_to_table(p_y::text,'') WITH ORDINALITY ) ty(y,iy)
   ON tx.ix=ty.iy
$f$ language SQL IMMUTABLE;
COMMENT ON FUNCTION osmcodes_common.str_interlace(text,text)
 IS 'Interlaces characters of two equal-size strings.'
;

-- Dedatic version, only for human-decimals:
CREATE or replace FUNCTION osmcodes_common.str_interlace_decimal(p_x int, p_y int, p_digits int DEFAULT 7) RETURNS text AS $wrap$
     SELECT osmcodes_common.str_interlace( LPAD(p_x::text,p_digits,'0'), LPAD(p_y::text,p_digits,'0') )
$wrap$ language SQL IMMUTABLE;
COMMENT ON FUNCTION osmcodes_common.str_interlace_decimal(int,int,int)
 IS 'Wrap for osmcodes_common.str_interlace(text,text), default lpad 7.'
;

CREATE or replace FUNCTION osmcodes_common.interlace_24bits_pair(  p_x int, p_y int  ) RETURNS varbit AS $f$
     SELECT osmcodes_common.str_interlace( p_x::bit(24)::text, p_y::bit(24)::text )::bit(48)::varbit
$f$ language SQL IMMUTABLE;
COMMENT ON FUNCTION osmcodes_common.interlace_24bits_pair(int,int)
 IS 'Bit interlace and varbit copnversion, default 24 bit pair resulting in 48 interlaced bits.'
;
CREATE or replace FUNCTION osmcodes_common.interlace_24bits_pair(  p_x int, p_y int  ) RETURNS varbit AS $f$
     SELECT osmcodes_common.str_interlace( p_x::bit(31)::text, p_y::bit(31)::text )::bit(62)::varbit
$f$ language SQL IMMUTABLE;
COMMENT ON FUNCTION osmcodes_common.interlace_24bits_pair(int,int)
 IS 'Bit interlace and varbit copnversion, default 31 bits pair resulting in 62 interlaced bits.'
;
CREATE or replace FUNCTION osmcodes_common.interlace_32bits_pair(  p_x bigint, p_y bigint  ) RETURNS varbit AS $f$
     SELECT osmcodes_common.str_interlace( p_x::bit(32)::text, p_y::bit(32)::text )::bit(64)::varbit
$f$ language SQL IMMUTABLE;
COMMENT ON FUNCTION osmcodes_common.interlace_32bits_pair(bigint,bigint)
 IS 'Bit interlace and varbit copnversion, default 32 bits pair resulting in 64 interlaced bits.'
;
