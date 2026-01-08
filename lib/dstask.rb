# frozen_string_literal: true

require 'open3'
require 'json'
require 'shellwords'

module Dstask
  class Error < StandardError; end

  class << self
    # Read operations - return parsed JSON arrays

    def tasks(filter: nil)
      run_read('show-open', filter)
    end

    def active_tasks
      run_read('show-active')
    end

    def paused_tasks
      run_read('show-paused')
    end

    def resolved_tasks
      run_read('show-resolved')
    end

    def projects
      run_read('show-projects')
    end

    def tags
      run_read('show-tags')
    end

    def task(id)
      validate_id!(id)
      tasks = run_read('show-open')
      tasks.find { |t| t['id'] == id.to_i }
    end

    # Write operations - return { success: bool, message: string }

    def add(summary:, project: nil, priority: nil, tags: [])
      args = [summary]
      args << "project:#{project}" if project && !project.empty?
      args << priority if priority && !priority.empty?
      tags.each { |tag| args << "+#{tag}" if tag && !tag.empty? }

      run_write('add', args)
    end

    def start(id)
      validate_id!(id)
      run_write(id.to_s, ['start'])
    end

    def stop(id)
      validate_id!(id)
      run_write(id.to_s, ['stop'])
    end

    def done(id)
      validate_id!(id)
      run_write(id.to_s, ['done'])
    end

    def remove(id)
      validate_id!(id)
      run_write(id.to_s, ['remove'])
    end

    def sync(script_path)
      return { success: false, message: 'No sync script configured', stdout: '', stderr: '' } unless script_path

      stdout, stderr, status = Open3.capture3(script_path, chdir: ENV['HOME'])
      {
        success: status.success?,
        message: status.success? ? 'Sync completed' : 'Sync failed',
        stdout: stdout,
        stderr: stderr
      }
    rescue Errno::ENOENT
      { success: false, message: "Sync script not found: #{script_path}", stdout: '', stderr: '' }
    rescue Errno::EACCES
      { success: false, message: "Sync script not executable: #{script_path}", stdout: '', stderr: '' }
    end

    def modify(id, project: nil, priority: nil, add_tags: [], remove_tags: [])
      validate_id!(id)
      args = ['modify']

      args << "project:#{project}" if project && !project.empty?
      args << priority if priority && !priority.empty?
      add_tags.each { |tag| args << "+#{tag}" if tag && !tag.empty? }
      remove_tags.each { |tag| args << "-#{tag}" if tag && !tag.empty? }

      return { success: true, message: 'No changes specified' } if args.length == 1

      run_write(id.to_s, args)
    end

    private

    def validate_id!(id)
      raise Error, 'Invalid task ID' unless id.to_s.match?(/\A\d+\z/)
    end

    def run_read(command, filter = nil)
      # Always use '--' to ignore any global context
      cmd = ['dstask', command, '--']
      cmd.concat(Shellwords.split(filter)) if filter && !filter.empty?

      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        # Some commands return empty on no results
        return [] if stdout.strip.empty?
        raise Error, "dstask error: #{stderr}"
      end

      return [] if stdout.strip.empty?

      JSON.parse(stdout)
    rescue JSON::ParserError => e
      raise Error, "Failed to parse dstask output: #{e.message}"
    end

    def run_write(id_or_cmd, args)
      # Always use '--' to ignore any global context
      cmd = ['dstask', id_or_cmd, '--'] + args.map(&:to_s)

      stdout, stderr, status = Open3.capture3(*cmd)

      if status.success?
        { success: true, message: stdout.strip }
      else
        { success: false, message: stderr.strip.empty? ? stdout.strip : stderr.strip }
      end
    end
  end
end
