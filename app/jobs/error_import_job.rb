class ErrorImportJob
  include Sidekiq::Job

  sidekiq_options queue: :imports, retry: 3, backtrace: true

  def perform(error_import_id)
    error_import = ActsAsTenant.without_tenant { ErrorImport.find(error_import_id) }
    ActsAsTenant.current_tenant = error_import.account

    error_import.import_now
  end
end

