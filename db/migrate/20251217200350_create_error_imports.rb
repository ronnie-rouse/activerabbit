class CreateErrorImports < ActiveRecord::Migration[8.0]
  def change
    create_table :error_imports do |t|
      t.references :project, null: false, foreign_key: true
      t.bigint :account_id, null: false
      t.string :provider, null: false  # 'honeybadger', 'sentry', etc.
      t.string :status, null: false, default: 'pending'  # pending, running, completed, failed, cancelled
      t.integer :total_count, default: 0  # Total errors found in source
      t.integer :imported_count, default: 0  # Successfully imported
      t.integer :skipped_count, default: 0  # Duplicates skipped
      t.integer :failed_count, default: 0  # Failed to import
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :last_imported_at  # For incremental imports
      t.json :settings, default: {}  # Provider-specific settings (date range, filters, etc.)
      t.json :progress, default: {}  # Current progress (current_page, current_fault_id, etc.)
      t.text :error_message  # Error details if failed
      t.text :warnings  # Warnings encountered during import

      t.timestamps
    end

    add_index :error_imports, [:project_id, :provider, :status]
    add_index :error_imports, [:account_id, :created_at]
    add_index :error_imports, :provider
    add_foreign_key :error_imports, :accounts
  end
end

