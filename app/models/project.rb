class Project < ApplicationRecord
  # Multi-tenancy setup - Project belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :user
  has_many :issues, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :performance_events, dependent: :destroy
  has_many :perf_rollups, dependent: :destroy
  has_many :performance_summaries, dependent: :destroy
  has_many :sql_fingerprints, dependent: :destroy
  has_many :releases, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :healthchecks, dependent: :destroy
  has_many :alert_rules, dependent: :destroy
  has_many :alert_notifications, dependent: :destroy
  has_many :deploys, dependent: :destroy
  has_many :notification_preferences, dependent: :destroy
  has_many :error_imports, dependent: :destroy

  validates :name, presence: true
  validates_uniqueness_to_tenant :name, scope: :user_id
  validates :slug, presence: true, uniqueness: true
  validates :environment, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }

  before_validation :generate_slug, if: -> { slug.nil? && name.present? }

  scope :active, -> { where(active: true) }

  def generate_api_token!
    api_tokens.create!(
      name: "Default Token",
      token: SecureRandom.hex(32),
      active: true
    )
  end

  def api_token
    api_tokens.active.first&.token
  end

  def create_default_alert_rules!
    # Create default alert rules for new projects
    alert_rules.create!([
      {
        name: "High Error Frequency",
        rule_type: "error_frequency",
        threshold_value: 10,
        time_window_minutes: 5,
        cooldown_minutes: 30,
        enabled: true
      },
      {
        name: "Slow Response Time",
        rule_type: "performance_regression",
        threshold_value: 2000, # 2 seconds
        time_window_minutes: 1,
        cooldown_minutes: 15,
        enabled: true
      },
      {
        name: "N+1 Query Detection",
        rule_type: "n_plus_one",
        threshold_value: 1, # Alert on any high-severity N+1
        time_window_minutes: 1,
        cooldown_minutes: 60,
        enabled: true
      },
      {
        name: "New Issues",
        rule_type: "new_issue",
        threshold_value: 1,
        time_window_minutes: 1,
        cooldown_minutes: 0, # No cooldown for new issues
        enabled: true
      }
    ])
  end

  # Computed health status used for UI:
  # - If an explicit health_status has been set (via uptime checks), use it.
  # - Otherwise, if we have seen at least one issue or event for this project,
  #   treat it as "healthy" instead of "unknown".
  def computed_health_status
    return health_status if health_status.present?

    if issues.exists? || events.exists?
      "healthy"
    else
      "unknown"
    end
  end

  def update_health_status!(healthcheck_results)
    critical_count = healthcheck_results.count { |r| r[:status] == "critical" }
    warning_count = healthcheck_results.count { |r| r[:status] == "warning" }

    new_status = if critical_count > 0
                   "critical"
    elsif warning_count > 0
                   "warning"
    else
                   "healthy"
    end

    update!(health_status: new_status)
  end

  # ---- Notifications ----
  def slack_configured?
    slack_access_token.present?
  end

  def notifications_enabled?
    settings.dig("notifications", "enabled") != false
  end

  def notify_via_slack?
    return false unless notifications_enabled?
    return false unless slack_configured?

    settings.dig("notifications", "channels", "slack") == true
  end

  def notify_via_email?
    return false unless notifications_enabled?

    settings.dig("notifications", "channels", "email") == true
  end

  def notification_pref_for(alert_type)
    notification_preferences.find_by(alert_type: alert_type)
  end

  # Fizzy sync settings
  def fizzy_endpoint_url
    # Priority: ENV variable > database setting
    env_endpoint = ENV["FIZZY_ENDPOINT_URL_#{slug.upcase}"] || ENV["FIZZY_ENDPOINT_URL"]
    env_endpoint.presence || settings["fizzy_endpoint_url"]
  end

  def fizzy_endpoint_url=(url)
    # Only store in database if not using environment variable
    if url.present? && !url.start_with?("ENV:")
      self.settings = settings.merge("fizzy_endpoint_url" => url&.strip)
    elsif url&.start_with?("ENV:")
      # Store reference to environment variable
      env_var = url.sub("ENV:", "")
      self.settings = settings.merge("fizzy_endpoint_url" => "ENV:#{env_var}")
    else
      # Clear the setting
      new_settings = settings.dup
      new_settings.delete("fizzy_endpoint_url")
      self.settings = new_settings
    end
  end

  def fizzy_endpoint_from_env?
    settings["fizzy_endpoint_url"]&.start_with?("ENV:") ||
    ENV["FIZZY_ENDPOINT_URL_#{slug.upcase}"].present? ||
    ENV["FIZZY_ENDPOINT_URL"].present?
  end

  def fizzy_api_key
    # Priority: ENV variable > database setting
    env_key = ENV["FIZZY_API_KEY_#{slug.upcase}"] || ENV["FIZZY_API_KEY"]
    env_key.presence || settings["fizzy_api_key"]
  end

  def fizzy_api_key=(key)
    if key.present? && !key.start_with?("ENV:")
      self.settings = settings.merge("fizzy_api_key" => key&.strip)
    elsif key&.start_with?("ENV:")
      # Store reference to environment variable
      env_var = key.sub("ENV:", "")
      self.settings = settings.merge("fizzy_api_key" => "ENV:#{env_var}")
    else
      # Clear the setting
      new_settings = settings.dup
      new_settings.delete("fizzy_api_key")
      self.settings = new_settings
    end
  end

  def fizzy_api_key_from_env?
    settings["fizzy_api_key"]&.start_with?("ENV:") ||
    ENV["FIZZY_API_KEY_#{slug.upcase}"].present? ||
    ENV["FIZZY_API_KEY"].present?
  end

  def fizzy_configured?
    fizzy_endpoint_url.present? && fizzy_api_key.present?
  end

  def fizzy_sync_enabled?
    fizzy_configured? && settings["fizzy_sync_enabled"] != false
  end

  def enable_fizzy_sync!
    self.settings = settings.merge("fizzy_sync_enabled" => true)
    save!
  end

  def disable_fizzy_sync!
    self.settings = settings.merge("fizzy_sync_enabled" => false)
    save!
  end

  # Honeybadger import settings
  def honeybadger_api_token
    env_token = ENV["HONEYBADGER_API_TOKEN_#{slug.upcase}"] || ENV["HONEYBADGER_API_TOKEN"]
    env_token.presence || settings["honeybadger_api_token"]
  end

  def honeybadger_api_token=(token)
    if token.present? && !token.start_with?("ENV:")
      self.settings = settings.merge("honeybadger_api_token" => token.strip)
    elsif token&.start_with?("ENV:")
      env_var = token.sub("ENV:", "")
      self.settings = settings.merge("honeybadger_api_token" => "ENV:#{env_var}")
    else
      new_settings = settings.dup
      new_settings.delete("honeybadger_api_token")
      self.settings = new_settings
    end
  end

  def honeybadger_project_id
    settings["honeybadger_project_id"]
  end

  def honeybadger_project_id=(id)
    if id.present?
      self.settings = settings.merge("honeybadger_project_id" => id.to_s.strip)
    else
      new_settings = settings.dup
      new_settings.delete("honeybadger_project_id")
      self.settings = new_settings
    end
  end

  def honeybadger_configured?
    honeybadger_api_token.present? && honeybadger_project_id.present?
  end

  def last_honeybadger_import
    error_imports.by_provider('honeybadger').completed.recent.first
  end

  def last_honeybadger_import_date
    last_honeybadger_import&.last_imported_at
  end

  # Webhook URL for Honeybadger to send errors
  def honeybadger_webhook_url
    base_url = ENV.fetch('RAILS_HOST', 'http://localhost:3000')
    token = honeybadger_webhook_token
    "#{base_url}/webhooks/honeybadger?project_token=#{token}" if token
  end

  def honeybadger_webhook_token
    if settings['honeybadger_webhook_token'].blank?
      self.settings = settings.merge('honeybadger_webhook_token' => SecureRandom.hex(32))
      save if changed?
    end
    settings['honeybadger_webhook_token']
  end

  def honeybadger_webhook_enabled?
    settings['honeybadger_webhook_enabled'] == true
  end

  def enable_honeybadger_webhook!
    self.settings = settings.merge('honeybadger_webhook_enabled' => true)
    save!
  end

  def disable_honeybadger_webhook!
    self.settings = settings.merge('honeybadger_webhook_enabled' => false)
    save!
  end

  def import_error_from_webhook_later(webhook_payload)
    ErrorImportWebhookJob.perform_async(id, webhook_payload)
  end

  def import_error_from_webhook_now(webhook_payload)
    provider = ErrorImport::HoneybadgerProvider.new(self)
    mapped_data = provider.map_webhook_to_internal_format(webhook_payload)

    if mapped_data.nil?
      Rails.logger.warn "Failed to map Honeybadger webhook payload"
      return
    end

    if Event.exists_from_external?(
      project: self,
      provider: 'honeybadger',
      external_id: mapped_data[:external_id]
    )
      Rails.logger.info "Skipping duplicate Honeybadger event: #{mapped_data[:external_id]}"
    else
      event = Event.ingest_error(project: self, payload: mapped_data)

      if mapped_data[:external_source] && mapped_data[:external_id]
        event.update_columns(
          external_source: mapped_data[:external_source],
          external_id: mapped_data[:external_id]
        )
      end

      Rails.logger.info "Imported Honeybadger error via webhook: #{event.id}"
    end
  rescue => e
    Rails.logger.error "Failed to import Honeybadger webhook: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  def self.ransackable_attributes(auth_object = nil)
    ["account_id", "active", "created_at", "description",
    "environment", "health_status", "id", "id_value", "last_event_at",
    "name", "settings", "slug", "tech_stack", "updated_at", "url", "user_id"]
  end

  private

  def generate_slug
    base_slug = name.parameterize
    counter = 1
    potential_slug = base_slug

    while Project.exists?(slug: potential_slug)
      potential_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = potential_slug
  end
end
