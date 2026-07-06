class AddUsersLoginPatternIndex < ActiveRecord::Migration[5.2]
  def up
    # Allow LIKE 'prefix%' queries on users.login to use the btree index.
    # PostgreSQL's default btree index uses locale collation and cannot serve
    # LIKE pattern queries. text_pattern_ops uses byte-order comparison which
    # supports prefix LIKE and is safe for ASCII login values.
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS index_users_on_login_text_pattern
      ON users USING btree (login text_pattern_ops);
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_users_on_login_text_pattern;"
  end
end
