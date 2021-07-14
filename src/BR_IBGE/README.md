# Grade Estatística IBGE

* CONVENÇÕES IBGE
    * [Nomenclatura das células](#nomenclatura-das-células)
* ALGORITMOS IMPLANTADOS
    * [Resolução dos identificadores de célula](#resolução-dos-identificadores-de-célula)
    * [Resolução de ponto em célula](#resolução-de-ponto-em-célula)
    * [Adaptações para outros países](#adaptações-para-outros-países)
* [INSTALAÇÃO](#instalação)
    * [xzxx](#xxxx)

------------
# CONVENÇÕES IBGE

## Estrutura das tabelas

Todas as tabelas criadas pelos *shapfiles* originais do IBGE (vide ) possuem a estrutura:

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

## Nomenclatura das células

Em qualquer quadrante *qq* o resultado de `SELECT DISTINCT substr(id_unico,1,4) id_prefix FROM grade_IDqq` será o conjunto
{"1KME",&nbsp;"200M"}. Isso significa que todos os demais atributos `nome_` (e `quadrante`) são reduntantes. Só existem esses dois tipos de célula, sendo a menor delas, 200 m, usada para o meio urbano, onde se faz necessária uma cobertura mais densa. No caso das células com `id_prefix` "1KME", de 1 km de lado, teremos `id_unico=nome_1km`.

Quanto ao signiicado da string de `id_unico`, que segue a *URI Template* `{lado}E{X}N{Y}`, onde `lado` é o tamanho do lado da célula, `X` e `Y` as "coordenadas da célula" tendo como referência o seu canto... Qual canto?
Tomando como referência as coordenadas do centro da geometria (função PostGIS `ST_Centroid`)
percebemos que o IBGE não adotou uma convenção regular: para células de 1 km basta truncar ou usar o canto inferior direito,
mas para células de 200 metros é o canto superior direito.

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
) t2 -- WHERE homologando a heuristica da nomenclatura das células:
WHERE substr(x::text,1,length(id_unico_parts[1]))!=id_unico_parts[1]
   OR substr(y::text,1,length(id_unico_parts[2]))!=id_unico_parts[2]
ORDER BY 1;
```
O algoritmo foi validado contra células de 200m (flag `is_200m`) e 1km. conforme `id_unico`.  Para as células de 200m foram validadas as coordenadas "X_centro-100" e "Y_centro+100", para células de 1km as coordenadas "X_centro-500" e "Y_centro-500".

A mesma heuristca pode ser utilizada para a recuperação de dados a partir do identificador IBGE das células de 200 m e de 1 km. A generalização para células maiores (10 km, 50 km etc.) requer uma avaliação mais detalhada, a seguir.

# ALGORITMOS IMPLANTADOS

## Resolução dos identificadores de célula

A consulta abaixo funcionou para o quadrante 45 (tabela `grade_id45`) e algumas outras, mas falha para a grande maioria, principalmente quando o número de dígitos aumenta para acomodar a unicidade (por exemplo nos quadrantes do extremo norte).

Está pendente portanto um algoritmo, mesmo que heurístico, capaz de reproduzir a partir do centróide da célula o seu identificador IBGE.

```SQL
SELECT * FROM (
  SELECT array[substr(id,5+digs,4), substr(id,10+digs)] id_parts,
        round( (ST_x((geom)) - sub) / div )::int x,
        round( (ST_y((geom)) - sub) / div )::int y
  FROM (
    SELECT id, digs,
           CASE WHEN ld>100000 THEN 0.001 WHEN ld>10000 THEN 0.01 ELSE 0.1 END*ld AS div,
           CASE WHEN is_five THEN 0.25 ELSE 0.50 END*ld AS sub,
           ST_Transform(  ST_centroid( ST_Collect(geom) ),  952019) AS geom
    FROM (
      SELECT *,
        10^(3+digs + CASE WHEN is_five THEN 1 ELSE 0 END) as ld
        FROM ( SELECT t0a.*, is_five, digs FROM (
            SELECT *, nome_10km AS id --> Trocar por nome_1km, nome_5km, nome_50km ou nome_100km.
            FROM grade_id45 --> Trocar por outro quadrante (44,35,etc)
        ) t0a, LATERAL (SELECT
          substr(t0a.id,1,1)='5' AS is_five,
          length(t0a.id)-13 as digs
        ) t0b  
      ) t0c
    ) t0f
    GROUP BY 1,2,3,4
  ) t1
) t2  -- WHERE homologando a heuristica da nomenclatura das células:
WHERE substr(x::text,1,length(id_parts[1]))!=id_parts[1]
   OR substr(y::text,1,length(id_parts[2]))!=id_parts[2]
ORDER BY 1;
```

O comportamento regular esperado nos parâmetros de
`(X_centro-sub)/div` e `(Y_centro-sub)/div`
seria o seguinte:

Lado<br/>(km)|Exemplo| digs|   ld |  sub | div
----|-----------------|----|------|------|-----
1   | 1KME5300N9632   | 0  | 1000 | 500 | 100
5   | 5KME5300N9630   | 0  | 10000 | 2500 | 1000
10  | 10KME5300N9630  | 1  | 10000 | 5000 | 1000
50  | 50KME5300N9600  | 1  | 100000 | 25000 | 1000
100 | 100KME5300N9550 | 2  | 100000 | 50000 | 1000

Com arredondamento seguido de multipicação por 10 por exemplo pode-se amplicar o número de casos, mas ainda teriam de ser tratados quadrantes como o 83 (tabela `grade_id83`) onde os identificadores são maiores. Por exemplo 1KME4300N11825 e 5KME4300N11825 possuem 4 dígitos em X e 5 dígitos em Y.

<!--
SELECT DISTINCT min(id) as min_id digs, ld, sub, div
FROM (
  SELECT id, digs, ld,
         CASE WHEN ld>100000 THEN 0.001 WHEN ld>10000 THEN 0.01 ELSE 0.1 END*ld AS div,
         CASE WHEN substr(id,1,1)='5' THEN 0.25 ELSE 0.50 END*ld AS sub,
         ST_Transform(  ST_centroid( ST_Collect(geom) ),  952019) AS geom
  FROM (
    SELECT *,
      length(id)-13 as digs,
      10^(3+length(id)-13 + CASE WHEN substr(id,1,1)='5' THEN 1 ELSE 0 END) as ld
      FROM ( SELECT *, nome_10km AS id FROM grade_id83) t00
           -- Trocar por nome_1km, nome_5km, nome_50km ou nome_100km.
      ) t0
  GROUP BY 1,2,3,4, 5
) t1;
... como realizar a resulução dos geocodigos da Grade IBGE, exemplos:
* Solicitado XY relativo a `1KME5300N9350`: ...
* Solicitado XY relativo a `200ME53000N96322`: ...
-->

## Resolução de ponto em célula

A solução proposta na presente versão indexada por XY permite usar a representação interna invez da busca geométrica.
Por exemplo o ponto XY=(4580490.89,8849499.5) pode primeiramente ser arredondado para inteiros, e
em seguida a busca se realizaria através de indexão otimizada em cada coordenada, nas tabelas `mvw_censo2010_info_Xsearch` e `mvw_censo2010_info_Ysearch`.

Suponhamos a busca por **X=4580491**, ela será realizada pelo algoritmo:

```sql
SELECT x FROM (
  (
    SELECT x FROM grid_ibge.mvw_censo2010_info_xsearch
    WHERE x >= 4580491 ORDER BY x LIMIT 1
  )  UNION ALL (
    SELECT x FROM grid_ibge.mvw_censo2010_info_xsearch
    WHERE x < 4580491 ORDER BY x DESC LIMIT 1
  )
) t
ORDER BY abs(4580491-x) LIMIT 1;
```

Depois de fazer mesmo em Y, obtemos a suposta célula que contém o ponto XY solicitado.
A função  *search_cell* da biblioteca *grid_ibge* retorna não-nulo, em 0.042 ms, quando existe uma célula contendo o ponto:
```SQL
SELECT * FROM grid_ibge.censo2010_info
WHERE xy=grid_ibge.search_cell(4580490.89::int, 8849499.5::int);
```

## Adaptações para outros países

Conforme necessidades, os _scripts_ SQL podem ser facilmente adaptados, desde que refatorando nos diversos scripts. As adaptações mais comuns são:

* SRID da projeção Albers do IBGE: mude o valor 952019 para o valor desejado.

* Uso do *SQL schema* `public` (sem *schema*) no lugar de : basta eliminar os comandos DROP SCHEMA e CREATE SCHEMA correspondentes, e alterar todas as ocorrências de `grid_ibge.` para `public.`.

* Discarte do preparo: a operação de `DROP CASCADE` pode ser comentada caso esteja realizando testes, fazendo por partes, ou reusando o *schema* em outras partes do seu sistema.

----------------

## INSTALAÇÃO

Use no terminal, a parir desta pasta, o comando `make` para listar as alternativas de instalação integral (*all1* ou *all2* descritas abaixo), que rodam todos os  _targets_ necessários, exceto `clean`. O comando `make` sem target informa também o que fazem os demais targets, que podem ser executados em separado.

Na pasta anterior, em [/src/README.md](../README.md), as versões e configurações necessárias são detalhadas.

### Instalando somente o zip
Recomenda-se o mais simples, que é obter a **Grade Estatística IBGE Compacta** diretamente a partir do CSV zipado desta distribuição git. Basta executar, em terminal Linux:

```sh
make all2
```

### Reproduzindo o processo completo

Se o objetivo for reproduzir, auditorar ou atualizar a  partir da **Grade Estatística IBGE Original**, demora um pouco mais e requer um pouco mais de espaço em disco, mas é igualmente simples. Basta executar no terminal Linux, nesta pasta, o comando:

```sh
make all1
```

Ou executar, na sequência, cada um dos _targets_ definidos nas dependências de *all1*.
No final de `make grid_orig_get` (ou meio do `make all1`) todas as tabelas de quadrantes,  `grade_id*`, terão sido criadas:
```
 grade_id04: 66031 itens inseridos
 grade_id13: 31126 itens inseridos
 grade_id14: 537732 itens inseridos
 grade_id15: 306162 itens inseridos
 ...
 grade_id92: 5091 itens inseridos
 grade_id93: 1901 itens inseridos
(56 rows)
```

Executando em seguida o `make grid_alt1_fromOrig` (final do `make all1`), as tabelas são lidas e as geometrias de célula são convertidas em coordenadas de centro (na função `grid_ibge.censo2010_info_load()`), para formar o identificador de célula com representação binária compacta (representado em *bigint*) na tabela `grid_ibge.censo2010_info`.  Essa tabela pode ainda ser gravada como CSV,  

```sql
COPY grid_ibge.censo2010_info TO '/tmp/grid_ibge_censo2010_info.csv' CSV HEADER;
```
Se por acaso o IBGE gerar uma nova versão da grade original, o arquivo CSV deve então ser zipado com o comando `zip` Linux e gravado no presente repositório *git*, na pasta [/data/BR_IBGE](https://github.com/AddressForAll/grid-tests/tree/main/data/BR_IBGE).
