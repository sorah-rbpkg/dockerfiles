# vim: ft=ruby

timeout (ENV['UNICORN_TIMEOUT'] || 30).to_i

if ENV['LISTEN_UNIX']
  listen ENV['LISTEN_UNIX'], backlog: 2048
else
  listen (ENV['PORT'] || 8080).to_i
end

preload_app true

worker_processes (ENV['WORKER_NUM'] || 4).to_i

pid '/run/unicorn.pid'
stdout_path '/dev/stdout'
stderr_path '/dev/stderr'

before_fork do |server, worker|
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.connection_handler.clear_all_connections!
  end

  old_pid_path = "#{pid_path}.oldbin"
  if File.exists?(old_pid_path) && server.pid != old_pid_path
    begin
      Process.kill("QUIT", File.read(old_pid_path).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
    end
  end
end

after_fork do |server, worker|
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.connection_handler.connection_pool_list.map(&:connections).flatten.each { |c| c.reconnect! }
  end
end

if ENV['RAILS_ENV']
  ENV['RACK_ENV'] = ENV['RAILS_ENV']
end
