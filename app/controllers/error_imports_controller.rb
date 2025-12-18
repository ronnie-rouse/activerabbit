class ErrorImportsController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_error_import, only: [:show, :destroy]

  def index
    @error_imports = @project.error_imports.recent.page(params[:page]).per(20)
    @providers = %w[honeybadger sentry]
  end

  def show
    @imported_issues = @error_import.project.issues
      .joins(:events)
      .where(events: { external_source: @error_import.provider })
      .where("events.created_at >= ?", @error_import.started_at)
      .distinct
      .limit(50)
  end

  def create
    provider = params[:provider]
    options = {
      incremental: params[:incremental] == "true",
      start_date: params[:start_date],
      end_date: params[:end_date]
    }

    if @project.send("#{provider}_configured?")
      error_import = @project.error_imports.create!(
        provider: provider,
        status: "pending",
        settings: options
      )

      error_import.import_later

      redirect_to project_error_import_path(@project, error_import),
        notice: "Import started. This may take a few minutes."
    else
      redirect_to project_error_imports_path(@project),
        alert: "#{provider.camelize} is not configured. Please configure it in project settings."
    end
  end

  def destroy
    if @error_import.running?
      redirect_to project_error_imports_path(@project),
        alert: "Cannot delete a running import. Please wait for it to complete."
    else
      @error_import.destroy
      redirect_to project_error_imports_path(@project),
        notice: "Import record deleted."
    end
  end

  def test_connection
    provider = params[:provider]

    if @project.send("#{provider}_configured?")
      provider_class = "ErrorImport::#{provider.camelize}Provider".constantize
      provider_instance = provider_class.new(@project)
      result = provider_instance.test_connection

      render json: result
    else
      render json: { success: false, message: "Provider not configured" }, status: :unprocessable_entity
    end
  rescue => e
    render json: { success: false, message: e.message }, status: :internal_server_error
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def set_error_import
    @error_import = @project.error_imports.find(params[:id])
  end
end
