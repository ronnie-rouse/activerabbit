module ErrorImport
  class HoneybadgerProvider < BaseProvider
    BASE_URL = 'https://app.honeybadger.io/v2'

    def initialize(project, options = {})
      super
      @api_token = project.honeybadger_api_token
      @project_id = project.honeybadger_project_id
      raise ArgumentError, "Honeybadger not configured" unless configured?
    end

    def configured?
      @api_token.present? && @project_id.present?
    end

    def test_connection
      begin
        response = make_request('GET', "#{BASE_URL}/projects/#{@project_id}",
          headers: auth_headers)
        { success: true, message: "Connection successful" }
      rescue => e
        { success: false, message: e.message }
      end
    end

    # Fetch all faults (errors) with pagination
    def fetch_errors(start_date: nil, end_date: nil)
      Enumerator.new do |yielder|
        page = 1
        loop do
          faults_response = fetch_faults_page(page: page, start_date: start_date, end_date: end_date)
          faults = faults_response['results'] || []
          break if faults.empty?

          faults.each do |fault|
            notices = fetch_notices(fault['id'])
            notices.each do |notice|
              yielder << {
                fault: fault,
                notice: notice,
                external_id: notice['id'].to_s,
                occurred_at: parse_time(notice['created_at'])
              }
            end
          end

          # Check if there's a next page
          if faults_response['links']&.dig('next').present?
            page += 1
            wait_for_rate_limit
          else
            break
          end
        end
      end
    end

    def map_to_internal_format(data)
      fault = data[:fault]
      notice = data[:notice]

      # Extract backtrace
      backtrace = extract_backtrace(notice)
      top_frame = Event.extract_top_frame(backtrace)
      controller_action = extract_controller_action(notice, backtrace)

      # Build context with provider metadata
      context = {
        'import_source' => 'honeybadger',
        'honeybadger_fault_id' => fault['id'],
        'honeybadger_notice_id' => notice['id'],
        'honeybadger_url' => fault['url'],
        'request' => notice['request'] || {},
        'server' => notice['server'] || {},
        'environment' => notice['server']&.dig('environment_name')
      }

      # Merge any existing context from notice
      if notice['request']&.dig('context')
        context['request'].merge!(notice['request']['context'])
      end

      {
        exception_class: fault['klass'] || 'UnknownError',
        exception_type: fault['klass'], # Alias for compatibility
        message: fault['message'] || notice['message'] || 'No message',
        backtrace: backtrace,
        controller_action: controller_action,
        request_path: notice.dig('request', 'url'),
        request_method: notice.dig('request', 'method'),
        occurred_at: parse_time(notice['created_at']),
        environment: notice.dig('server', 'environment_name') || 'production',
        release_version: notice.dig('server', 'revision'),
        server_name: notice.dig('server', 'hostname'),
        request_id: notice.dig('request', 'id'),
        context: context,
        # External tracking
        external_source: 'honeybadger',
        external_id: notice['id'].to_s
      }
    end

    def map_webhook_to_internal_format(webhook_payload)
      fault = webhook_payload['fault'] || webhook_payload[:fault]
      notice = webhook_payload['notice'] || webhook_payload[:notice]

      if notice.nil?
        Rails.logger.warn "Honeybadger webhook missing notice data"
        return nil
      end

      # Use existing mapping logic
      map_to_internal_format({
        fault: fault,
        notice: notice,
        external_id: notice['id'] || notice[:id],
        occurred_at: parse_time(notice['created_at'] || notice[:created_at])
      })
    end

    private

    def auth_headers
      {
        'Authorization' => "Basic #{Base64.strict_encode64("#{@api_token}:")}",
        'Accept' => 'application/json',
        'Content-Type' => 'application/json'
      }
    end

    def fetch_faults_page(page: 1, start_date: nil, end_date: nil)
      url = "#{BASE_URL}/projects/#{@project_id}/faults"
      params = { page: page }
      params[:start_date] = start_date.iso8601 if start_date
      params[:end_date] = end_date.iso8601 if end_date
      url += "?#{URI.encode_www_form(params)}" if params.any?

      make_request('GET', url, headers: auth_headers)
    end

    def fetch_notices(fault_id, limit: 100)
      url = "#{BASE_URL}/projects/#{@project_id}/faults/#{fault_id}/notices"
      url += "?limit=#{limit}"

      response = make_request('GET', url, headers: auth_headers)
      response['results'] || []
    end

    def extract_backtrace(notice)
      return [] unless notice['backtrace']

      notice['backtrace'].map do |frame|
        "#{frame['file']}:#{frame['number']} in `#{frame['method']}'"
      end
    end

    def extract_controller_action(notice, backtrace)
      # Try to extract from backtrace first
      controller_action = Event.extract_controller_from_backtrace(backtrace)
      if controller_action != 'BackgroundJob'
        return controller_action
      end

      # Try to extract from request context
      if notice.dig('request', 'context', 'controller')
        controller = notice.dig('request', 'context', 'controller')
        action = notice.dig('request', 'context', 'action')
        if controller && action
          return "#{controller}##{action}"
        end
      end

      # Fallback
      'UnknownController#unknown'
    end

    def parse_time(time_string)
      if time_string.blank?
        Time.current
      else
        Time.parse(time_string)
      end
    rescue
      Time.current
    end
  end
end

