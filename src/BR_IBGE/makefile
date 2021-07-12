
all:
	@echo "------------"
	@echo "Use psql shp2pgsql and builds datatbase 'ibge'."
	@echo "Possible targets for this makefile:"
	@echo " * all0: build all from zero, database and downloads"
	@echo " * sql_prepare: build database and start SQL scripts"
	@echo " * grade: download and build Grade IBGE on database"
	@echo " * clean: remove all IBGE tables and files"

all0: sql_prepare grade

clean: clean_sql clean_files

sql_prepare:
	psql postgres://postgres@localhost -c "CREATE DATABASE ibge"
	psql postgres://postgres@localhost/ibge < step2_pubLib.sql

grade:
	sh step1_download_IBGE.sh
	sh step3_build_IBGE.sh
	psql postgres://postgres@localhost/ibge < step4_prepareGridLibs.sql
	psql postgres://postgres@localhost/ibge < step5_asserts.sql

clean_sql:
	psql postgres://postgres@localhost/ibge < step6_dropOldIBGE.sql

clean_files:
	rm -r /tmp/sandbox/ibge_grade/
