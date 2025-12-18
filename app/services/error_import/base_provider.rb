module ErrorImport
  class BaseProvider
    attr_reader :project, :options

    def initialize(project, options = {})
      @project = project
      @options = options
      @rate_limit_remaining = nil
      @rate_limit_reset_at = nil
    end

    # Abstract methods - must be implemented by subclasses
    def fetch_errors(start_date: nil, end_date: nil)
      raise NotImplementedError, "Subclass must implement fetch_errors"
    end

    def map_to_internal_format(external_error)
      raise NotImplementedError, "Subclass must implement map_to_internal_format"
    end

    def test_connection
      raise NotImplementedError, "Subclass must implement test_connection"
    end

    # Optional: Map webhook payload to internal format
    def map_webhook_to_internal_format(webhook_payload)
      # Default implementation delegates to map_to_internal_format
      # Subclasses can override for webhook-specific handling
      map_to_internal_format(webhook_payload)
    end

    protected

    def http_client
      @http_client ||= begin
        require 'net/http'
        require 'uri'
        require 'json'
        Net::HTTP
      end
    end

    def make_request(method, url, headers: {}, body: nil)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = 30
      http.open_timeout = 10

      request = case method.to_s.upcase
      when 'GET'
        Net::HTTP::Get.new(uri.request_uri)
      when 'POST'
        Net::HTTP::Post.new(uri.request_uri)
      else
        raise "Unsupported HTTP method: #{method}"
      end

      headers.each { |k, v| request[k] = v }
      request.body = body.to_json if body

      response = http.request(request)

      # Track rate limits
      @rate_limit_remaining = response['X-RateLimit-Remaining']&.to_i
      @rate_limit_reset_at = Time.at(response['X-RateLimit-Reset'].to_i) if response['X-RateLimit-Reset']

      handle_rate_limit(response)

      parse_response(response)
    rescue Net::TimeoutError => e
      raise ErrorImport::TimeoutError, "Request timeout: #{e.message}"
    rescue Errno::ECONNREFUSED => e
      raise ErrorImport::ConnectionError, "Connection refused: #{e.message}"
    end

    def handle_rate_limit(response)
      if response.code.to_i == 429
        retry_after = response['Retry-After']&.to_i || 60
        raise ErrorImport::RateLimitError.new(
          "Rate limit exceeded. Retry after #{retry_after} seconds",
          retry_after: retry_after
        )
      end
    end

    def parse_response(response)
      case response.code.to_i
      when 200..299
        JSON.parse(response.body) if response.body.present?
      when 401
        raise ErrorImport::AuthenticationError, "Authentication failed"
      when 403
        raise ErrorImport::AuthorizationError, "Access forbidden"
      when 404
        raise ErrorImport::NotFoundError, "Resource not found"
      when 429
        handle_rate_limit(response)
      when 500..599
        raise ErrorImport::ServerError, "Server error: #{response.code}"
      else
        raise ErrorImport::ApiError, "Unexpected response: #{response.code}"
      end
    end

    def wait_for_rate_limit
      if @rate_limit_remaining && @rate_limit_remaining < 10 && @rate_limit_reset_at
        wait_time = [@rate_limit_reset_at - Time.current, 0].max.ceil
        if wait_time > 0
          Rails.logger.warn "Rate limit low (#{@rate_limit_remaining} remaining). Waiting #{wait_time}s"
          sleep(wait_time)
        end
      end
    end
  end
end

# Custom exceptions
module ErrorImport
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class AuthorizationError < Error; end
  class RateLimitError < Error
    attr_reader :retry_after
    def initialize(message, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end
  class NotFoundError < Error; end
  class ServerError < Error; end
  class ApiError < Error; end
  class TimeoutError < Error; end
  class ConnectionError < Error; end
end

