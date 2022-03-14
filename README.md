## activerecord-clean-db-structure [ ![](https://img.shields.io/gem/v/activerecord-clean-db-structure.svg)](https://rubygems.org/gems/activerecord-clean-db-structure) [ ![](https://img.shields.io/gem/dt/activerecord-clean-db-structure.svg)](https://rubygems.org/gems/activerecord-clean-db-structure)

Ever been annoyed at a constantly changing `db/structure.sql` file when using ActiveRecord and Postgres?

Spent hours trying to decipher why that one team member keeps changing the file?

This library is here to help!

It cleans away all the unnecessary output in the file every time its updated automatically. This helps avoid merge conflicts, as well as increase readability.

## Installation

Add the following to your Gemfile:

```ruby
gem 'activerecord-clean-db-structure'
```

This will automatically hook the library into your `rake db:migrate` task.

## Supported Rails versions

Whilst there is no reason this shouldn't work on earlier versions, this has only been tested on Rails 4.2 and newer.

It also assumes you use ActiveRecord with PostgreSQL - other ORMs or databases are not supported.

## Caveats

Currently the library assumes all your `id` columns are either SERIAL, BIGSERIAL or uuid. It also assumes the `id` is the primary key.

Multi-column primary keys, as well as tables that don't have `id` as the primary key are not supported right now, and might lead to wrong output.

You can disable this part of the _cleaning_ process in your `config/environments/<environment>.rb` (or `config/application.rb`):

```ruby
Rails.application.configure do
  config.activerecord_clean_db_structure.ignore_ids = true
end
```

## Other options

You can optionally have indexes following the respective tables setting `indexes_after_tables`:

```ruby
Rails.application.configure do
  config.activerecord_clean_db_structure.indexes_after_tables = true
end
```

When it is enabled the structure looks like this:

```sql
CREATE TABLE public.users (
    id SERIAL PRIMARY KEY,
    tenant_id integer,
    email text NOT NULL
);

CREATE INDEX index_users_on_tentant_id ON public.users USING btree (tenant_id);
CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);
```

To enable sorting the table column definitions alphabetically, discarding the actual order provided by `pg_dump`, set `order_column_definitions`:

```ruby
Rails.application.configure do
  config.activerecord_clean_db_structure.order_column_definitions = true
end
```

You can have the schema_migrations values reorganized to reduce the number of merge conflicts by setting `order_schema_migrations_values`:

```ruby
Rails.application.configure do
  config.activerecord_clean_db_structure.order_schema_migrations_values = true
end
```

You can have the unique constraints moved to the create table definitions with `move_unique_constraints_to_tables`:

```ruby
Rails.application.configure do
  config.activerecord_clean_db_structure.move_unique_constraints_to_tables = true
end
```

When `order_schema_migrations_values` is enabled the values are ordered chronologically and the semicolon is placed on a separate line:

```sql
INSERT INTO "schema_migrations" (version) VALUES
 ('20190503120501')
,('20190508123941')
,('20190508132644')
;
```

To reduce the potential for merge conflicts even more, set it to `:jumbled`. This will randomize migration versions in a deterministic fashion, the downside being that the list becomes less readable. The upside is that with a sufficiently large number of migrations, two migration versions are unlikely to end up on adjacent lines:

```ruby
Rails.application.configure do
  config.activerecord_clean_db_structure.order_schema_migrations_values = :jumbled
end
```

## Authors

* [Lukas Fittl](https://github.com/lfittl)

## License

Copyright (c) 2017, Lukas Fittl<br>
activerecord-clean-db-structure is licensed under the 3-clause BSD license, see LICENSE file for details.
