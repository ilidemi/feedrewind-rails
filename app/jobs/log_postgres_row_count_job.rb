class LogPostgresRowCountJob < ApplicationJob
  queue_as :default

  def perform
    # https://stackoverflow.com/a/28668340
    query = <<-SQL
      SELECT
        SUM(pgClass.reltuples) AS totalRowCount
      FROM
        pg_class pgClass
      LEFT JOIN
        pg_namespace pgNamespace ON (pgNamespace.oid = pgClass.relnamespace)
      WHERE
        pgNamespace.nspname NOT IN ('pg_catalog', 'information_schema') AND
        pgClass.relkind='r'
    SQL
    query_result = ActiveRecord::Base.connection.exec_query(query, "SQL", [])

    row_count = query_result.rows.first[0]
    if row_count > 5000000
      Rails.logger.warn("DB total row count: #{row_count} (over 50%)")
    else
      Rails.logger.info("DB total row count: #{row_count}")
    end

    LogPostgresRowCountJob.set(wait: 10.minutes).perform_later
  end
end


