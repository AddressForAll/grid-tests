dbname=osmcodes
pg_uri=postgres://postgres@localhost

all:
	@echo "------------"
	@echo "Will use psql and datatbase '$(dbname)'."
	@echo "Possible targets for this makefile:"
	@echo " * all_lite: build basic in a existing database, and tests"
	@echo " * all_DANGER: build all from zero (database, schemas and tests);"
	@echo " * sql_build: only build basic (schemas and pub scripts);"
	@echo " * sql_test: only redo test scripts."
	@echo
	@echo " NOTES: change dbname to non-standard database."
	@echo

all_lite:  sql_build sql_test

all_DANGER: sql_perigo sql_build sql_test

sql_perigo:
	@echo "## Tem certeza que quer fazer DROP da base $(dbname)?  (ENTER ou ^C para sair)"
	@read _sim_certeza_com_ENTER_
	@psql $(pg_uri) -c "DROP DATABASE $(dbname)"
	@psql $(pg_uri) -c "CREATE DATABASE $(dbname)"

sql_build:
	@echo
	@echo "## Preparando base com PostGIS, libPub, OSMcodes-comum e OSMcodes-Brasil..."
	@echo
	psql $(pg_uri)/$(dbname) -f step1-libPub.sql
	psql $(pg_uri)/$(dbname) -f step2-lib_OsmCodes.sql
	psql $(pg_uri)/$(dbname) -f step3-lib_BR.sql

sql_test:
	@echo "## TESTES em construção!"
	# psql $(pg_uri)/$(dbname) -f step4-BR_tests.sql
