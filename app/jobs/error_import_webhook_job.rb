class ErrorImportWebhookJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 3, backtrace: true

  def perform(project_id, webhook_payload)
    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    project.import_error_from_webhook_now(webhook_payload)
  end
end

