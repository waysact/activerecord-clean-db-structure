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
  end
end
