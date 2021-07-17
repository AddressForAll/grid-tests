pg_db=ibge

info:
	@echo "------------"
	@echo "Builds the Compact IBGE's Grade Estatística do Censo de 2010"
	@echo "------------"
	@echo "Builds datatbase '$(pg_db)' with psql, change with pg_db=DatabaseName"
	@echo "Possible targets for this git package:"
	@echo " * all1: build all by alternative 1, downloading original grid"
	@echo " * all2: build all by alternative 2, from zip file"
	@echo " * sql_prepare: build and prepare database with pubLib"
	@echo " * grid_orig_get: download and build the original Grade IBGE on database"
	@echo " * grid_alt1_fromOrig: builds by alternative 1, from original, the Compact IBGE grid"
	@echo " * grid_alt2_fromZip: builds, by alternative 2, from Zip, the Compact IBGE grid"
	@echo " * clean: remove all IBGE tables and files"

## Abstract targets:

all1: sql_prepare grid_orig_get grid_alt1_fromOrig

all2: sql_prepare grid_alt2_fromZip

clean: clean_sql clean_files

## Concrete builder targets:

sql_prepare:
	psql postgres://postgres@localhost -c "CREATE DATABASE $(pg_db)"
	psql postgres://postgres@localhost/$(pg_db) < step2_pubLib.sql

grid_orig_get:
	sh step1_download_IBGE.sh
	sh step3_build_IBGE.sh

grid_alt1_fromOrig:
	psql postgres://postgres@localhost/$(pg_db) < step4_prepareGridLibs.sql
	psql postgres://postgres@localhost/$(pg_db) < step5opt1_fromOriginal.sql
	psql postgres://postgres@localhost/$(pg_db) < step6_asserts.sql

grid_alt2_fromZip: ../../data/BR_IBGE/grid_ibge_censo2010_info.zip
	@echo "recuperando dados do git no PostgreSQL"
	psql postgres://postgres@localhost/$(pg_db) < step4_prepareGridLibs.sql
	unzip -d /tmp  ../../data/BR_IBGE/grid_ibge_censo2010_info.zip
	psql postgres://postgres@localhost/$(pg_db) < step5opt2_fromCsv.sql
	rm /tmp/grid_ibge_censo2010_info.csv
	psql postgres://postgres@localhost/$(pg_db) < step6_asserts.sql

## save ans check files:
grid_alt2_toZip:
	@echo "-- creating CSV and ZIP of new grid:"
	psql postgres://postgres@localhost/$(pg_db) -c "COPY grid_ibge.censo2010_info TO '/tmp/grid_ibge_censo2010_info.csv' CSV HEADER"
	rm -f /tmp/grid_ibge_censo2010_info.zip
	zip /tmp/grid_ibge_censo2010_info.zip  /tmp/grid_ibge_censo2010_info.csv
	@echo "Saved zip at /tmp"

checksums:
	@echo "Calculating checksums of original file"
	cd /tmp/sandbox/ibge_grade; md5sum grade_id*.zip > /tmp/sandbox/md5sum.txt
	cd /tmp/sandbox/ibge_grade; sha256sum grade_id*.zip > /tmp/sandbox/sha256sum.txt
	@echo "Use diff to compare with git checks"

## Concrete cleaner targets:

clean_sql:
	@echo "Drops the original grid tables, remains the compact one"
	psql postgres://postgres@localhost/$(pg_db) < step6_dropOldIBGE.sql

clean_files:
	@echo "Delete the original grid shapefiles"
	rm -r /tmp/sandbox/ibge_grade/
