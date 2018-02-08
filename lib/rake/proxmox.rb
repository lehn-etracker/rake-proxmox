require 'rake/proxmox/version'
require 'rake/proxmox/proxmox_api'
require 'rake/tasklib'

module Rake
  module Proxmox
    # This class provides rake tasks to control proxmox cluster through api.
    #
    # rubocop:disable Metrics/ClassLength
    class RakeTasks < ::Rake::TaskLib
      # @yield [self] gives itself to the block
      # rubocop:disable Metrics/AbcSize
      def initialize(ssl_options = {})
        unless ENV.include?('PROXMOX_PVE_CLUSTER')
          puts ''
          puts '# Proxmox Tasks are not available without correct environment'
          puts '#'
          puts '# Please set following variables to enable that feature:'
          puts '#'
          puts '# export PROXMOX_PVE_CLUSTER='\
            'https://pve1.example.com:8006/api2/json/'
          puts '# export PROXMOX_NODE=pve1'
          puts '# export PROXMOX_REALM=pve'
          puts '# export PROXMOX_USERNAME=vagrant'
          puts '# export PROXMOX_PASSWORD=vagrant'
          puts ''
          return false
        end

        @proxmox = Rake::Proxmox::ProxmoxApi.new(
          ENV['PROXMOX_PVE_CLUSTER'],
          ENV['PROXMOX_NODE'],
          ENV['PROXMOX_USERNAME'],
          ENV['PROXMOX_PASSWORD'],
          ENV['PROXMOX_REALM'],
          ssl_options
        )

        # container for current lxc status
        @lxc_status = {}

        yield self if block_given?
        define
      end

      # @return [Proxmox] a Proxmox::Proxmox
      attr_reader :proxmox

      # @return [Hash] from Proxmox.lxc_get
      attr_accessor :lxc_status

      private

      def update_lxc_status
        # self.lxc_status = proxmox.lxc_get
        proxmox.cluster_resources_get('vm').each do |vm|
          # print "vm: #{vm}\n"
          # print "vm: #{vm['name']} on #{vm['node']}\n"
          next unless vm.include?('type')
          next unless vm.include?('vmid')
          next unless vm['type'] <=> 'lxc'
          lxc_status[vm['vmid']] = vm
        end
        # print lxc_status
      end

      def wait_for_task(upid, node = nil)
        max_n = 0
        if upid.include?('NOK: error code')
          print "Proxmox task failed #{upid}"
          l = proxmox.task_log(upid, node, max_n)
          return false unless l.is_a?(Array)
          l.each do |log_entry|
            next if log_entry['n'].to_i <= max_n
            print "[#{log_entry['n']}] #{log_entry['t']}\n"
            max_n = log_entry['n'].to_i
          end
          return false
        end
        status = proxmox.task_status(upid, node)
        until status.include? ':'
          sleep 1
          print "waiting for task: '#{upid}' [#{status}]\n"
          proxmox.task_log(upid, node, max_n).each do |log_entry|
            next if log_entry['n'].to_i <= max_n
            print "[#{log_entry['n']}] #{log_entry['t']}\n"
            max_n = log_entry['n'].to_i
          end
          status = proxmox.task_status(upid, node)
        end
        (_final_status, exitstatus) = status.split(':')
        if exitstatus.include?('OK')
          print "waiting for task: '#{upid}' [#{exitstatus}]\n"
          return true
        end
        proxmox.task_log(upid, node, max_n).each do |log_entry|
          next if log_entry['n'].to_i <= max_n
          print "[#{log_entry['n']}] #{log_entry['t']}\n"
          max_n = log_entry['n'].to_i
        end
        print "waiting for task failed: '#{upid}' [#{exitstatus}]\n"
        false
      end

      def lxc_stop(vmid)
        prop = lxc_status[vmid]
        return false unless prop.include?('status')
        return false unless prop.include?('node')
        return true if prop['status'].include?('stopped')
        print "stopping CT #{vmid} (#{prop['name']})\n"
        taskid = proxmox.lxc_stop(vmid, prop['node'])
        wait_for_task(taskid, prop['node'])
      end

      def lxc_destroy(vmid)
        prop = lxc_status[vmid]
        return false unless prop.include?('name')
        return false unless prop.include?('node')
        print "destroy CT #{vmid} (#{prop['name']})\n"
        taskid = proxmox.lxc_delete(vmid, prop['node'])
        wait_for_task(taskid, prop['node'])
      end

      def lxc_snapshot(vmid, name, desc)
        prop = lxc_status[vmid]
        return false unless prop.include?('status')
        return false unless prop.include?('node')
        print "snapshot vmid: #{vmid} (#{prop['name']})\n"
        taskid = proxmox.lxc_snapshot(vmid, name, desc, prop['node'])
        wait_for_task(taskid, prop['node'])
      end

      def lxc_snapshot_list(vmid)
        prop = lxc_status[vmid]
        return false unless prop.include?('status')
        return false unless prop.include?('node')
        # print "snapshot list vmid: #{vmid} (#{prop['name']})\n"
        l = proxmox.lxc_snapshot_list(vmid, prop['node'])
        return false if l.is_a?(String)
        l
      end

      def lxc_snapshot_delete(vmid, snapname)
        prop = lxc_status[vmid]
        return false unless prop.include?('status')
        return false unless prop.include?('node')
        print "snapshot delete #{snapname} vmid: #{vmid} (#{prop['name']})\n"
        taskid = proxmox.lxc_snapshot_delete(vmid, snapname, prop['node'])
        wait_for_task(taskid, prop['node'])
      end

      def lxc_backup(vmid, storage, mode = 'snapshot')
        prop = lxc_status[vmid]
        return false unless prop.include?('status')
        return false unless prop.include?('node')
        print "vzdump to #{storage} vmid: #{vmid} (#{prop['name']})\n"
        taskid = proxmox.vzdump_single(vmid, prop['node'], storage, mode)
        wait_for_task(taskid, prop['node'])
      end

      def lxc_restore(vmid, storage, backup_storage, backup, node = nil)
        options = {
          force: 1,
          restore: 1,
          storage: storage
        }
        prop = if node
                 p = {}
                 p['status'] = 'to-be-recovered'
                 p['node'] = node.to_s
                 # return p into prop
                 p
               else
                 lxc_status[vmid]
               end
        return false unless prop.include?('status')
        return false unless prop.include?('node')
        put "vzrestore of #{storage}:#{file} to vmid: #{vmid} (#{prop['name']})"
        taskid = proxmox.lxc_post("#{backup_storage}:#{backup}", vmid, options,
                                  prop['node'])
        wait_for_task(taskid, prop['node'])
      end

      # define Rake tasks
      def define
        desc 'Proxmox'
        update_lxc_status
        namespace 'proxmox' do
          desc 'upload template to proxmox storage'
          task 'storage:upload:template', %i[filename
                                             node
                                             storage
                                             force] do |_t, args|
            args.with_defaults(storage: 'local')
            args.with_defaults(node: ENV['PROXMOX_NODE'])
            args.with_defaults(force: 'false')
            # get upload filename
            upload_file_split = File.split(args.filename)
            upload_filename = upload_file_split[1]
            upload_size_b = File.size?(args.filename)
            # validate file does not already exist
            should_i_upload = true
            proxmox.list_storage(args.node, args.storage).each do |c|
              (_c_storage, c_path) = c['volid'].split(':')
              (_c_content, c_name) = c_path.split('/')
              next unless c_name == upload_filename
              # check filesize
              if c['size'].to_i >= upload_size_b.to_i
                puts "Template #{upload_filename} already on server"\
                     " (#{c['size'].to_i / 1024 / 1024}MB)"
                should_i_upload = false
              else
                puts 'Template has wrong size'\
                     " Local: #{upload_filename.to_i / 1024 / 1024}MB"\
                     " Proxmox: #{c['size'].to_i / 1024 / 1024}MB"
              end
              # found image leave loop
              break
            end
            if should_i_upload || args.force.to_s != 'false'
              puts "upload template: #{args.filename} to "\
                   "#{args.storage}@#{args.node}:\n"
              r = proxmox.upload_template(args.filename, args.node,
                                          args.storage)
              puts "upload result: #{r}"
            end
          end

          desc 'list proxmox storage'
          task 'storage:list', %i[node storage] do |_t, args|
            args.with_defaults(storage: 'local')
            args.with_defaults(node: ENV['PROXMOX_NODE'])
            print "list_storage: #{args.storage}@#{args.node}:\n"
            proxmox.list_storage(args.node, args.storage).each do |c|
              print " content:#{c['content']} volid:#{c['volid']}\n"
            end
          end

          desc 'list all backup jobs'
          task 'cluster:backupjob:list', %i[json] do |_t, args|
            # handle arguments
            args.with_defaults(json: 'false')
            print_json = /true|1|j|y/ =~ args.json ? true : false
            # fetch jobs
            jobs = proxmox.fetch_backup_jobs
            # handle errors
            raise 'Error while fetching backup jobs' unless jobs.is_a?(Array)
            # produce output
            if print_json
              puts jobs.to_json
            else
              puts 'list all backup jobs: '
              jobs.each_with_index do |c, i|
                puts "#{i + 1}.  id: #{c['id']}; starttime: #{c['starttime']}"
              end
            end
          end

          desc 'show details of backup job identified by id'
          task 'cluster:backupjob:show', %i[jobid json] do |_t, args|
            # handle arguments
            args.with_defaults(json: 'false')
            print_json = /true|1|j|y/ =~ args.json ? true : false
            raise 'Please provide backup jobid' unless args.jobid
            # fetch job details
            job = proxmox.fetch_backup_job(args.jobid)
            # handle errors
            unless job.is_a?(Hash)
              raise "There is no backupjob with id #{args.jobid}"
            end
            # produce output
            if print_json
              puts job.to_json
            else
              puts 'Backup Job Parameter:'
              job.sort.each do |k, v|
                puts format "%-18s: %s\n", k.to_s, v.to_s
              end
            end
          end

          desc 'exclude VM id ranges from all backup jobs'
          task 'cluster:backupjob:exclude_range', %i[range_min range_max] \
            do |_t, args|
            args.with_defaults(range_min: 900)
            args.with_defaults(range_max: 999)
            exclude_list = []
            lxc_status.each do |vmid, _|
              exclude_list.push(vmid.to_s) if vmid >= args.range_min.to_i && \
                                              vmid < args.range_max.to_i + 1
            end
            if exclude_list.empty?
              puts "No VM Ids found in range #{args.range_min}"\
                   " to #{args.range_max}. Nothing to exclude."
              next
            end
            puts "Found following VM Ids in range #{args.range_min}"\
                 " to #{args.range_max}: "
            puts exclude_list.join(',')
            proxmox.fetch_backup_jobs.each do |c|
              bjob_list = c['exclude'].split(',')
              unless (exclude_list - bjob_list).any?
                puts 'Nothing to exclude. All VMs in given range are in'\
                      ' current exclude list in backup job '\
                      "with id #{c['id']} and starttime #{c['starttime']}."
                next
              end
              puts 'Add following IDs to exclude list in backup job '\
                   "with id #{c['id']} and starttime #{c['starttime']}:"
              add_to_bjob = exclude_list - bjob_list
              puts add_to_bjob.join(',')
              new_settings = {
                starttime: c['starttime'],
                exclude: (exclude_list | bjob_list).join(',')
              }
              response = proxmox.update_backup_job(c['id'], new_settings)
              next if response.nil?
              if response.include? 'NOK: error code'
                raise "Update of Backup Job with id #{c['id']} "\
                      "failed: #{response}"
              else
                puts response
              end
            end
          end

          desc 'list proxmox backups'
          task 'backup:list', %i[vmid node storage] do |_t, args|
            args.with_defaults(storage: 'local')
            args.with_defaults(node: ENV['PROXMOX_NODE'])
            $stderr.puts "backup list vmid:#{args.vmid} #{args.storage}@"\
                           "#{args.node}:"
            proxmox.list_storage(args.node, args.storage).each do |c|
              # print " content:#{c['content']} volid:#{c['volid']}\n"
              filename_parts = c['volid'].split('/')[1].split('.')[0].split('-')
              next if filename_parts.count < 4
              next if filename_parts[1].empty?
              next unless filename_parts[1] <=> 'lxc' # must be lxc type
              # get vmid of backup
              file_vmid = filename_parts[2].to_i
              next unless file_vmid.to_s == filename_parts[2]
              next unless file_vmid == args.vmid.to_i
              print "#{c['volid']}\n"
            end
          end

          desc 'restore from vzdump [:vmid, :node'\
               " :storage => 'local',"\
               " :backup_storage => 'local',"\
               ' :file]'
          task 'backup:restore', %i[vmid
                                    node
                                    storage
                                    backup_storage
                                    file] do |_t, args|
            print "restore args: #{args}\n"
            id = args.vmid.to_i
            args.with_defaults(storage: 'local')
            args.with_defaults(backup_storage: 'local')
            unless lxc_restore(id, args.storage, args.backup_storage,
                               args.file, args.node)
              raise "failed to restore #{id} from "\
                      "#{args.storage}:#{args.file} to #{args.storage}\n"
            end
          end

          desc 'destroy all but exclude_ids (defaulting to: 6002) separated by'\
               ' colon(:)'
          task 'destroy:all', %i[exclude_ids delete_low_ids] do |t, args|
            args.with_defaults(exclude_ids: '6002')
            args.with_defaults(delete_low_ids: 'false')
            exclude_ids = args.exclude_ids.split(':').map(&:to_i)
            b = { 'true' => true,
                  true => true,
                  'false' => false,
                  false => false }
            low_ids = b[args.delete_low_ids.downcase]
            print "exclude_ids: #{exclude_ids}\n"

            return false unless lxc_status

            lxc_status.each do |id, prop|
              next if exclude_ids.include?(id.to_i)
              if !low_ids && id.to_i < 6000
                raise "not allowed to destroy id: #{id} < low_ids (6000)"\
                     " enable delete_low_ids deletion by executing \n"\
                     "# rake #{t}[#{args.exclude_ids},true]"
              end
              unless lxc_stop(id)
                raise "failed to stop #{id} (#{prop['name']})\n"
              end
              unless lxc_destroy(id)
                raise "failed to destroy #{id} (#{prop['name']})\n"
              end
            end
          end
          # create snapshot of every container
          desc 'snapshot all but exclude_ids (defaulting to: 6002) separated'\
               ' by colon(:)'
          task 'snapshot:create:all', %i[exclude_ids name desc] do |_t, args|
            args.with_defaults(exclude_ids: '6002')
            args.with_defaults(name: 'rakesnap1')
            args.with_defaults(desc: 'snapshot taken by rake task')
            exclude_ids = args.exclude_ids.split(':').map(&:to_i)
            print "exclude_ids: #{exclude_ids}\n"

            return false unless lxc_status

            lxc_status.each do |id, prop|
              next if exclude_ids.include?(id.to_i)
              unless lxc_snapshot(id, args.name, args.desc)
                raise "failed to snapshot #{id} (#{prop['name']})\n"
              end
            end
          end
          # delete all snapshots with specific name
          desc 'delete all snapshots with :name'
          task 'snapshot:delete:all', %i[exclude_ids name] do |_t, args|
            args.with_defaults(exclude_ids: '6002')
            args.with_defaults(name: 'rakesnap1')
            exclude_ids = args.exclude_ids.split(':').map(&:to_i)
            print "exclude_ids: #{exclude_ids}\n"

            return false unless lxc_status

            lxc_status.each do |id, prop|
              next if exclude_ids.include?(id.to_i)
              unless lxc_snapshot_delete(id, args.name)
                raise "failed to delete snapshot #{snap['name']} from #{id} "\
                     "(#{prop['name']})\n"
              end
            end
          end
          # add task for each lxc container
          lxc_status.each do |id, prop|
            desc "destroy #{prop['name']}"
            task "destroy:#{prop['name']}" do
              unless lxc_stop(id)
                raise "failed to stop #{id} (#{prop['name']})\n"
              end
              unless lxc_destroy(id)
                raise "failed to destroy #{id} (#{prop['name']})\n"
              end
            end
            desc "backup #{prop['name']} [:storage => 'local',"\
                 " :mode => 'snapshot']"
            task "backup:create:#{prop['name']}", %i[storage mode] do |_t, args|
              args.with_defaults(storage: 'local')
              args.with_defaults(mode: 'snapshot')
              unless lxc_backup(id, args.storage, args.mode)
                raise "failed to backup #{id} (#{prop['name']})\n"
              end
            end
            desc "restore #{prop['name']} [:storage => 'local',"\
                 ' :file]'
            task "backup:restore:#{prop['name']}", %i[storage
                                                      backup_storage
                                                      file] do |_t, args|
              args.with_defaults(storage: 'local')
              args.with_defaults(backup_storage: 'local')
              unless lxc_restore(id, args.storage, args.backup_storage,
                                 args.file)
                raise "failed to restore #{id} (#{prop['name']}) from "\
                        "#{args.storage}:#{args.file} to #{args.storage}\n"
              end
            end
            desc "snapshot #{prop['name']}"
            task "snapshot:create:#{prop['name']}", %i[name desc] do |_t, args|
              args.with_defaults(name: 'rakesnap1')
              args.with_defaults(desc: 'snapshot taken by rake task')
              unless lxc_snapshot(id, args.name, args.desc)
                raise "failed to snapshot #{id} (#{prop['name']})\n"
              end
            end
            lxc_snap_list = lxc_snapshot_list(id)
            next if lxc_snap_list == false
            lxc_snap_list.each do |snap|
              next unless snap.include?('name')
              next if snap['name'] == 'current'
              desc "snapshot #{snap['name']} from #{prop['name']} "\
                   "(#{snap['description'].tr("\n", ' ').gsub(/ $/, '')})"
              task "snapshot:delete:#{prop['name']}:#{snap['name']}"\
                do |_t, _args|
                unless lxc_snapshot_delete(id, snap['name'])
                  raise "failed to delete snapshot #{snap['name']} of #{id}"\
                       " (#{prop['name']})\n"
                end
              end
            end
          end
        end
      end
    end
  end
end
