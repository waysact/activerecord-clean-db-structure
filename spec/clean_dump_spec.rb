# frozen_string_literal: true

require 'activerecord-clean-db-structure/clean_dump'

RSpec.describe ActiveRecordCleanDbStructure::CleanDump do
  describe '#run' do
    let(:dump) do
      <<~STRUCTURE_SQL
        INSERT INTO "schema_migrations" (version) VALUES
        ('20220309184009'),
        ('20220309101143'),
        ('20220221045523'),
        ('20220202235304'),
        ;
      STRUCTURE_SQL
    end

    let(:options) { {} }

    subject { described_class.new(dump.dup, options) }

    context 'when ordering schema migrations' do
      let(:options) { { order_schema_migrations_values: true } }
      it 'works' do
        subject.run
        expect(subject.dump).to eq(<<~STRUCTURE_SQL)
          INSERT INTO "schema_migrations" (version) VALUES
           ('20220202235304')
          ,('20220221045523')
          ,('20220309101143')
          ,('20220309184009')
          ;
        STRUCTURE_SQL
      end
    end

    context 'when re-running over already cleaned schema migrations' do
      let(:options) { { order_schema_migrations_values: true } }

      it 'keeps every migration version' do
        first_pass = described_class.new(dump.dup, options).tap(&:run).dump
        second_pass = described_class.new(first_pass.dup, options).tap(&:run).dump

        expect(second_pass).to eq(first_pass)
      end
    end

    context 'when the schema_migrations INSERT has no values' do
      let(:dump) do
        <<~STRUCTURE_SQL
          INSERT INTO "schema_migrations" (version) VALUES
          ;
        STRUCTURE_SQL
      end

      let(:options) { { order_schema_migrations_values: true } }

      it 'raises instead of writing an empty list' do
        expect { subject.run }.to raise_error(described_class::NoSchemaMigrationValues)
      end
    end

    context 'when there is no schema_migrations INSERT' do
      let(:dump) { "CREATE TABLE waysact.things (\n    id BIGSERIAL\n);\n" }

      let(:options) { { order_schema_migrations_values: true } }

      it 'leaves the dump alone' do
        subject.run
        expect(subject.dump).to eq(dump)
      end
    end

    context 'when jumbling schema migrations' do
      let(:options) { { order_schema_migrations_values: :jumbled } }
      it 'works' do
        subject.run
        expect(subject.dump).to eq(<<~STRUCTURE_SQL)
          INSERT INTO "schema_migrations" (version) VALUES
           ('20220309101143')
          ,('20220202235304')
          ,('20220221045523')
          ,('20220309184009')
          ;
        STRUCTURE_SQL
      end
    end

    context 'when reversing schema migrations' do
      let(:options) { { order_schema_migrations_values: :reversed } }
      it 'sorts by reversed migration ID' do
        subject.run
        expect(subject.dump).to eq(<<~STRUCTURE_SQL)
          INSERT INTO "schema_migrations" (version) VALUES
           ('20220221045523')
          ,('20220309101143')
          ,('20220202235304')
          ,('20220309184009')
          ;
        STRUCTURE_SQL
      end
    end

    context 'when schemas_extensions_if_not_exists is enabled' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE SCHEMA waysact;

          CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA waysact;

          CREATE EXTENSION plrust WITH SCHEMA plrust;
        STRUCTURE_SQL
      end

      let(:options) { { schemas_extensions_if_not_exists: true } }

      it 'adds IF NOT EXISTS to CREATE SCHEMA' do
        subject.run
        expect(subject.dump).to include('CREATE SCHEMA IF NOT EXISTS waysact;')
        expect(subject.dump).not_to match(/^CREATE SCHEMA (?!IF)/)
      end

      it 'adds IF NOT EXISTS to CREATE EXTENSION' do
        subject.run
        expect(subject.dump).not_to match(/CREATE EXTENSION (?!IF)/)
      end
    end

    context 'when schemas_extensions_if_not_exists is not set' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE SCHEMA waysact;

          CREATE EXTENSION plrust WITH SCHEMA plrust;
        STRUCTURE_SQL
      end

      it 'leaves statements unchanged' do
        subject.run
        expect(subject.dump).to include('CREATE SCHEMA waysact;')
        expect(subject.dump).to include('CREATE EXTENSION plrust')
        expect(subject.dump).not_to include('IF NOT EXISTS')
      end
    end

    context 'when cleaning up sequences' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.things (
              id bigint NOT NULL
          );

          CREATE SEQUENCE waysact.things_id_seq
              START WITH 1
              INCREMENT BY 1
              NO MINVALUE
              NO MAXVALUE
              CACHE 1;

          ALTER TABLE waysact.things_id_seq OWNER TO waysact;

          ALTER SEQUENCE waysact.things_id_seq OWNED BY waysact.things.id;

          ALTER TABLE ONLY waysact.things ALTER COLUMN id SET DEFAULT nextval('waysact.things_id_seq'::regclass);
        STRUCTURE_SQL
      end

      it 'removes the sequence OWNER TO statement' do
        subject.run
        expect(subject.dump).not_to include('things_id_seq')
      end
    end

    context 'when moving primary keys into the table definition' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.things (
              id bigint NOT NULL,
              name text
          );

          --
          -- Name: things things_pkey; Type: CONSTRAINT; Schema: waysact; Owner: -
          --

          ALTER TABLE ONLY waysact.things
              ADD CONSTRAINT things_pkey PRIMARY KEY (id);
        STRUCTURE_SQL
      end

      it 'inlines the primary key on the id column' do
        subject.run
        expect(subject.dump).to include('id BIGSERIAL PRIMARY KEY')
      end

      it 'removes the separate ADD CONSTRAINT statement' do
        subject.run
        expect(subject.dump).not_to include('ADD CONSTRAINT things_pkey')
      end
    end

    context 'when moving unique constraints into the table definition' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.things (
              id BIGSERIAL,
              email text
          );

          --
          -- Name: things things_email_key; Type: CONSTRAINT; Schema: waysact; Owner: -
          --

          ALTER TABLE ONLY waysact.things
              ADD CONSTRAINT things_email_key UNIQUE (email);
        STRUCTURE_SQL
      end

      let(:options) { { move_unique_constraints_to_tables: true } }

      it 'inlines the unique constraint' do
        subject.run
        expect(subject.dump).to include('CONSTRAINT things_email_key UNIQUE (email)')
      end

      it 'removes the separate ADD CONSTRAINT statement' do
        subject.run
        expect(subject.dump).not_to include('ALTER TABLE ONLY waysact.things')
      end
    end

    context 'when removing partitioned tables' do
      let(:dump) do
        <<~STRUCTURE_SQL
          --
          -- Name: events; Type: TABLE; Schema: waysact; Owner: waysact
          --

          CREATE TABLE waysact.events (
              id bigint NOT NULL
          )
          PARTITION BY RANGE (id);

          --
          -- Name: events_p2024; Type: TABLE; Schema: waysact; Owner: waysact
          --

          CREATE TABLE waysact.events_p2024 (
              id bigint NOT NULL
          );

          ALTER TABLE ONLY waysact.events ATTACH PARTITION waysact.events_p2024 FOR VALUES FROM (1) TO (100);

          --
          -- Name: idx_events_p2024_id; Type: INDEX; Schema: waysact; Owner: waysact
          --

          CREATE INDEX idx_events_p2024_id ON waysact.events_p2024 USING btree (id);

          ALTER TABLE waysact.events_p2024 OWNER TO waysact;

          --
          -- Name: events_p2024 events_p2024_pkey; Type: CONSTRAINT; Schema: waysact; Owner: waysact
          --

          --
          -- Name: events_p2024_pkey; Type: INDEX ATTACH; Schema: waysact; Owner: waysact
          --

          ALTER INDEX waysact.events_pkey ATTACH PARTITION waysact.events_p2024_pkey;

          --
          -- Name: TABLE events_p2024; Type: COMMENT; Schema: waysact; Owner: waysact
          --

          COMMENT ON TABLE waysact.events_p2024 IS 'A partition for 2024 data';

          --
          -- Name: events_p2024_stats; Type: STATISTICS; Schema: waysact; Owner: waysact
          --

          CREATE STATISTICS waysact.events_p2024_stats ON id FROM waysact.events_p2024;

          ALTER STATISTICS waysact.events_p2024_stats OWNER TO waysact;
        STRUCTURE_SQL
      end

      it 'does not leave orphaned comment suffixes as bare SQL' do
        subject.run
        expect(subject.dump).not_to match(/^; Schema:/)
      end

      it 'removes all references to the partition' do
        subject.run
        expect(subject.dump).not_to include('events_p2024')
      end
    end

    context 'when removing inherited tables' do
      let(:dump) do
        <<~STRUCTURE_SQL
          --
          -- Name: parent; Type: TABLE; Schema: waysact; Owner: waysact
          --

          CREATE TABLE waysact.parent (
              id bigint NOT NULL
          );

          --
          -- Name: child; Type: TABLE; Schema: waysact; Owner: waysact
          --

          CREATE TABLE waysact.child (
              id bigint NOT NULL
          )
          INHERITS (waysact.parent);

          --
          -- Name: idx_child_id; Type: INDEX; Schema: waysact; Owner: waysact
          --

          CREATE INDEX idx_child_id ON waysact.child USING btree (id);
        STRUCTURE_SQL
      end

      it 'does not leave orphaned comment suffixes as bare SQL' do
        subject.run
        expect(subject.dump).not_to match(/^; Schema:/)
      end
    end

    context 'when ordering column definitions with multiline constraints' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              id bigint NOT NULL,
              call_uuid uuid NOT NULL,
              event_type text NOT NULL,
              payload jsonb,
              CONSTRAINT call_events_valid CHECK (
          CASE
              WHEN (event_type = 'initiated'::text) THEN validate_json_schema('{"required": ["CallSid"],
          event_type text NOT NULL,
          next_states text[]}'::jsonb, payload)
              ELSE false
          END)
          );
        STRUCTURE_SQL
      end

      let(:options) { { order_column_definitions: true } }

      it 'keeps the constraint body intact' do
        subject.run
        expect(subject.dump).to include(
          %{validate_json_schema('{"required": ["CallSid"],\nevent_type text NOT NULL,\nnext_states text[]}'::jsonb, payload)}
        )
      end
    end

    context 'when ordering column definitions with WITH clause' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              name text NOT NULL,
              id bigint NOT NULL
          )
          WITH (fillfactor='85');

          CREATE TABLE waysact.other (
              id bigint NOT NULL,
              value text
          );
        STRUCTURE_SQL
      end

      let(:options) { { order_column_definitions: true } }

      it 'does not move columns between tables' do
        subject.run
        expect(subject.dump).to include('call_events')
        expect(subject.dump).to include('name text NOT NULL')
        # name must remain inside call_events, not move to other
        other_block = subject.dump[/CREATE TABLE waysact\.other \(.*?\);/m]
        expect(other_block).not_to include('name')
      end
    end

    context 'when sorting indexes' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              id BIGSERIAL
          );

          CREATE TABLE waysact.other (
              id BIGSERIAL
          );

          CREATE INDEX foo ON waysact.call_events (id);

          CREATE INDEX "bar" ON waysact.call_events (id);
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'works' do
        subject.run
        expect(subject.dump).to eq(<<~STRUCTURE_SQL)
          CREATE TABLE waysact.call_events (
              id BIGSERIAL
          );

          CREATE INDEX foo ON waysact.call_events (id);
          CREATE INDEX "bar" ON waysact.call_events (id);

          CREATE TABLE waysact.other (
              id BIGSERIAL
          );
        STRUCTURE_SQL
      end
    end

    context 'when sorting indexes with WITH clause on table' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              id BIGSERIAL
          )
          WITH (fillfactor='85');

          CREATE INDEX foo ON waysact.call_events (id);
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'places indexes after the table' do
        subject.run
        expect(subject.dump).to include("WITH (fillfactor='85');")
        expect(subject.dump).to include('CREATE INDEX foo ON waysact.call_events (id);')
      end
    end
  end
end
