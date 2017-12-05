require "bundler/gem_tasks"
require "rspec/core/rake_task"
require 'rake/proxmox'
Rake::Proxmox::RakeTasks.new

RSpec::Core::RakeTask.new(:spec)

task :default => :spec
