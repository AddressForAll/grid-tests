dbname=osmcodes

all:
	@echo "------------"
	@echo "Use psql builds datatbase '$(dbname)'."
	@echo "Possible targets for this makefile:"
	@echo " * all0: build all from zero (database, schemas and tests);"
	@echo " * sql_build: only schemas and pub scripts;"
	@echo " * sql_test: only redo test scripts."
	@echo
	@echo " NOTES: change dbname to non-standard database."
	@echo

all0: sql_prepare sql_build sql_test

sql_prepare:
	psql postgres://postgres@localhost -c "CREATE DATABASE $(dbname)"

sql_build:
	psql postgres://postgres@localhost/$(dbname) -f step1_libPub.sql
	psql postgres://postgres@localhost/$(dbname) -f step2_libOsmCode.sql
	psql postgres://postgres@localhost/$(dbname) -f step3_libGrid.sql

sql_test:
	psql postgres://postgres@localhost/$(dbname) -f step4_prepareGrid.sql
