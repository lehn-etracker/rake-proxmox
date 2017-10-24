require 'spec_helper'
require 'rake'
require 'zlib'
require 'stringio'

describe Rake::Proxmox do
  it 'has a version number' do
    expect(Rake::Proxmox::VERSION).not_to be nil
  end

  before do
    ENV['PROXMOX_PVE_CLUSTER'] = 'https://pve1.example.com:8006/api2/json/'
    ENV['PROXMOX_NODE'] = 'pve1'
    ENV['PROXMOX_REALM'] = 'pve'
    ENV['PROXMOX_USERNAME'] = 'vagrant'
    ENV['PROXMOX_PASSWORD'] = 'vagrant'
    # stubsdir
    stubsdir = File.expand_path('../../support/stubs', __FILE__)

    # stubs for proxmox api calls
    stub_request(:post,
                 'https://pve1.example.com:8006/api2/json/access/ticket')\
      .with(body: { 'password' => 'vagrant',
                    'realm' => 'pve',
                    'username' => 'vagrant' },
            headers: { 'Accept' => '*/*',
                       'Accept-Encoding' => 'gzip, deflate',
                       'Content-Length' => '43',
                       'Content-Type' => 'application/x-www-form-urlencoded',
                       'Host' => 'pve1.example.com:8006',
                       'User-Agent' => 'rest-client/2.0.2 (linux-gnu x86_64) '\
                                       'ruby/2.3.1p112' })
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'access-ticket.resp.gz')),
                 headers: JSON.parse(File.read(
                                       File.join(stubsdir,
                                                 'access-ticket.head.json')
                 )))

    # get headers for stub requests with Cookie and CSRFPreventionToken
    stub_request_headers = JSON.parse(File.read(File.join(stubsdir,
                                                          'req-headers.json')))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/'\
                       'cluster/resources?type=vm')\
      .with(headers: stub_request_headers)
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req1.resp.gz')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req1.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev01/lxc/6011/snapshot')
      .with(headers: stub_request_headers)
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req2.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req2.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev01/lxc/6002/snapshot')
      .with(headers: stub_request_headers)
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req3.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req3.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev02/lxc/6012/snapshot')
      .with(headers: stub_request_headers)
      .to_return(status: 595,
                 body: File.read(File.join(stubsdir, 'req4.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req4.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev03/lxc/6013/snapshot')
      .with(headers: stub_request_headers)
      .to_return(status: 595,
                 body: File.read(File.join(stubsdir, 'req5.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req5.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev01/lxc/6251/snapshot')
      .with(headers: stub_request_headers)
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req6.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req6.head.json'))))

    # load rake tasks
    Rake::Proxmox::RakeTasks.new
  end

  describe 'Rake::Proxmox::RakeTasks.new' do
    # this list contains existing containers within proxmox cluster
    container = %w[consul-01 consul-02 consul-03 gw-01 mon-01]

    it 'should have task to destroy all container' do
      task = Rake::Task
      expect(task).to be_task_defined('proxmox:destroy:all')
    end

    it 'should have tasks to destroy single container' do
      task = Rake::Task
      container.each do |c|
        task_name = "proxmox:destroy:#{c}"
        expect(task).to be_task_defined(task_name)
      end
    end

    it 'should have task to snapshot all container' do
      task = Rake::Task
      expect(task).to be_task_defined('proxmox:snapshot:create:all')
    end

    it 'should have tasks to snapshot single container' do
      task = Rake::Task
      container.each do |c|
        task_name = "proxmox:snapshot:create:#{c}"
        expect(task).to be_task_defined(task_name)
      end
    end

    it 'should have task to delete all snapshots' do
      task = Rake::Task
      expect(task).to be_task_defined('proxmox:snapshot:delete:all')
    end

    it 'should have task proxmox:storage:list' do
      task = Rake::Task
      expect(task).to be_task_defined('proxmox:storage:list')
    end

    it 'should have task proxmox:storage:upload:template' do
      task = Rake::Task
      expect(task).to be_task_defined('proxmox:storage:upload:template')
    end

    it 'should have task proxmox:backup:list' do
      task = Rake::Task
      expect(task).to be_task_defined('proxmox:backup:list')
    end

    it 'should have task proxmox:backup:restore' do
      task = Rake::Task
      expect(task).to be_task_defined('proxmox:backup:restore')
    end

    it 'should have tasks to backup:create single container' do
      task = Rake::Task
      container.each do |c|
        task_name = "proxmox:backup:create:#{c}"
        expect(task).to be_task_defined(task_name)
      end
    end

    it 'should have tasks to backup:restore single container' do
      task = Rake::Task
      container.each do |c|
        task_name = "proxmox:backup:restore:#{c}"
        expect(task).to be_task_defined(task_name)
      end
    end
  end

  # it 'should bake a bar' do
  #   # Bar.any_instance.should_receive :bake
  #   Rake::Task['proxmox:storage:list'].invoke
  # end
end
