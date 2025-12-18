class ErrorImport < ApplicationRecord
  acts_as_tenant(:account)
  belongs_to :project

  validates :provider, presence: true, inclusion: { in: %w[honeybadger sentry] }
  validates :status, presence: true, inclusion: {
    in: %w[pending running completed failed cancelled]
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :by_provider, ->(provider) { where(provider: provider) }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }

  def import_later
    ErrorImportJob.perform_async(id)
  end

  def running?
    status == 'running'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def mark_running!
    update!(status: 'running', started_at: Time.current)
  end

  def mark_completed!
    update!(
      status: 'completed',
      completed_at: Time.current,
      last_imported_at: Time.current
    )
  end

  def mark_failed!(error_message)
    update!(
      status: 'failed',
      completed_at: Time.current,
      error_message: error_message
    )
  end

  def update_progress(imported: 0, skipped: 0, failed: 0, current_page: nil)
    self.imported_count += imported
    self.skipped_count += skipped
    self.failed_count += failed
    self.progress = (progress || {}).merge(
      current_page: current_page,
      updated_at: Time.current
    )
    save!
  end

  def success_rate
    if total_count.zero?
      0
    else
      (imported_count.to_f / total_count * 100).round(2)
    end
  end

  def import_now
    mark_running!

    provider_name = provider
    provider_class = "ErrorImport::#{provider_name.camelize}Provider".constantize
    provider_instance = provider_class.new(project, settings || {})

    start_date = determine_start_date
    end_date = settings&.dig('end_date')&.then { |d| Time.parse(d) }

    Rails.logger.info "Starting #{provider_name} import for project #{project.slug} " \
                      "(#{start_date} to #{end_date || 'now'})"

    imported = 0
    skipped = 0
    failed = 0
    batch_size = 50
    batch = []

    begin
      provider_instance.fetch_errors(start_date: start_date, end_date: end_date).each do |external_error|
        result = process_external_error(external_error, provider_instance, batch, batch_size)
        if result == :imported
          imported += 1
        elsif result == :skipped
          skipped += 1
        elsif result == :failed
          failed += 1
        end

        if batch.size >= batch_size
          process_batch(batch, provider_name)
          imported += batch.size
          batch.clear
          update_progress(imported: batch.size, skipped: skipped, failed: failed)
          skipped = 0
          failed = 0
        end
      end

      if batch.any?
        process_batch(batch, provider_name)
        imported += batch.size
      end

      update_progress(imported: imported, skipped: skipped, failed: failed)
      update!(total_count: imported + skipped + failed)
      mark_completed!

      Rails.logger.info "Completed #{provider_name} import: #{imported} imported, " \
                        "#{skipped} skipped, #{failed} failed"

    rescue ErrorImport::RateLimitError => e
      retry_after = e.retry_after || 60
      ErrorImportJob.perform_in(retry_after.seconds, id)
      update!(status: 'pending', error_message: "Rate limited. Retrying in #{retry_after}s")

    rescue => e
      Rails.logger.error "Import failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      mark_failed!(e.message)
      raise
    end
  end

  private

  def determine_start_date
    if settings&.dig('incremental') == true
      last_import = project.last_honeybadger_import_date
      return last_import if last_import
    end

    if settings&.dig('start_date')
      return Time.parse(settings['start_date'])
    end

    30.days.ago
  end

  def process_external_error(external_error, provider_instance, batch, batch_size)
    if Event.exists_from_external?(
      project: project,
      provider: provider,
      external_id: external_error[:external_id]
    )
      :skipped
    else
      payload = provider_instance.map_to_internal_format(external_error)
      batch << payload
      :imported
    end
  rescue => e
    Rails.logger.error "Failed to import error #{external_error[:external_id]}: #{e.message}"
    :failed
  end

  def process_batch(batch, provider_name)
    batch.each do |payload|
      event = Event.ingest_error(project: project, payload: payload)

      if payload[:external_source] && payload[:external_id]
        event.update_columns(
          external_source: payload[:external_source],
          external_id: payload[:external_id]
        )
      end
    end
  end
end

