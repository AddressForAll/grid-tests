## Grade Estatística IBGE

Use `make`.

## Adaptações nos scripts

Conforme necessidades os scripts podem ser facilmente adaptados, desde que refatorando nos diversos scripts. As adaptações mais comuns são:

* SRID da projeção Albers do IBGE: mude o valor 952019 para o valor desejado.

* Uso do *SQL schema* `public` (sem *schema*) no lugar de : basta eliminar os comandos DROP SCHEMA e CREATE SCHEMA correspondentes, e alterar todas as ocorrências de `grid_ibge.` para `public.`.

* Discarte do preparo: a operação de `DROP CASCADE` pode ser comentada caso esteja realizando testes, fazendo por partes, ou reusando o *schema* em outras partes do seu sistema.

## Nomenclatura das células

Todas as tabelas criadas pelos shapfiles originais do IBGE possuem a estrutura:

Column   |            Type             | Comments                 
----------|----------------------------|---------
gid        | integer                     | (redundante com `id_unico`) ID de tabelas de geometria, gerado por antigo padrão.
id_unico   | character varying(50)       | ID real da célula. String do tipo `{lado}E{X}N{Y}`, com referência XY na projeção Albers.
nome_1km   | character varying(16)       | (redundante para apoio na agregação de 1 km)
nome_5km   | character varying(16)       | (redundante para apoio na agregação de 5 km)
nome_10km  | character varying(16)       | (redundante para apoio na agregação de 10 km)
nome_50km  | character varying(16)       | (redundante para apoio na agregação de 50 km)
nome_100km | character varying(16)       | (redundante para apoio na agregação de 100 km)
nome_500km | character varying(16)       | (redundante para apoio na agregação de 500 km)
quadrante  | character varying(50)       | (redundante para localizar quadrante ou apoio na agregação de 500 km)
masc       | integer                     | população do sexo masculino
fem        | integer                     | população do sexo feminino
pop        | integer                     | população total (conforme Censo 2010) no interior da célula
dom_ocu    | integer                     | ??
shape_leng | numeric                     | (redundante)
shape_area | numeric                     | (redundante)
geom       | geometry(MultiPolygon,4326) | geometria da célula em coordenadas LatLong WGS84 (sem projeção)

Em qualquer quadrante *qq* o resultado de `SELECT DISTINCT substr(id_unico,1,4) id_prefix FROM grade_IDqq` será o conjunto
{"1KME",&nbsp;"200M"}. Isso significa que todos os demais atributos `nome_` (e `quadrante`) são reduntantes. Só existem esses dois tipos de célula, sendo a menor delas, 200 m, usada para o meio urbano, onde se faz necessária uma cobertura mais densa. No caso das células com `id_prefix` "1KME", de 1 km de lado, teremos `id_unico=nome_1km`.

Quanto ao signiicado da string de `id_unico`, que segue a *URI Template* `{lado}E{X}N{Y}`, onde `lado` é o tamanho do lado, `X` e `Y` as "coordenadas da célula" tendo como referência o seu canto... Qual canto?
Tomando como referência as coordenadas do centro da geometria (função PostGIS `ST_Centroid`)
percebemos que o IBGE não adotou uma convenção regular: para células de 1km basta truncar ou usar o coanto inferior direito,
mas para células de 200 metros é o canto superior direito. Abaixo o uso de "X_centro-100" e "Y_centro+100" indica as coordenadas do canto que validado por `id_unico`.

```SQL
SELECT * FROM (
  SELECT is_200m, id_unico_parts,
       round( ST_x(ST_Transform(geom,952019)) + iif(is_200m,-100,-500) )::int x,
       round( ST_y(ST_Transform(geom,952019)) + iif(is_200m,+100,-500) )::int y
  FROM (
    SELECT substr(id_unico,1,4)='200M' AS is_200m,
      CASE
        WHEN id_unico=nome_1km THEN array[substr(id_unico,5,4), substr(id_unico,10)]
        ELSE  array[substr(id_unico,6,5), substr(id_unico,12)]
        END id_unico_parts,
      ST_centroid(st_transform(geom,952019)) as geom
    FROM grade_id45                        
  ) t1
) t2  -- WHERE homologando a heuristica da nomenclatura das células:
WHERE substr(x::text,1,length(id_unico_parts[1]))!=id_unico_parts[1]
   OR substr(y::text,1,length(id_unico_parts[2]))!=id_unico_parts[2]
ORDER BY 1;
```

A heuristca também sugere como realizar a resulução dos geocodigos da Grade IBGE, exemplos:
* Solicitado XY relativo a `1KME5300N9350`: ...
* Solicitado XY relativo a `200ME53000N96322`: ...
