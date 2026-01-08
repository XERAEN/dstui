# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/contrib'
require 'yaml'
require_relative 'lib/dstask'

module Dstui
  CONFIG_PATH = File.join(__dir__, 'config.yml')
  CONFIG = File.exist?(CONFIG_PATH) ? YAML.load_file(CONFIG_PATH) : {}

  class App < Sinatra::Base
    set :root, __dir__
    set :public_folder, -> { File.join(root, 'public') }
    set :views, -> { File.join(root, 'views') }

    # Configure permitted hosts from config.yml
    if CONFIG['permitted_hosts']
      hosts = CONFIG['permitted_hosts']
      if hosts == ['*'] || hosts == '*'
        set :host_authorization, permitted_hosts: [/.*/]
      else
        set :host_authorization, permitted_hosts: Array(hosts)
      end
    end

    enable :sessions
    set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(32) }

    helpers do
      def h(text)
        Rack::Utils.escape_html(text.to_s)
      end

      def flash
        session[:flash] ||= {}
      end

      def set_flash(type, message)
        flash[type] = message
      end

      def get_flash(type)
        flash.delete(type)
      end

      def active_nav?(path)
        return true if path == '/' && request.path_info == '/'
        return false if path == '/'
        request.path_info.start_with?(path)
      end

      def priority_class(priority)
        case priority
        when 'P0' then 'priority-critical'
        when 'P1' then 'priority-high'
        when 'P2' then 'priority-normal'
        when 'P3' then 'priority-low'
        else 'priority-normal'
        end
      end

      def status_class(status)
        case status
        when 'active' then 'status-active'
        when 'paused' then 'status-paused'
        else 'status-pending'
        end
      end

      def build_filter
        parts = []
        parts << "project:#{params[:project]}" if params[:project] && !params[:project].empty?
        parts << params[:priority] if params[:priority] && !params[:priority].empty?
        parts << "+#{params[:tag]}" if params[:tag] && !params[:tag].empty?
        parts << params[:q] if params[:q] && !params[:q].empty?
        parts.join(' ')
      end
    end

    # Task list (default view)
    get '/' do
      filter = build_filter
      @tasks = Dstask.tasks(filter: filter.empty? ? nil : filter)
      @projects = Dstask.projects rescue []
      @current_project = params[:project]
      @current_priority = params[:priority]
      @current_tag = params[:tag]
      @current_query = params[:q]
      erb :tasks
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      @tasks = []
      @projects = []
      erb :tasks
    end

    # Active tasks
    get '/active' do
      @tasks = Dstask.active_tasks
      @projects = Dstask.projects rescue []
      @view_title = 'Active Tasks'
      erb :tasks
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      @tasks = []
      @projects = []
      erb :tasks
    end

    # Resolved tasks
    get '/resolved' do
      @tasks = Dstask.resolved_tasks
      @projects = Dstask.projects rescue []
      @all_tags = @tasks.flat_map { |t| t['tags'] || [] }.uniq.sort
      @view_title = 'Resolved Tasks'
      erb :tasks
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      @tasks = []
      @projects = []
      erb :tasks
    end

    # Projects overview
    get '/projects' do
      @projects = Dstask.projects
      erb :projects
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      @projects = []
      erb :projects
    end

    # Runboard (Kanban view)
    get '/runboard' do
      all_tasks = Dstask.tasks
      @pending_tasks = all_tasks.select { |t| t['status'] == 'pending' }
      @active_tasks = all_tasks.select { |t| t['status'] == 'active' }
      @paused_tasks = all_tasks.select { |t| t['status'] == 'paused' }
      @projects = Dstask.projects rescue []
      @all_tags = all_tasks.flat_map { |t| t['tags'] || [] }.uniq.sort
      erb :runboard
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      @pending_tasks = []
      @active_tasks = []
      @paused_tasks = []
      @projects = []
      @all_tags = []
      erb :runboard
    end

    # Sync page
    get '/sync' do
      @sync_configured = !CONFIG['sync_script'].nil?
      erb :sync
    end

    # Execute sync (AJAX endpoint)
    post '/sync' do
      content_type :json
      result = Dstask.sync(CONFIG['sync_script'])
      if result[:success]
        { success: true, message: result[:message], stdout: result[:stdout], stderr: result[:stderr] }.to_json
      else
        status 422
        { success: false, message: result[:message], stdout: result[:stdout], stderr: result[:stderr] }.to_json
      end
    end

    # New task form
    get '/tasks/new' do
      @task = {}
      @projects = Dstask.projects rescue []
      @is_new = true
      erb :task_form
    end

    # Create task
    post '/tasks' do
      tags = (params[:tags] || '').split(/[,\s]+/).map(&:strip).reject(&:empty?)

      result = Dstask.add(
        summary: params[:summary],
        project: params[:project],
        priority: params[:priority],
        tags: tags
      )

      if result[:success]
        set_flash(:success, 'Task created successfully')
        redirect '/'
      else
        set_flash(:error, result[:message])
        @task = params
        @projects = Dstask.projects rescue []
        @is_new = true
        erb :task_form
      end
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      redirect '/'
    end

    # Edit task form
    get '/tasks/:id/edit' do
      @task = Dstask.task(params[:id])
      if @task.nil?
        set_flash(:error, 'Task not found')
        redirect '/'
        return
      end
      @projects = Dstask.projects rescue []
      @is_new = false
      erb :task_form
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      redirect '/'
    end

    # Update task
    post '/tasks/:id' do
      tags_input = (params[:tags] || '').split(/[,\s]+/).map(&:strip).reject(&:empty?)
      original_tags = (params[:original_tags] || '').split(',').map(&:strip).reject(&:empty?)

      add_tags = tags_input - original_tags
      remove_tags = original_tags - tags_input

      result = Dstask.modify(
        params[:id],
        project: params[:project],
        priority: params[:priority],
        add_tags: add_tags,
        remove_tags: remove_tags
      )

      if result[:success]
        set_flash(:success, 'Task updated successfully')
      else
        set_flash(:error, result[:message])
      end
      redirect '/'
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      redirect '/'
    end

    # Start task
    post '/tasks/:id/start' do
      result = Dstask.start(params[:id])
      if result[:success]
        set_flash(:success, 'Task started')
      else
        set_flash(:error, result[:message])
      end
      redirect back
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      redirect back
    end

    # Stop task
    post '/tasks/:id/stop' do
      result = Dstask.stop(params[:id])
      if result[:success]
        set_flash(:success, 'Task stopped')
      else
        set_flash(:error, result[:message])
      end
      redirect back
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      redirect back
    end

    # Mark task done
    post '/tasks/:id/done' do
      result = Dstask.done(params[:id])
      if result[:success]
        set_flash(:success, 'Task completed')
      else
        set_flash(:error, result[:message])
      end
      redirect back
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      redirect back
    end

    # Remove task
    post '/tasks/:id/remove' do
      result = Dstask.remove(params[:id])
      if result[:success]
        set_flash(:success, 'Task removed')
      else
        set_flash(:error, result[:message])
      end
      redirect back
    rescue Dstask::Error => e
      set_flash(:error, e.message)
      redirect back
    end

    # Update task status (AJAX endpoint for runboard)
    post '/tasks/:id/status' do
      content_type :json
      new_status = params[:status]
      task_id = params[:id]

      result = case new_status
               when 'active'
                 Dstask.start(task_id)
               when 'paused'
                 Dstask.stop(task_id)
               when 'pending'
                 # To move to pending, we stop the task
                 Dstask.stop(task_id)
               else
                 { success: false, message: 'Invalid status' }
               end

      if result[:success]
        { success: true, message: 'Status updated' }.to_json
      else
        status 422
        { success: false, message: result[:message] }.to_json
      end
    rescue Dstask::Error => e
      status 500
      { success: false, message: e.message }.to_json
    end
  end
end
