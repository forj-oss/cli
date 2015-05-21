# encoding: UTF-8

# (c) Copyright 2014 Hewlett-Packard Development Company, L.P.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# Functions for test-box
class ForjCoreProcess
  # Function which detects the repository to send out to
  # the box
  #
  # * *Args*:
  #   - +params+   : ObjParams. Take care of following data
  #     - :test_box : Hash. Key is the repo, and
  #       value a full path to the local repo.
  #     - :test_box_path : full path to the test-box.sh script
  #     - :public_ip: Used for ssh connections
  #     - :keypairs: Used for ssh connections
  #   - +log_output+ : log string to parse.
  #
  # * *returns* :
  #   - nothing.
  #
  def tb_detect(hParams, log_output)
    return unless hParams[:test_box_path]
    tb_repos = hParams[:test_box]
    script = hParams[:test_box_path]

    # the server must wait with 4 last lines in server log:
    # [...] - forj-cli: tb-repo=maestro tb-dir=/opt/co[...] tb-root-repo=ma[...]
    # [...] - build.sh: test-box-repo=maestro
    # [...] - Test-box: Waiting for ~ubuntu/git/maestro.[...]
    # [...] - On your workstation, you can start test-b [...]

    re = /forj-cli: tb-repo=(.*) tb-dir=(.*) tb-root-repo=(.*)/
    res = log_output.split("\n")[-4].match(re)

    if res
      repo_dir = "--repo-dir #{res[2]} --root-repo #{res[3]}"
    else
      res = log_output.split("\n")[-3].match(/build.sh: test-box-repo=(.*)/)
      repo_dir = ''
    end
    return unless res && res[1] && tb_repos[res[1]]

    repo = res[1]

    test_box_dir = tb_repos[repo]

    PrcLib.info('test-box: your box is waiting for a test-box repository. '\
                'One moment.')

    # TODO : Add tb_ensure_ssh_config task to set this server in ~/.ssh/config.
    # unless tb_ensure_ssh_config(hParams)
    #  PrcLib.info('test-box: Unable to configure ssh config with this server.'\
    #               ' You needs to do it yourself manually. Remote box boot '\
    #               "process is waiting for #{test_box_dir}")
    #   return
    # end
    PrcLib.warning('test-box: ssh config is currently not managed. You may '\
                   'need to configure it yourself, otherwise test-box may fail')

    pubip = hParams[:public_ip, :public_ip]
    user = hParams[:image, :ssh_user]
    # TODO: Implement testing branch warning. See build.sh lines 618 -> 632
    cmd = <<-CMD
cd #{test_box_dir}
if [ "$(git branch | grep 'testing-larsonsh-#{user}@#{pubip}')" != "" ]
then
   #{script} --remove-from #{user}@#{pubip} --repo #{repo} #{repo_dir}
fi
#{script} --push-to #{user}@#{pubip} --repo #{repo} #{repo_dir}
    CMD
    PrcLib.info "Running following shell instructions:\n#{cmd}"

    return if system(cmd)

    PrcLib.error('Unable to run test-box.sh successfully. You need to run it'\
                 ' yourself manually, now.')
    loop do
      break if ask("When you are done, type 'DONE'") == 'DONE'
    end
  end

  # def tb_ensure_ssh_config(hParams)
  #   pubip = hParams[:public_ip, :name]
  #   user = hParams[:image, :ssh_user]
  #
  #   ssh_config = Net::SSH::Config.new
  # end

  # function to add extra meta data to support test-box
  #
  # * *Args*:
  #   - metadata : Hash. Hash structure to update.
  #
  # * * returns*:
  #   - nothing
  def tb_metadata(hParams, metadata)
    #   META['test-box']="test-box=$REPO_TO_ADD;testing-$(id -un)"
    # else
    #   META['test-box']="${META['test-box']}|$REPO_TO_ADD;testing-$(id -un)"
    return unless hParams.exist?(:test_box_path)

    meta_str = `echo "testing-$(id -un)"`.split[0]
    res = []
    hParams[:test_box].each_key { |k| res << format('%s;%s', k, meta_str) }
    metadata['test-box'] = res.join('|')
  end
end
