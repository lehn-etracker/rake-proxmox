require 'spec_helper'
require 'rake'
require 'zlib'
require 'stringio'

describe Rake::Proxmox do
  it 'has a version number' do
    expect(Rake::Proxmox::VERSION).not_to be nil
  end

  let(:stubsdir) do
    File.expand_path('../../support/stubs', __FILE__)
  end

  before do
    ENV['PROXMOX_PVE_CLUSTER'] = 'https://pve1.example.com:8006/api2/json/'
    ENV['PROXMOX_NODE'] = 'pve1'
    ENV['PROXMOX_REALM'] = 'pve'
    ENV['PROXMOX_USERNAME'] = 'vagrant'
    ENV['PROXMOX_PASSWORD'] = 'vagrant'

    # stubs for proxmox api calls
    stub_request(:post,
                 'https://pve1.example.com:8006/api2/json/access/ticket')\
      .with(body: { 'password' => 'vagrant',
                    'realm' => 'pve',
                    'username' => 'vagrant' },
            headers: { 'Accept' => '*/*',
                       'Accept-Encoding' => 'gzip,deflate',
                       'Content-Type' => 'application/x-www-form-urlencoded',
                       'User-Agent' => /.*/ })
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'access-ticket.resp')),
                 headers: JSON.parse(File.read(
                                       File.join(stubsdir,
                                                 'access-ticket.head.json')
                 )))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/'\
                       'cluster/resources?type=vm')\
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req1.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req1.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev01/lxc/6011/snapshot')
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req2.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req2.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev01/lxc/6002/snapshot')
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req3.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req3.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev02/lxc/6012/snapshot')
      .to_return(status: 595,
                 body: File.read(File.join(stubsdir, 'req4.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req4.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev03/lxc/6013/snapshot')
      .to_return(status: 595,
                 body: File.read(File.join(stubsdir, 'req5.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req5.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/nodes/hpvdev01/lxc/6251/snapshot')
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req6.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req6.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/cluster/backup/7ed5a5dc646bddbc7ef38f5f1fd8426595b21e98:1')
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req7.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req7.head.json'))))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/cluster/backup')
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req8.resp')),
                 headers: JSON.parse(File.read(File.join(stubsdir,
                                                         'req8.head.json'))))

    stub_request(:put, 'https://pve1.example.com:8006/api2/json/cluster/backup/7ed5a5dc646bddbc7ef38f5f1fd8426595b21e98:1')
      .to_return(status: 200,
                 body: File.read(File.join(stubsdir, 'req9.resp')))

    stub_request(:get, 'https://pve1.example.com:8006/api2/json/cluster/status')
      .to_return(status: 200,
                 body: File.read(
                   File.join(stubsdir, 'cluster_status.body.resp')
                 ),
                 headers: JSON.parse(
                   File.read(
                     File.join(stubsdir,
                               'cluster_status.head.json')
                   )
                 ))

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

    it 'should have task to list all cluster backup jobs' do
      task = Rake::Task
      task_name = 'proxmox:cluster:backupjob:list'
      expect(task).to be_task_defined(task_name)
      my_task = Rake::Task[task_name]
      expect(my_task.arg_names).to eq([:json])
    end

    it 'should be able to exclude a certain range of container ids'\
       ' from all backup jobs' do
      task_name = 'proxmox:cluster:backupjob:exclude_range'
      my_task = Rake::Task[task_name]
      # define expectations
      ['Add following IDs to exclude list in backup job with '\
       'id 7ed5a5dc646bddbc7ef38f5f1fd8426595b21e98:1 and starttime 20:00:',
       'Found following VM Ids in range 6000 to 6500: ',
       '6011,6002,6012,6013,6251'].each do |output|
        expect(STDOUT).to receive(:puts).with(output).at_least(:once)
      end
      # call task
      my_task.reenable
      my_task.invoke('6000', '6500')
    end

    it 'should get correct json proxmox:cluster:backupjob:list[true]' do
      task_name = 'proxmox:cluster:backupjob:list'
      my_task = Rake::Task[task_name]
      # define expectations
      stubsdir = File.expand_path('../../support/stubs', __FILE__)
      stub_resp = File.read(File.join(stubsdir, 'req8.resp'))
      resp = JSON.parse(stub_resp)
      expect(STDOUT).to receive(:puts).with(resp['data'].to_json)
        .at_least(:once)
      # call task
      my_task.reenable
      my_task.invoke('true')
    end

    it 'should get correct data proxmox:cluster:backupjob:list' do
      task_name = 'proxmox:cluster:backupjob:list'
      my_task = Rake::Task[task_name]
      # define expectations
      ['list all backup jobs: ',
       '1.  id: 7ed5a5dc646bddbc7ef38f5f1fd8426595b21e98:1;'\
       ' starttime: 20:00'].each do |output|
        expect(STDOUT).to receive(:puts).with(output).at_least(:once)
      end
      # call task
      my_task.reenable
      my_task.invoke
    end

    it 'should have task to show specific cluster backup job' do
      task = Rake::Task
      task_name = 'proxmox:cluster:backupjob:show'
      expect(task).to be_task_defined(task_name)
      my_task = Rake::Task[task_name]
      expect(my_task.arg_names).to eq(%i[jobid json])
    end

    it 'should get correct json from cluster backup job show command' do
      task_name = 'proxmox:cluster:backupjob:show'
      my_task = Rake::Task[task_name]
      jobid = '7ed5a5dc646bddbc7ef38f5f1fd8426595b21e98:1'
      # define expectations
      stubsdir = File.expand_path('../../support/stubs', __FILE__)
      stub_resp = File.read(File.join(stubsdir, 'req7.resp'))
      resp = JSON.parse(stub_resp)
      expect(STDOUT).to receive(:puts).with(resp['data'].to_json)
        .at_least(:once)
      # call task
      my_task.reenable
      my_task.invoke(jobid, 'true')
    end

    it 'should get correct print from cluster backup job show command' do
      task_name = 'proxmox:cluster:backupjob:show'
      my_task = Rake::Task[task_name]
      jobid = '7ed5a5dc646bddbc7ef38f5f1fd8426595b21e98:1'
      # define expectations
      ['Backup Job Parameter:',
       "all               : 1\n",
       "compress          : lzo\n",
       "dow               : mon,tue,wed,thu,fri,sat,sun\n",
       "enabled           : 1\n",
       "exclude           : 909,913,940\n",
       "id                : 7ed5a5dc646bddbc7ef38f5f1fd8426595b21e98:1\n",
       "mailnotification  : failure\n",
       "mailto            : sysadmin@example.net\n",
       "mode              : snapshot\n",
       "quiet             : 1\n",
       "starttime         : 20:00\n",
       "storage           : store03\n"]
        .each do |output|
        expect(STDOUT).to receive(:puts).with(output).at_least(:once)
      end
      # call task
      my_task.reenable
      my_task.invoke(jobid)
    end

    it 'should have task to get cluster status' do
      task = Rake::Task
      expect(task).to be_task_defined('proxmox:cluster:status')
    end

    context 'cluster not ok' do
      it 'task proxmox:cluster:status should raise error if cluster not ok' do
        task_name = 'proxmox:cluster:status'
        my_task = Rake::Task[task_name]
        my_task.reenable
        # define expectations
        expect { my_task.invoke('true') }.to raise_error(
          RuntimeError,
          'Proxmox Node id=node/hpvdev03,ip=192.168.124.72,level=,local=0'\
            ',name=hpvdev03,nodeid=3,online=1,type=node has errors'
        )
      end
    end

    context 'cluster ok' do
      before do
        stub_request(:get, 'https://pve1.example.com:8006/api2/json/cluster/status')
          .to_return(status: 200,
                     body: File.read(
                       File.join(stubsdir, 'cluster_status-ok.body.resp')
                     ),
                     headers: JSON.parse(
                       File.read(
                         File.join(stubsdir,
                                   'cluster_status-ok.head.json')
                       )
                     ))
      end

      it 'task proxmox:cluster:status should return message if cluster ok' do
        task_name = 'proxmox:cluster:status'
        my_task = Rake::Task[task_name]
        my_task.reenable
        # define expectations
        expect(STDOUT).to receive(:puts).with(
          'Proxmox Cluster HPV-DEV-CLUSTER online with 3 nodes'
        ).at_least(:once)
        # call task
        expect { my_task.invoke('true') }.not_to raise_error
      end
    end
  end
end
