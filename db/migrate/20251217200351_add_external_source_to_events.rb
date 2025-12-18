class AddExternalSourceToEvents < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:events, :external_source)
      add_column :events, :external_source, :string  # 'honeybadger', 'sentry', etc.
    end
    unless column_exists?(:events, :external_id)
      add_column :events, :external_id, :string  # Provider's unique ID for this event
    end

    unless index_exists?(:events, [:project_id, :external_source, :external_id], name: 'index_events_on_external_source')
      add_index :events, [:project_id, :external_source, :external_id], 
        unique: true, 
        name: 'index_events_on_external_source'
    end
    unless index_exists?(:events, :external_source)
      add_index :events, :external_source
    end
  end
end

