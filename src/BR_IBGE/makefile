
all:
	@echo "------------"
	@echo "Use psql shp2pgsql and builds datatbase 'ibge'."
	@echo "Possible targets for this makefile:"
	@echo " * all0: build all from zero, database and downloads"
	@echo " * sql_prepare: build database and SQL scripts"
	@echo " * grade_ibge: download and build Grade IBGE on database"
	@echo " * newgrid: builds the New Grid at SQL"
	@echo " * clean: remove all IBGE tables and files"

all0: sql_prepare grade_ibge newgrid

clean: clean_sql clean_files

sql_prepare:
	psql postgres://postgres@localhost -c "CREATE DATABASE ibge"
	psql postgres://postgres@localhost/ibge < step2_gradeHierarquica.sql

grade_ibge:
	sh step1_download_IBGE.sh
	sh step3_build_IBGE.sh

newgrid:
	psql postgres://postgres@localhost/ibge < step4_buildNewIBGE.sql
	psql postgres://postgres@localhost/ibge < step5_buildNewGrid.sql

clean_sql:
	psql postgres://postgres@localhost/ibge < step6_dropOldIBGE.sql

clean_files:
	rm -r /tmp/sandbox/ibge_grade/
