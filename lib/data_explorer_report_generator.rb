# frozen_string_literal: true

class DataExplorerReportGenerator
  def initialize(creator_user_id)
    @creator_user_id = creator_user_id
  end

  def generate(query_id, query_params, recipients)
    query = DataExplorer::Query.find(query_id)
    return [] unless query

    usernames = filter_recipients_by_query_access(recipients, query)
    return [] if usernames.empty?
    params = params_to_hash(query_params)

    result = DataExplorer.run_query(query, params)
    query.update!(last_run_at: Time.now)

    table = ResultToMarkdown.convert(result[:pg_result])

    build_report_pms(query, table, usernames)
  end

  def filter_recipients_by_query_access(recipients, query)
    return [] if recipients.empty?
    creator = User.find(@creator_user_id)
    return [] unless Guardian.new(creator).can_send_private_messages?

    recipients.reduce([]) do |names, recipient|
      if (group = Group.find_by(name: recipient))
        next names unless query.query_groups.exists?(group_id: group.id)
        next names.concat group.users.pluck(:username)
      elsif (user = User.find_by(username: recipient))
        next names unless Guardian.new(user).user_can_access_query?(query)
        next names << recipient
      end
    end
  end

  def params_to_hash(query_params)
    params = JSON.parse(query_params)
    params_hash = {}

    if !params.blank?
      param_key, param_value = [], []
      params.flatten.each.with_index do |data, i|
        if i % 2 == 0
          param_key << data
        else
          param_value << data
        end
      end

      params_hash = Hash[param_key.zip(param_value)]
    end

    params_hash
  end

  def build_report_pms(query, table = "", usernames = [])
    pms = []
    usernames.flatten.compact.uniq.each do |username|
      pm = {}
      pm["title"] = "Scheduled Report for #{query.name}"
      pm["target_usernames"] = Array(username)
      pm["raw"] = "Hi #{username}, your data explorer report is ready.\n\n" +
        "Query Name:\n#{query.name}\n\nHere are the results:\n#{table}\n\n" +
        "<a href='/admin/plugins/explorer?id=#{query.id}'>View query in Data Explorer</a>\n\n" +
        "Report created at #{Time.zone.now.strftime("%Y-%m-%d at %H:%M:%S")} (#{Time.zone.name})"
      pms << pm
    end
    pms
  end
end
