# grid-tests

Tests for hierarchical grids base in quadrilateral cells and Generalized Geohases.

All implemantations in PostGIS.

* Global:
 - **S2 Geometry**: adapted to move 1 bit and use hierarchical representations.
 * **H3 Uber**: adaptating projection to use in quadrilaterial partitions after triangules-unions or hexagones-partitions.

* Country-wide: equal-area grids.
  - [Brazil experiment](./src/BR_IBGE): **Grade Estatística do IBGE** adaptada para hierarquias na base16h e 32.
  - Colômbia experiment: avaliando...
