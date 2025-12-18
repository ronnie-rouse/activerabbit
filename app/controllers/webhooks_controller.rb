class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  skip_before_action :set_current_tenant
  skip_before_action :set_current_project_from_slug
  skip_before_action :check_onboarding_needed

  def stripe
    payload = request.body.read
    sig = request.env["HTTP_STRIPE_SIGNATURE"]
    event = Stripe::Webhook.construct_event(payload, sig, ENV.fetch("STRIPE_SIGNING_SECRET"))

    # Idempotency tracking
    already = WebhookEvent.find_by(provider: "stripe", event_id: event.id)
    if already&.processed_at
      head :ok
    else
      ActiveRecord::Base.transaction do
        WebhookEvent.create!(provider: "stripe", event_id: event.id)
        StripeEventHandler.new(event: event).call
        WebhookEvent.where(provider: "stripe", event_id: event.id).update_all(processed_at: Time.current)
      end
      head :ok
    end
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end

  def honeybadger
    payload = request.body.read
    project_token = params[:project_token]

    project = Project.find_by("settings->>'honeybadger_webhook_token' = ?", project_token)

    if project
      webhook_data = parse_webhook_payload(payload)

      if webhook_data
        process_honeybadger_webhook(project, webhook_data)
        head :ok
      else
        head :bad_request
      end
    else
      Rails.logger.warn "Honeybadger webhook: Invalid project token"
      head :unauthorized
    end
  rescue => e
    Rails.logger.error "Honeybadger webhook error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    head :internal_server_error
  end

  private

  def parse_webhook_payload(payload)
    JSON.parse(payload)
  rescue JSON::ParserError
    nil
  end

  def process_honeybadger_webhook(project, webhook_data)
    event_id = webhook_data.dig('notice', 'id') || webhook_data.dig('fault', 'id')
    event_type = webhook_data['event'] || 'error_occurred'

    webhook_event = WebhookEvent.find_or_initialize_by(
      provider: 'honeybadger',
      event_id: event_id.to_s
    )

    if webhook_event.processed_at
      # Already processed - idempotency check
    else
      ActsAsTenant.with_tenant(project.account) do
        ActiveRecord::Base.transaction do
          webhook_event.save! unless webhook_event.persisted?

          if event_type == 'error_occurred' || webhook_data['notice']
            project.import_error_from_webhook_later(webhook_data)
          end

          webhook_event.update!(processed_at: Time.current)
        end
      end
    end
  end
end
