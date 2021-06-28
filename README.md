# grid-tests

Tests for hierarchical grids base in quadrilateral cells and Generalized Geohases.

All implemantations in PostGIS.

* Global:
  - **S2 Geometry**: adapted to move 1 bit and use hierarchical representations. Using [s2geom-PoC](https://github.com/osm-codes/s2geom-PoC) as start point.
  - **H3 Uber**: adaptating projection to use in quadrilaterial partitions after triangules-unions or hexagones-partitions.

* Country-wide: equal-area grids.
  - Brazil experiment: 
      - [**Grade Estatística do IBGE**](./src/BR_IBGE): nova estrutura de dados, mais enxuta e consistente com uso como geocódigo. 
      - [**OSMcodes Brasil**](./src/OSMcodes_BR): Geohashes (base16h e base32) sobre a grade IBGE adaptada.
  - Colômbia experiment: avaliando...
