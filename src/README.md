
## Códigos-fonte
Ainda estamos testando as diversas grades em diversos países... Em breve alguns desses testes serão transferidos para um projeto mais específico e tomando o  código-fonte como algo mais definitivo. Por hora temos:

* [BR_IBGE](BR_IBGE): a "grade oficial do Brasil" vigente, por falta de outra melhor. Nos fontes demonstramos como o identificador de célula do IBGE pode 6
* [BR_new](BR_new): a nossa proposta de "nova grade oficial do Brasil", com melhoras sobre a grade IBGE.

Para todos eles o método de instação é o tradicional comando `make` do Unix, que tem seu arquivo de configuração nos respectivos `makefile`s.

## Instruções gerais e compatibilidade

Use `make` (da pasta `/src/*` da fonte desejada) para ver instruções e rodar _targets_ desejados.
O software foi testado com as seguintes versões e configurações:

* PostgreSQL v12 ou v13, e PostGIS v3. Disponível em *localhost* como service. Rodar make com outra `pg_uri` se o usuário não for *postgres*
* `psql` v13. Configurado no `makefile` para rodar já autenticado pelo usuário do terminal .
* pastas *default*: rodar o `make` a partir da própria pasta *git*, `/src/BR_new`. Geração de arquivos pelo servidor local PostgreSQL em `/tmp/pg_io`.

Para testes pode-se usar `git clone https://github.com/AddressForAll/grid-tests.git` ou uma versão específica zipada, por exemplo `wget -c https://github.com/AddressForAll/grid-tests/archive/refs/tags/v0.1.0.zip`. Em seguida, estes seriam os procedimentos básicos para rodar o *make* em terminal *bash*, por exemplo:
```sh
cd grid-tests/src/BR_new
make
```

O `make` sem target vai apnas listar as opções. Para rodar um target específico usar `make nomeTarget`.
Para rodar com outra base ou outra URI de conexão com PostreSQL server, usar por exemplo <br/>`make db=outraBase pg_uri=outraConexao nomeTarget`.
