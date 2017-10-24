# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rake/proxmox/version'

Gem::Specification.new do |spec|
  spec.name          = 'rake-proxmox'
  spec.version       = Rake::Proxmox::VERSION
  spec.authors       = ['Sebastian Lehn']
  spec.email         = ['lehn@etracker.com']

  spec.summary       = 'Provides rake tasks for proxmox api'
  spec.description   = 'Provides rake tasks to manage proxmox cluster'
  spec.homepage      = 'https://github.com/lehn-etracker/rake-proxmox'
  spec.license       = 'MIT'

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org/'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'

  spec.add_runtime_dependency 'rest-client', '~> 2.0', '>= 2.0.2'
  spec.add_runtime_dependency 'json', '~> 2.1'
end
