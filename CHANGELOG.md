# Changelog

## Unreleased

* Order the `COMMENT ON COLUMN` statements with the column definitions when
  `order_column_definitions` is enabled, so that the file stays consistent with
  itself and survives a round trip through the database
* Move each `COMMENT ON INDEX` statement to its index when `indexes_after_tables`
  is enabled, rather than leaving it stranded in the block pg_dump wrote it in
* Order the per-column `ALTER TABLE` statements (`SET DEFAULT`, `SET STATISTICS`,
  `SET STORAGE`) with the column definitions as well. pg_dump writes them in
  attnum order, so they had the same round trip problem as the column comments

* Fix `order_schema_migrations_values` deleting every migration version when the
  cleaner runs over its own output. The reader now accepts both the raw pg_dump
  format and the format the cleaner writes, and raises `NoSchemaMigrationValues`
  instead of writing an empty version list
* Make `run` idempotent, so that cleaning an already cleaned file is a no-op
* Fix `indexes_after_tables` duplicating an index whose name needs quoting, and
  dropping an index whose name contains a dot
* Fix `indexes_after_tables` copying an index onto every table when the index
  target has no schema prefix
* Handle `CREATE UNLOGGED TABLE` in `order_column_definitions`,
  `indexes_after_tables`, `ignore_ids` and `move_unique_constraints_to_tables`
* Fix `order_column_definitions` moving columns into the next table when a table
  ends with a `USING`, `INHERITS`, `TABLESPACE` or `SERVER` clause
* Fix `move_unique_constraints_to_tables` discarding the constraint when the
  table ends with a `WITH` clause
* Require `English`, which the primary key and unique constraint cleanups need,
  and drop the undeclared ActiveSupport dependency of `CleanDump`
* Escape table, column and index names before interpolating them into patterns
* `run` now returns the cleaned dump instead of `nil`
* Remove the duplicate `order_column_definitions` call
* Ask Rails which files `db:schema:dump` wrote instead of rebuilding the names.
  This fixes the task looking for `primary_structure.sql`, which does not exist
  and made `db:schema:dump` fail on an application with more than one database
  that has schema tasks enabled. It also honours `ENV["SCHEMA"]`, the
  per-database `schema_dump` setting, and skips replicas, databases with
  `database_tasks: false`, and databases that dump to `schema.rb`
* Stop defining a top level `PRE_6_1` constant in the host application
* Add specs for the rake task, and pin the development dependencies to the Rails
  version the consuming application runs

## 0.4.0    2019-08-27

* Add "indexes_after_tables" option to allow indexes to be placed following the respective tables [#13](https://github.com/lfittl/activerecord-clean-db-structure/pull/13) [Giovanni Kock Bonetti](https://github.com/giovannibonetti)
* Add "order_schema_migrations_values" option to prevent schema_migrations values causing merge conflicts [#15](https://github.com/lfittl/activerecord-clean-db-structure/pull/15) [Nicke van Oorschot](https://github.com/nvanoorschot)
* Add "order_column_definitions" option to sort table columns alphabetically [#11](https://github.com/lfittl/activerecord-clean-db-structure/pull/11) [RKushnir](https://github.com/RKushnir)
* Generalize handling of schema names to not assume public
* Rails 6 support
  * Fix Rails 6 compatibility [#16](https://github.com/lfittl/activerecord-clean-db-structure/pull/16) [Giovanni Kock Bonetti](https://github.com/giovannibonetti)
  * Fix handling of multiple structure.sql files
* Remove Postgres 12 specific GUCs
* Generalize handling of schema names to not assume public
* Fix whitespace issue for config settings, remove default_with_oids


## 0.3.0    2019-05-07

* Add "ignore_ids" option to allow disabling of primary key substitution logic [#12](https://github.com/lfittl/activerecord-clean-db-structure/pull/12) [Vladimir Dementyev](https://github.com/palkan)
* Compatibility with Rails 6 multi-database configuration


## 0.2.6    2018-03-11

* Fix regular expressions to support schema qualification changes in 10.3


## 0.2.5    2017-11-15

* Filter out indices belonging partitioned tables


## 0.2.4    2017-11-02

* Remove pg_buffercache extension if present (its only used for statistics purposes)
* Remove extension comments if present - they can prevent non-superusers from
  restoring the tables, and are never used together with Rails anyway


## 0.2.3    2017-10-21

* pg 10.x adds AS Integer to structure.sql format [Nathan Woodhull](https://github.com/woodhull)


## 0.2.2    2017-08-05

* Support Rails 5.1 primary key UUIDs that rely on gen_random_uuid()


## 0.2.1    2017-06-30

* Allow primary keys to be the last column of a table [Clemens Kofler](https://github.com/clemens)
  - Special thanks to [Jon Mohrbacher](https://github.com/johnnymo87) who submitted a similar earlier change


## 0.2.0    2017-03-20

* Reduce dependencies to only require ActiveRecord [Mario Uher](https://github.com/ream88)
* Support Rails Engines [Mario Uher](https://github.com/ream88)
* Clean up more comment lines [Clemens Kofler](https://github.com/clemens)


## 0.1.0    2017-02-12

* Initial release.
