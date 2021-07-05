--
-- TESTS to check by QGIS,
--


SELECT OSMcodes_br.xy_to_ggeohash(5300500,9396500,8);

DROP TABLE IF EXISTS osmcodes_br.grid_test1_quadrantes;
CREATE TABLE osmcodes_br.grid_test1_quadrantes AS
  SELECT lpad((j*10+i)::text,2,'0') AS gid,
        OSMcodes_br.cellgeom_from_ij(j*10+i) as geom
  FROM generate_series(0,8) as j, generate_series(0,9) as i
;


SELECT gid, geocode
FROM (
  SELECT gid, x, y, OSMcodes_br.xy_to_ggeohash(x,y,4) AS geocode
  FROM (
    SELECT  gid, st_x(geom)::int x, st_y(geom)::int y
    FROM (SELECT gid, st_centroid(geom) geom FROM osmcodes_br.grid_test1_quadrantes) t1
  ) t2
) t3
WHERE geocode is not null;

DROP TABLE osmcodes_br.grid_test25_quadrantes;
CREATE TABLE osmcodes_br.grid_test25_quadrantes AS
  SELECT gid, pop, substr(OSMcodes_br.xy_to_ggeohash(gx,gy,4),3) as geocode, geom
  FROM grade_ibge_1kmcenters
  WHERE newprefix = 25;

===


Adaptar função xy_to_ggeohash para varbit!

Criar uma função de varredura de box unitária! Bastam canto e size, ou diagonal. Por hora só boxes quadradas ... depois retangulares·

SELECT x,y,OSMcodes_br.xy_to_ggeohash(x,y,4) AS geocode
FROM (
  SELECT 2734000 + ui*1000 AS x, 7320000 + uj*1000 AS y
  FROM generate_series(0,512/4) as ui, generate_series(0,512/4) as uj
) t;

(x0_min,y0_min)=(2734000,)



DROP TABLE osmcodes_br.grid_q25_2km;
CREATE TABLE osmcodes_br.grid_q25_2km AS
  SELECT geocode, SUM(pop) as pop, ST_UNION(geom) as geom
  FROM (
    SELECT gid, substr(OSMcodes_br.xy_to_ggeohash(gx,gy,4),3) as geocode,
           pop, geom
    FROM grade_ibge_1kmcells
    WHERE newprefix = 25
  ) t
;


====



gid   | ibge_prefix |  pop  | pop_fem_perc | is_urban |   gx    |    gy    |                        geom                        | newprefix
---------+-------------+-------+--------------+----------+---------+----------+----------------------------------------------------+-----------
2341969 |          45 |     0 |            0 | f        | 5411500 |  9609500 | 0101000020E6100000F6E6360A7C0E49C071773D4FBAE72EC0 |        45
2341970 |          45 |     0 |            0 | f        | 5411500 |  9610500 | 0101000020E6100000D431F856800E49C06F616BDF29E32EC0 |        45
2341971 |          45 |     0 |            0 | f        | 5411500 |  9611500 | 0101000020E61000002107A6A3840E49C012AC0B7299DE2EC0 |        45
2341972 |          45 |   186 |           49 | t        | 5411500 |  9612500 | 0101000020E6100000E35F41F0880E49C0CC0FE70709DA2EC0 |        45
2341973 |          45 |     0 |            0 | f        | 5411500 |  9613500 | 0101000020E610000047B0C83C8D0E49C0A9A1909E78D52EC0 |        45
2341974 |          45 |     0 |            0 | f        | 5411500 |  9614500 | 0101000020E6100000F0343E89910E49C0CE277438E8D02EC0 |        45


-----

-----------

SELECT gid, x, y, OSMcodes_br.xy_to_ggeohash(x,y,4)
FROM (
  SELECT  gid, st_x(geom) x, st_y(geom) y
  FROM (SELECT gid, st_centroid(geom) geom FROM osmcodes_br.grid_test1_quadrantes) t1
) t2;

DROP TABLE osmcodes_br.grid_test1_hexadecimal;
CREATE TABLE osmcodes_br.grid_test1_hexadecimal AS
osmcodes_common.ggeohash_to_xybounds
  SELECT gid, OSMcodes_br.cellgeom_xy( OSMcodes_br.ggeohash_to_xy(gid,4) , 512000/4)
  FROM (
    SELECT lpad((j*10+i)::text,2,'0') || c AS gid
    FROM generate_series(0,8) as j, generate_series(0,9) as i, (
      SELECT substr('0123456789abcdef',k,1) as c
      FROM generate_series(1,16) t1(k)
    ) t2
  ) t3
;

INSERT INTO osmcodes_br.grid_test1(gid,geom)
  WITH   scan AS (
      SELECT '45'||c as gid, osmcodes_br.ggeohash_to_xybounds('45'||c,2) as xy_bound
      FROM (
        SELECT substr('0123456789abcdef',k,1) as c
        FROM generate_series(1,4) t1(k)
      ) t2
  )
  SELECT gid||'-'||'pt1',  ST_SetSRID(ST_MakePoint(xy_bound[1],xy_bound[2]),952019 ) as geom FROM scan
  UNION
  SELECT gid||'-'||'pt2',  ST_SetSRID(ST_MakePoint(xy_bound[3],xy_bound[4]),952019 ) as geom FROM scan
;



/*
-- NOT WORKING:
INSERT INTO osmcodes_br.grid_test1_quadrants_full(gid,geom)
  SELECT gid, OSMcodes_br.cellgeom_xy( OSMcodes_br.ggeohash_to_xy(gid,5) , 512000/32)
  FROM (
    SELECT lpad((j*10+i)::text,2,'0') || c AS gid
    FROM generate_series(0,8) as j, generate_series(0,9) as i, (
      SELECT substr('0123456789BCDFGHJKLMNPQRSTUVWXYZ',k,1) as c
      FROM generate_series(1,32) t1(k)
    ) t2
  ) t3
;

--- Debug points:
INSERT INTO osmcodes_br.grid_test1_quadrants_full(gid,geom)
  SELECT gid||'-'||'pt',  ST_SetSRID(ST_MakePoint(xy_bound[1],xy_bound[2]),952019 ) as geom
  FROM (
    SELECT '00'||c as gid, osmcodes_br.ggeohash_to_xybounds('00'||c,5) as xy_bound
    FROM (
      SELECT substr('0123456789BCDFGHJKLMNPQRSTUVWXYZ',k,1) as c
      FROM generate_series(1,32) t1(k)
    ) t2
  ) t3
;

--- Unit box
SELECT c, osmcodes_common.ggeohash_to_uxybounds(c,5)
FROM (
  SELECT substr('0123456789BCDFGHJKLMNPQRSTUVWXYZ',k,1) as c
  FROM generate_series(1,32) t1(k)
) t2;


*/
