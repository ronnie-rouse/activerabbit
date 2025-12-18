class ProjectSettingsController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project

  def show
    # Show project settings including Slack configuration
    @api_tokens = @project.api_tokens.active
    @preferences_by_type =
      NotificationPreference::ALERT_TYPES.index_with do |type|
        @project.notification_preferences.find_or_create_by!(
          alert_type: type
        ) do |pref|
          pref.enabled = true
          pref.frequency = "immediate"
        end
      end
  end

  def update
    ok = true

    ok &&= update_notification_settings if params[:project]&.dig(:notifications)
    ok &&= update_github_settings if params[:project]&.except(:notifications).present?
    ok &&= update_import_settings if params[:project]&.key?(:honeybadger_api_token) || params[:project]&.key?(:honeybadger_project_id) || params[:project]&.key?(:honeybadger_webhook_enabled)
    ok &&= update_notification_preferences if params[:preferences].present?

    if ok
      redirect_to project_settings_path(@project),
                  notice: "Settings updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def test_notification
    unless @project.notify_via_slack?
      redirect_to project_settings_path(@project),
                  alert: "Slack notifications are disabled or Slack is not configured."
      return
    end

    begin
      slack_service = SlackNotificationService.new(@project)
      slack_service.send_custom_alert(
        "🧪 *Test Notification*",
        "This is a test message from ActiveRabbit to verify your Slack integration is working correctly!",
        color: "good"
      )

      redirect_to project_settings_path(@project), notice: "Test notification sent successfully! Check your Slack channel."
    rescue StandardError => e
      Rails.logger.error "Slack test failed: #{e.message}"
      redirect_to project_settings_path(@project), alert: "Failed to send test notification: #{e.message}"
    end
  end


  private

  def set_project
    # Use @current_project set by ApplicationController for slug-based routes
    # or find by project_id for regular routes
    if @current_project
      @project = @current_project
    elsif params[:project_id].present?
      @project = current_user.projects.find(params[:project_id])
    else
      redirect_to dashboard_path, alert: "Project not found."
    end
  end

  def update_notification_settings
    return true unless params[:project]

    notif_params = params
      .require(:project)
      .fetch(:notifications, {})
      .permit(:enabled, channels: [:slack, :email])

    settings = @project.settings || {}
    settings["notifications"] ||= {}

    settings["notifications"]["enabled"] =
      notif_params[:enabled] == "1"

    settings["notifications"]["channels"] = {
      "slack" => notif_params.dig(:channels, :slack) == "1",
      "email" => notif_params.dig(:channels, :email) == "1"
    }

    @project.settings = settings
    @project.save
  end

  def update_notification_preferences
    prefs = params[:preferences]
    return true if prefs.blank?

    prefs.each do |id, attrs|
      pref = @project.notification_preferences.find(id)
      pref.update!(frequency: attrs[:frequency])
    end

    true
  end

  def update_import_settings
    import_params = params.fetch(:project, {}).permit(
      :honeybadger_api_token,
      :honeybadger_project_id,
      :honeybadger_webhook_enabled
    )

    if import_params.present?
      @project.honeybadger_api_token = import_params[:honeybadger_api_token] if import_params.key?(:honeybadger_api_token)
      @project.honeybadger_project_id = import_params[:honeybadger_project_id] if import_params.key?(:honeybadger_project_id)

      if import_params.key?(:honeybadger_webhook_enabled)
        if import_params[:honeybadger_webhook_enabled] == "1"
          @project.enable_honeybadger_webhook!
        else
          @project.disable_honeybadger_webhook!
        end
      end

      @project.save
    end

    true
  end
end
