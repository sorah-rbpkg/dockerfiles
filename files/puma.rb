threads_count = ENV.fetch("THREADS_NUM") { 5 }
threads threads_count, threads_count

port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "production" }

workers ENV.fetch("WORKER_NUM") { 2 }
preload_app!

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart

before_fork do
  Barnes.start if defined? Barnes
end
