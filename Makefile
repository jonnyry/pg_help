PSQL     := psql -U postgres
PG_PROVE := pg_prove -U postgres --verbose --ext .sql

.PHONY: help setup test lint

## Show this help.
help:
	@awk '/^## /{desc=substr($$0,4)} /^[a-z][a-z-]+:/{printf "  %-15s %s\n", substr($$1,1,length($$1)-1), desc}' $(MAKEFILE_LIST)

## Load pg_describe and the example schema into the database.
setup:
	$(PSQL) -f pg_describe.sql
	$(PSQL) -f tests/test-schema.sql

## Run the full test suite.
test:
	$(PG_PROVE) tests/test.sql

## Run plpgsql_check linter against all pg_describe functions.
lint:
	$(PSQL) -v ON_ERROR_STOP=1 -f tests/lint.sql
