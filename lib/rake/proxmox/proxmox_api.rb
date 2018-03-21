require 'rest_client'
require 'json'

module Rake
  module Proxmox
    # ProxmoxApi adopted from https://github.com/nledez/proxmox
    # rubocop:disable Metrics/ClassLength
    class ProxmoxApi
      # Return connection status
      # - connected
      # - error
      attr_reader :connection_status

      # Create a object to manage a Proxmox server through API
      #
      # :call-seq:
      #   new(pve_cluster, node, username, password, realm, ssl_options)
      #   -> Proxmox
      #
      # Example:
      #
      #   Proxmox::Proxmox.new('https://the-proxmox-server:8006/api2/json/',
      #                        'node', 'root', 'secret', 'pam',
      #                        {verify_ssl: false})
      #
      # rubocop:disable Metrics/ParameterLists
      def initialize(pve_cluster, node, username, password, realm,
                     ssl_options = {})
        @pve_cluster = pve_cluster
        @node = node
        @username = username
        @password = password
        @realm = realm
        @ssl_options = ssl_options
        @connection_status = 'error'
        @site = RestClient::Resource.new(@pve_cluster, @ssl_options)
        @auth_params = create_ticket
      end

      def get(path, args = {})
        http_action_get(path, args)
      end

      def post(path, args = {})
        http_action_post(path, args)
      end

      def put(path, args = {})
        http_action_put(path, args)
      end

      def delete(path)
        http_action_delete(path)
      end

      # Get task status
      #
      # :call-seq:
      #   task_status(task-id) -> String
      #
      # - taksstatus
      # - taskstatus:exitstatus
      #
      # Example:
      #
      #   taskstatus \
      #     'UPID:localhost:00051DA0:119EAABC:521CCB19:vzcreate:203:root@pam:'
      #
      # Examples return:
      #   - running
      #   - stopped:OK
      #
      def task_status(upid, node = @node)
        data = http_action_get "nodes/#{node}/tasks/#{URI.encode upid}/status"
        status = data['status']
        exitstatus = data['exitstatus']
        if exitstatus
          "#{status}:#{exitstatus}"
        else
          status.to_s
        end
      end

      # get task log
      def task_log(upid, node = @node, start = 0, limit = 20)
        data = {
          start: start,
          limit: limit
        }
        http_action_get("nodes/#{node}/tasks/#{URI.encode upid}/log", data)
      end

      # Get template list
      #
      # :call-seq:
      #   templates -> Hash
      #
      # Return a Hash of all templates
      #
      # Example:
      #
      #   templates
      #
      # Example return:
      #
      #   {
      #     'ubuntu-10.04-standard_10.04-4_i386' => {
      #         'format' => 'tgz',
      #         'content' => 'vztmpl',
      #         'volid' => 'local:vztmpl/ubuntu-10.04-...d_10.04-4_i386.tar.gz',
      #         'size' => 142126884
      #     },
      #     'ubuntu-12.04-standard_12.04-1_i386' => {
      #         'format' => 'tgz',
      #         'content' => 'vztmpl',
      #         'volid' => 'local:vztmpl/ubuntu-12.04-...d_12.04-1_i386.tar.gz',
      #          'size' => 130040792
      #     }
      #  }
      #
      def templates
        data = http_action_get "nodes/#{@node}/storage/local/content"
        template_list = {}
        data.each do |ve|
          name = ve['volid'].gsub(%r{local:vztmpl\/(.*).tar.gz}, '\1')
          template_list[name] = ve
        end
        template_list
      end

      # Get CT list
      #
      # :call-seq:
      #   lxc_get -> Hash
      #
      # Return a Hash of all lxc container
      #
      # Example:
      #
      #   lxc_get
      #
      # Example return:
      #   {
      #     '101' => {
      #           'maxswap' => 536870912,
      #           'disk' => 405168128,
      #           'ip' => '192.168.1.5',
      #           'status' => 'running',
      #           'netout' => 272,
      #           'maxdisk' => 4294967296,
      #           'maxmem' => 536870912,
      #           'uptime' => 3068073,
      #           'swap' => 0,
      #           'vmid' => '101',
      #           'nproc' => '10',
      #           'diskread' => 0,
      #           'cpu' => 0.00031670581100007,
      #           'netin' => 0,
      #           'name' => 'test2.domain.com',
      #           'failcnt' => 0,
      #           'diskwrite' => 0,
      #           'mem' => 22487040,
      #           'type' => 'lxc',
      #           'cpus' => 1
      #     },
      #     [...]
      #   }
      def lxc_get(node = @node)
        data = http_action_get "nodes/#{node}/lxc"
        ve_list = {}
        data.each do |ve|
          ve_list[ve['vmid']] = ve
        end
        ve_list
      end

      # Create CT container
      #
      # :call-seq:
      #   lxc_post(ostemplate, vmid) -> String
      #   lxc_post(ostemplate, vmid, options) -> String
      #
      # Return a String as task ID
      #
      # Examples:
      #
      #   lxc_post('ubuntu-10.04-standard_10.04-4_i386', 200)
      #   lxc_post('ubuntu-10.04-standard_10.04-4_i386', 200, \
      #     {'hostname' => 'test.test.com', 'password' => 'testt' })
      #
      # Example return:
      #
      #   UPID:localhost:000BC66A:1279E395:521EFC4E:vzcreate:200:root@pam:
      #
      def lxc_post(ostemplate, vmid, config = {}, node = @node)
        config['vmid'] = vmid
        config['ostemplate'] = ostemplate
        vm_definition = config.to_a.map { |v| v.join '=' }.join '&'

        http_action_post("nodes/#{node}/lxc", vm_definition)
      end

      # Delete CT
      #
      # :call-seq:
      #   lxc_delete(vmid) -> String
      #
      # Return a string as task ID
      #
      # Example:
      #
      #   lxc_delete(200)
      #
      # Example return:
      #
      #   UPID:localhost:000BC66A:1279E395:521EFC4E:vzdelete:200:root@pam:
      #
      def lxc_delete(vmid, node = @node)
        http_action_delete "nodes/#{node}/lxc/#{vmid}"
      end

      # Get CT status
      #
      # :call-seq:
      #   lxc_delete(vmid) -> String
      #
      # Return a string as task ID
      #
      # Example:
      #
      #   lxc_delete(200)
      #
      # Example return:
      #
      #   UPID:localhost:000BC66A:1279E395:521EFC4E:vzdelete:200:root@pam:
      #
      def lxc_status(vmid, node = @node)
        http_action_get "nodes/#{node}/lxc/#{vmid}/status/current"
      end

      # Start CT
      #
      # :call-seq:
      #   lxc_start(vmid) -> String
      #
      # Return a string as task ID
      #
      # Example:
      #
      #   lxc_start(200)
      #
      # Example return:
      #
      #   UPID:localhost:000BC66A:1279E395:521EFC4E:vzstart:200:root@pam:
      #
      def lxc_start(vmid, node = @node)
        http_action_post "nodes/#{node}/lxc/#{vmid}/status/start"
      end

      # Stop CT
      #
      # :call-seq:
      #   lxc_stop(vmid) -> String
      #
      # Return a string as task ID
      #
      # Example:
      #
      #   lxc_stop(200)
      #
      # Example return:
      #
      #   UPID:localhost:000BC66A:1279E395:521EFC4E:vzstop:200:root@pam:
      #
      def lxc_stop(vmid, node = @node)
        http_action_post "nodes/#{node}/lxc/#{vmid}/status/stop"
      end

      # Shutdown CT
      #
      # :call-seq:
      #   lxc_shutdown(vmid) -> String
      #
      # Return a string as task ID
      #
      # Example:
      #
      #   lxc_shutdown(200)
      #
      # Example return:
      #
      #   UPID:localhost:000BC66A:1279E395:521EFC4E:vzshutdown:200:root@pam:
      #
      def lxc_shutdown(vmid, node = @node)
        http_action_post "nodes/#{node}/lxc/#{vmid}/status/shutdown"
      end

      # Get CT config
      #
      # :call-seq:
      #   lxc_config(vmid) -> String
      #
      # Return a string as task ID
      #
      # Example:
      #
      #   lxc_config(200)
      #
      # Example return:
      #
      #   {
      #     'quotaugidlimit' => 0,
      #     'disk' => 0,
      #     'ostemplate' => 'ubuntu-10.04-standard_10.04-4_i386.tar.gz',
      #     'hostname' => 'test.test.com',
      #     'nameserver' => '127.0.0.1 192.168.1.1',
      #     'memory' => 256,
      #     'searchdomain' => 'domain.com',
      #     'onboot' => 0,
      #     'cpuunits' => 1000,
      #     'swap' => 256,
      #     'quotatime' => 0,
      #     'digest' => 'e7e6e21a215af6b9da87a8ecb934956b8983f960',
      #     'cpus' => 1,
      #     'storage' => 'local'
      #   }
      #
      def lxc_config(vmid, node = @node)
        http_action_get "nodes/#{node}/lxc/#{vmid}/config"
      end

      # Set CT config
      #
      # :call-seq:
      #   lxc_config_set(vmid, parameters) -> Nil
      #
      # Return nil
      #
      # Example:
      #
      #   lxc_config(200, { 'swap' => 2048 })
      #
      # Example return:
      #
      #   nil
      #
      def lxc_config_set(vmid, data, node = @node)
        http_action_put("nodes/#{node}/lxc/#{vmid}/config", data)
      end

      # LXC snapshot
      def lxc_snapshot(vmid, snapname, desc, node = @node)
        data = {
          snapname: snapname,
          description: desc
        }
        http_action_post("nodes/#{node}/lxc/#{vmid}/snapshot", data)
      end

      # LXC snapshot list
      def lxc_snapshot_list(vmid, node = @node)
        http_action_get("nodes/#{node}/lxc/#{vmid}/snapshot")
      end

      # LXC snapshot delete
      def lxc_snapshot_delete(vmid, snapname, node = @node)
        http_action_delete("nodes/#{node}/lxc/#{vmid}/snapshot/#{snapname}")
      end

      # Get VM list
      def qemu_get
        data = http_action_get "nodes/#{@node}/qemu"
        ve_list = {}
        data.each do |ve|
          ve_list[ve['vmid']] = ve
        end
        ve_list
      end

      # Create VM container
      def qemu_post(template, vmid, config = {})
        config['vmid'] = vmid
        config['template'] = "local%3Aisol%2F#{template}.iso"
        config['kvm'] = 1
        vm_definition = config.to_a.map { |v| v.join '=' }.join '&'

        http_action_post("nodes/#{@node}/qemu", vm_definition)
      end

      # Delete VM
      def qemu_delete(vmid)
        http_action_delete "nodes/#{@node}/qemu/#{vmid}"
      end

      # Get VM status
      def qemu_status(vmid)
        http_action_get "nodes/#{@node}/qemu/#{vmid}/status/current"
      end

      # Start VM
      def qemu_start(vmid)
        http_action_post "nodes/#{@node}/qemu/#{vmid}/status/start"
      end

      # Stop VM
      def qemu_stop(vmid)
        http_action_post "nodes/#{@node}/qemu/#{vmid}/status/stop"
      end

      # Shutdown VM
      def qemu_shutdown(vmid)
        http_action_post "nodes/#{@node}/qemu/#{vmid}/status/shutdown"
      end

      # Get VM config
      def qemu_config(vmid)
        http_action_get "nodes/#{@node}/qemu/#{vmid}/config"
      end

      # Set VM config
      def qemu_config_set(vmid, data)
        http_action_put("nodes/#{@node}/qemu/#{vmid}/config", data)
      end

      # cluster Methods
      def cluster_resources_get(type)
        http_action_get("cluster/resources?type=#{type}")
      end

      # get cluster status
      def cluster_status
        http_action_get('cluster/status')
      end

      # Backup VM
      def vzdump_single(vmid, node = @node, storage = 'local',
                        mode = 'snapshot', compress = 1, remove = 1, pigz = 1,
                        lockwait = 5)
        data = {
          all: 0,
          compress: compress,
          storage: storage,
          remove: remove,
          pigz: pigz,
          mode: mode,
          lockwait: lockwait,
          vmid: vmid
        }
        http_action_post("nodes/#{node}/vzdump", data)
      end

      # list storage
      def list_storage(node = @node, storage = 'local')
        http_action_get("nodes/#{node}/storage/#{storage}/content")
      end

      # get backup job list
      def fetch_backup_jobs
        http_action_get('cluster/backup')
      end

      # fetch one backup job
      def fetch_backup_job(backupid)
        http_action_get("cluster/backup/#{backupid}")
      end

      # update backup job
      def update_backup_job(jobid, data)
        http_action_put("cluster/backup/#{jobid}", data)
      end

      # upload lxc template
      def upload_template(filename, node = @node, storage = 'local')
        "Template #{filename} does not exist locally" unless File.file? filename
        data = {
          content: 'vztmpl',
          filename: File.new(filename)
        }
        http_action_post("nodes/#{node}/storage/#{storage}/upload", data)
      end

      private

      # Methods manages auth
      def create_ticket
        post_param = { username: @username, realm: @realm, password: @password }
        @site['access/ticket'].post post_param do |resp, _req, _res, &_block|
          if resp.code == 200
            extract_ticket resp
          else
            @connection_status = 'error'
          end
        end
      end

      # Method create ticket
      def extract_ticket(response)
        data = JSON.parse(response.body)
        ticket = data['data']['ticket']
        csrf_prevention_token = data['data']['CSRFPreventionToken']
        unless ticket.nil?
          token = 'PVEAuthCookie=' + ticket.gsub!(/:/, '%3A').gsub!(/=/, '%3D')
        end
        @connection_status = 'connected'
        {
          CSRFPreventionToken: csrf_prevention_token,
          cookie: token
        }
      end

      # Extract data or return error
      def check_response(response)
        if response.code == 200
          JSON.parse(response.body)['data']
        else
          'NOK: error code = ' + response.code.to_s \
          + 'data = ' + response.body + "\n"
        end
      end

      # Methods manage http dialogs
      def http_action_post(url, data = {})
        # print "POST #{url}\n#{data}\n"
        @site[url].post data, @auth_params do |resp, _req, _res, &_block|
          check_response resp
        end
      end

      def http_action_put(url, data = {})
        @site[url].put data, @auth_params do |resp, _req, _res, &_block|
          check_response resp
        end
      end

      def http_action_get(url, data = {})
        @site[url].get @auth_params.merge(data) do |resp, _req, _res, &_block|
          check_response resp
        end
      end

      def http_action_delete(url)
        @site[url].delete @auth_params do |resp, _req, _res, &_block|
          check_response resp
        end
      end
    end
  end
end
