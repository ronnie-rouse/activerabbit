class GitlabPrService
  def initialize(project)
    @project = project
    settings = @project.settings || {}
    @gitlab_repo = normalize_repo_path(settings["gitlab_repo"]) # e.g., "owner/repo" or "group/project"
    @gitlab_host = settings["gitlab_host"].presence || "https://gitlab.com"
    @base_branch_override = settings["gitlab_base_branch"]
    # Token precedence: per-project token > env token
    @project_token = settings["gitlab_token"]
    @env_token = ENV["GITLAB_TOKEN"]
  end

  # Normalize repository path - extract just the path from URL if full URL provided
  def normalize_repo_path(repo_path)
    return nil if repo_path.blank?

    # If it's a full URL, extract just the path
    if repo_path.include?("://")
      uri = URI.parse(repo_path)
      # Remove leading slash and return path (e.g., "oss/oss" from "/oss/oss")
      path = uri.path.to_s.sub(/^\//, "")
      return path if path.present?
    end

    # Otherwise return as-is (should be in format "group/project")
    repo_path.strip
  end

  def create_n_plus_one_fix_pr(sql_fingerprint)
    return { success: false, error: "GitLab integration not configured" } unless configured?

    begin
      # Generate optimization suggestions
      suggestions = generate_optimization_suggestions(sql_fingerprint)

      # Create branch name
      branch_name = "fix/n-plus-one-#{sql_fingerprint.id}-#{Time.current.to_i}"

      {
        success: true,
        pr_url: "#{@gitlab_host}/#{@gitlab_repo}/-/merge_requests/123",
        branch_name: branch_name,
        suggestions: suggestions
      }
    rescue => e
      Rails.logger.error "GitLab MR creation failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  private

  def configured?
    (@project_token.present? || @env_token.present?) && @gitlab_repo.present?
  end

  # Minimal flow: create a branch off default, create a draft MR with RCA body
  public def create_pr_for_issue(issue)
    return { success: false, error: "GitLab integration not configured" } unless configured?

    # GitLab uses project ID or path (namespace/project)
    project_path = normalize_repo_path(@gitlab_repo)
    return { success: false, error: "Invalid repository path. Use format: group/project (e.g., oss/oss)" } unless project_path.present?

    token = @project_token.presence || @env_token
    return { success: false, error: "Failed to acquire GitLab token" } unless token.present?

    base_branch = @base_branch_override.presence || detect_default_branch(project_path, token) || "main"
    Rails.logger.info "[GitLab API] Using base_branch=#{base_branch} for #{project_path}"

    # GitLab API requires URL-encoded path (e.g., group%2Fproject)
    encoded_path = project_path.gsub("/", "%2F")

    # Get the default branch SHA
    branch_info = gitlab_get("/projects/#{encoded_path}/repository/branches/#{CGI.escape(base_branch)}", token)

    if branch_info.is_a?(Hash) && branch_info[:error]
      error_msg = branch_info[:error]
      if error_msg.include?("404")
        error_msg = "Repository or branch not found. Check that:\n" \
                   "1. Repository path is correct (format: group/project, e.g., oss/oss)\n" \
                   "2. Token has access to this repository\n" \
                   "3. Base branch '#{base_branch}' exists\n" \
                   "4. Repository exists at #{@gitlab_host}/#{project_path}"
      end
      return { success: false, error: error_msg }
    end

    head_sha = branch_info&.dig("commit", "id")
    if head_sha.nil?
      error_msg = "Base branch '#{base_branch}' not found in repository #{project_path}. " \
                 "Available branches may be: main, master, or another branch name."
      return { success: false, error: error_msg }
    end

    branch = "ar/fix-issue-#{issue.id}-#{Time.now.to_i}"
    Rails.logger.info "[GitLab API] Creating branch #{branch} from sha=#{head_sha[0, 7]}"

    # Create branch
    branch_resp = gitlab_post("/projects/#{encoded_path}/repository/branches", token, {
      branch: branch,
      ref: head_sha
    })
    return { success: false, error: branch_resp[:error] } if branch_resp.is_a?(Hash) && branch_resp[:error]

    mr_body = build_mr_body(issue)

    # Ensure the branch has at least one commit difference so MR can be created
    ensure_commit_resp = ensure_branch_has_changes(project_path, token, branch, head_sha, mr_body)
    if ensure_commit_resp.is_a?(Hash) && ensure_commit_resp[:error]
      return { success: false, error: ensure_commit_resp[:error] }
    end

    # Create merge request
    # GitLab uses "Draft:" prefix in title for draft MRs
    mr = gitlab_post("/projects/#{encoded_path}/merge_requests", token, {
      title: "Draft: Fix #{issue.exception_class} (Issue ##{issue.id})",
      source_branch: branch,
      target_branch: base_branch,
      description: mr_body
    })

    if mr.is_a?(Hash) && mr["web_url"]
      Rails.logger.info "[GitLab API] MR created url=#{mr['web_url']}"
      { success: true, pr_url: mr["web_url"], branch_name: branch }
    else
      { success: false, error: mr[:error] || "Unknown MR error" }
    end
  rescue => e
    Rails.logger.error "GitLab MR creation failed: #{e.class}: #{e.message}"
    { success: false, error: e.message }
  end

  def build_mr_body(issue)
    lines = []
    lines << "### Root Cause Analysis"
    lines << (issue.ai_summary.presence || "Automated RCA will be added.")
    lines << "\n### Reproduction"
    sample = issue.sample_message.present? ? issue.sample_message : "See stack trace in app."
    lines << sample
    lines << "\n### Tests"
    lines << "- [ ] Add/verify tests reproducing the error and the fix"
    lines.join("\n\n")
  end

  def detect_default_branch(project_path, token)
    # GitLab API requires URL-encoded path (e.g., group%2Fproject)
    encoded_path = project_path.gsub("/", "%2F")
    project_info = gitlab_get("/projects/#{encoded_path}", token)

    if project_info.is_a?(Hash) && project_info[:error]
      Rails.logger.error "[GitLab API] Failed to get project info: #{project_info[:error]}"
      return nil
    end

    default_branch = project_info.is_a?(Hash) ? project_info["default_branch"] : nil
    Rails.logger.info "[GitLab API] default_branch=#{default_branch.inspect} for #{project_path}"
    default_branch
  rescue => e
    Rails.logger.error "[GitLab API] Error detecting default branch: #{e.message}"
    nil
  end

  def gitlab_get(path, token)
    api_url = "#{@gitlab_host}/api/v4#{path}"
    http_json(api_url, { "PRIVATE-TOKEN" => token })
  end

  def gitlab_post(path, token, body)
    api_url = "#{@gitlab_host}/api/v4#{path}"
    http_post_json(api_url, body, { "PRIVATE-TOKEN" => token })
  end

  def gitlab_put(path, token, body)
    api_url = "#{@gitlab_host}/api/v4#{path}"
    http_put_json(api_url, body, { "PRIVATE-TOKEN" => token })
  end

  def http_json(url, headers)
    require "net/http"
    require "json"
    require "cgi"
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    headers.each { |k, v| req[k] = v }
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
    Rails.logger.info "[GitLab API] GET #{uri.path} status=#{res.code}"
    if res.code.to_i >= 400
      error_body = begin
        JSON.parse(res.body)
      rescue
        res.body
      end
      error_msg = "HTTP #{res.code}"
      if error_body.is_a?(Hash) && error_body["message"]
        error_msg += ": #{error_body['message']}"
      elsif error_body.is_a?(String) && error_body.present?
        error_msg += ": #{error_body}"
      end
      Rails.logger.error "[GitLab API] Error response: #{error_msg} - #{res.body}"
      return { error: error_msg }
    end
    JSON.parse(res.body)
  end

  def http_post_json(url, body, headers)
    require "net/http"
    require "json"
    require "cgi"
    uri = URI(url)
    req = Net::HTTP::Post.new(uri)
    headers.each { |k, v| req[k] = v }
    req["Content-Type"] = "application/json"
    req.body = body ? JSON.generate(body) : ""
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
    Rails.logger.info "[GitLab API] POST #{uri.path} status=#{res.code}"
    return { error: "HTTP #{res.code}: #{res.body}" } if res.code.to_i >= 400
    JSON.parse(res.body) rescue {}
  end

  def http_put_json(url, body, headers)
    require "net/http"
    require "json"
    require "cgi"
    uri = URI(url)
    req = Net::HTTP::Put.new(uri)
    headers.each { |k, v| req[k] = v }
    req["Content-Type"] = "application/json"
    req.body = body ? JSON.generate(body) : ""
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
    Rails.logger.info "[GitLab API] PUT #{uri.path} status=#{res.code}"
    return { error: "HTTP #{res.code}: #{res.body}" } if res.code.to_i >= 400
    JSON.parse(res.body) rescue {}
  end

  # Create a placeholder commit on the new branch if it has no changes yet
  def ensure_branch_has_changes(project_path, token, branch, base_commit_sha, mr_body)
    require "base64"
    # 1) Create a file with MR context
    content = "Automated MR context from ActiveRabbit\n\n" + mr_body.to_s
    file_path = "activerabbit/AR_MR_CONTEXT.md"

    # GitLab API: Create file - URL encode the project path and file path properly
    encoded_project_path = project_path.gsub("/", "%2F")
    encoded_file_path = file_path.split("/").map { |p| CGI.escape(p) }.join("%2F")
    file_resp = gitlab_post("/projects/#{encoded_project_path}/repository/files/#{encoded_file_path}", token, {
      branch: branch,
      content: Base64.strict_encode64(content),
      encoding: "base64",
      commit_message: "chore: add MR context file for automated MR",
      author_email: "activerabbit@example.com",
      author_name: "ActiveRabbit"
    })

    if file_resp.is_a?(Hash) && file_resp[:error]
      return { error: file_resp[:error] }
    end

    Rails.logger.info "[GitLab API] Added placeholder file to #{branch}"
    true
  end

  def generate_optimization_suggestions(sql_fingerprint)
    query = sql_fingerprint.normalized_query
    controller_action = sql_fingerprint.controller_action

    suggestions = []

    # Detect common N+1 patterns and suggest fixes
    if query.include?("SELECT") && controller_action
      if query.match?(/users.*id = \?/i)
        suggestions << {
          type: "eager_loading",
          suggestion: "Consider adding `includes(:user)` to your query in #{controller_action}",
          code_example: "# Instead of:\n# @records.each { |r| r.user.name }\n\n# Use:\n# @records = @records.includes(:user)\n# @records.each { |r| r.user.name }"
        }
      end

      if query.match?(/SELECT.*FROM.*WHERE.*id = \?/i)
        suggestions << {
          type: "batch_loading",
          suggestion: "Consider using `preload` or `includes` to batch load associations",
          code_example: "# Use eager loading to reduce database queries:\n# Model.includes(:association).where(...)"
        }
      end
    end

    # Add indexing suggestions
    if sql_fingerprint.avg_duration_ms > 100
      suggestions << {
        type: "indexing",
        suggestion: "Consider adding database indexes to improve query performance",
        code_example: "# Add migration:\n# add_index :table_name, :column_name"
      }
    end

    suggestions
  end
end
