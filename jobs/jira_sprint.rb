require 'net/http'
require 'json'
require 'time'
require 'open-uri'
require 'cgi'
require_relative '../conf/dashboard_config'

JIRA_SPRINT_CONFIG = DashboardConfig.load()

def get_sprint_statistics(url, username, password, rapid_view_id, sprint_id)
  uri = URI.parse("#{url}/rest/greenhopper/1.0/rapid/charts/sprintreport?rapidViewId=#{rapid_view_id}&sprintId=#{sprint_id}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  request = Net::HTTP::Get.new(uri.request_uri)

  if !username.nil? && !username.empty?
    request.basic_auth(username, password)
  end

  data = JSON.parse(http.request(request).body)

  sprint_data = data["sprint"]
  contents_data = data["contents"]

  sprint_statistics = {"days_remaining" => 0, "progress" => 0, "wip_issues" => 0}

  sprint_statistics['days_remaining'] = sprint_data["daysRemaining"]
  sprint_statistics['progress'] = calculate_sprint_progress(contents_data["completedIssues"].count, contents_data["issuesNotCompletedInCurrentSprint"].count)
  sprint_statistics['wip_issues'] = get_wip_issues(contents_data["issuesNotCompletedInCurrentSprint"])

  sprint_statistics
end

def calculate_sprint_progress(completed_issues_count, not_completed_issues_count)
  total = completed_issues_count + not_completed_issues_count
  progress = (completed_issues_count.to_f / total) * 100
  progress.to_i
end

def get_wip_issues(not_completed_issues)
  wip_issues = []
  not_completed_issues.each {|issue| wip_issues.push({'title' => get_issue_title(issue), 'assignee' => issue["assigneeName"]}) if is_wip_issue?(issue)}

  wip_issues
end

def get_issue_title(issue)
  issue["key"] + " " + issue["summary"]
end

def is_wip_issue?(issue)
  status_name = issue["statusName"]

  if status_name.eql? "In Development" or status_name.eql? "In Progress"
    true
  else
    false
  end
end

SCHEDULER.every '1h', :first_in => 0 do
  sprint_statistics = get_sprint_statistics(JIRA_SPRINT_CONFIG[:jira_url], JIRA_SPRINT_CONFIG[:jira_username], JIRA_SPRINT_CONFIG[:jira_password], JIRA_SPRINT_CONFIG[:rapid_view_id], JIRA_SPRINT_CONFIG[:sprint_id])

  send_event('sprint-days-remaining', {current: sprint_statistics['days_remaining']})
  send_event('sprint-progress', {value: sprint_statistics['progress']})
  send_event('wip-tasks', {tasks: sprint_statistics['wip_issues']})
end
