class FizzyBatchSyncJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 3

  def perform(project_id)
    # Find project without tenant scoping, then set the tenant
    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    unless project.fizzy_configured?
      Rails.logger.warn "Fizzy not configured for project #{project.id}, skipping batch sync"
      return
    end

    unless project.fizzy_sync_enabled?
      Rails.logger.info "Fizzy sync disabled for project #{project.id}, skipping batch sync"
      return { synced: 0, failed: 0, total: 0, error: "Sync disabled" }
    end

    issue_count = project.issues.count
    Rails.logger.info "Fizzy batch sync starting for project #{project.slug} (#{project.id}): #{issue_count} issues found"

    if issue_count == 0
      Rails.logger.warn "No issues found for project #{project.slug}, nothing to sync"
      return { synced: 0, failed: 0, total: 0, error: "No issues found" }
    end

    Rails.logger.info "Fizzy endpoint: #{project.fizzy_endpoint_url}"
    Rails.logger.info "Fizzy API key present: #{project.fizzy_api_key.present?}"

    fizzy_service = FizzySyncService.new(project)
    result = fizzy_service.sync_batch(project.issues)

    Rails.logger.info "Fizzy batch sync completed for project #{project.slug}: #{result[:synced]} synced, #{result[:failed]} failed out of #{result[:total]} total"

    if result[:error].present?
      Rails.logger.error "Fizzy batch sync error: #{result[:error]}"
    end

    result
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Project not found for Fizzy batch sync: #{project_id}"
    raise e
  rescue StandardError => e
    Rails.logger.error "Error in Fizzy batch sync: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end
