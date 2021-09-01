# grid-tests

Tests for hierarchical grids base in quadrilateral cells and Generalized Geohases.

All implemantations in PostGIS.

* Global:
  - **S2 Geometry**: adapted to move 1 bit and use hierarchical representations. Using [s2geom-PoC](https://github.com/osm-codes/s2geom-PoC) as start point.
  - **H3 Uber**: adaptating projection to use in quadrilaterial partitions after triangules-unions or hexagones-partitions.

* Country-wide: equal-area grids.
  - Brazil experiment: 
      - Grade Estatística do IBGE em sua **versão compacta**: sucesso (!), mudou-se para https://github.com/osm-codes/BR_IBGE#readme<br/>Apresenta uma nova estrutura de dados, mais enxuta e consistente com uso como geocódigo. 
      - [**Nova Grade Estatística Brasil**](https://github.com/osm-codes/BR_new#readme) proposta pelo Instituto para substituir a Grade original IBGE e servir de referência para os geocódios oficiais do Brasil, incluindo o Novo CEP. Os seus geocódigos consistentem de Geohashes adaptados.
  - Colômbia experiment: avaliando...  [Projeção oficial](https://qgisusers.co/es/blog/configurando-la-proyeccion-ctm12-en-qgis/) quase aprobada. A sua [distorção de área é suportável](https://origen.igac.gov.co/) (ver fig.7). A adoção oficial é confirmada pela [Resolução IGAC 529 de 2020](https://igac.gov.co/sites/igac.gov.co/files/normograma/resolucion_529_de_2020.pdf).
