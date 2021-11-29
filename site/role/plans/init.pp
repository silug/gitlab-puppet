# @summary Build a Puppet server and attach agents
# @param puppet_release The major version of Puppet to use
# @param puppet_version The version of puppet-agent to install
# @param targets The targets to run on
# @param demo Use defaults for a demo environment
# @param control_repo URL of the control repo
# @param choria_user User name of the demo choria user on the Puppet server
# @param gitlab_package Locally cached gitlab-ce rpm
plan role (
  Integer          $puppet_release,
  Optional[String] $puppet_version = undef,
  TargetSpec       $targets        = 'all',
  Boolean          $demo           = false,
  Variant[
    Undef,
    Stdlib::HTTPUrl,
    Pattern[/\Afile:\/\/\/([^\n\/\0]+(\/)?)+\z/]
  ]                $control_repo   = undef,
  Optional[String] $choria_user    = $demo ? {
    true    => 'vagrant',
    default => undef,
  },
  Optional[String] $gitlab_package = undef,
) {
  # We want to specify the Puppet agent version to install,
  # so we start by running the puppet_agent::install task.
  $puppet_collection = "puppet${puppet_release}"
  $agent_install_message = $puppet_version ? {
    /^.+$/  => "Installing puppet-agent ${puppet_version}",
    default => "Installing ${puppet_collection}",
  }
  $agent_version = $puppet_version ? {
    /^.+$/  => { 'version' => $puppet_version },
    default => {},
  }
  $agent_install_args = {
    'collection' => $puppet_collection,
  } + $agent_version
  run_task('puppet_agent::install', $targets, $agent_install_message, $agent_install_args)

  # apply_prep will see that puppet-agent is already
  # installed and collect facts.
  apply_prep($targets)

  # Add a `role` fact based on the hostname if one isn't already set
  get_targets($targets).each |$target| {
    if $target.facts['role'] =~ Undef {
      case $target.facts['hostname'] {
        /^puppet/: {
          add_facts($target, { 'role' => 'puppet' })
        }
        /^gitlab/: {
          add_facts($target, { 'role' => 'gitlab' })
        }
        /^runner/: {
          add_facts($target, { 'role' => 'runner' })
        }
        default: {}
      }
    }
  }

  # Use the collected facts to build a hash of `host` resources.
  $hosts = get_targets($targets).reduce({}) |$memo, $target| {
    $this_host = {
      $target.facts['fqdn'] => {
        'ip' => $target.facts['networking']['interfaces'].reduce('') |$m, $v| {
          if $v[0] =~ /^e/ and $v[1]['ip'] {
            $v[1]['ip']
          } else {
            $m
          }
        },
        'host_aliases' => [
          $target.facts['hostname'],
        ],
      },
    }
    $memo + $this_host
  }

  # Use the hash to configure the hosts file and role fact on each target.
  apply($targets, '_description' => 'Configure hosts file') {
    $hosts.each |$key, $value| {
      host { $key:
        * => $value,
      }
    }

    if $facts['role'] {
      file { ['/etc/facter', '/etc/facter/facts.d']:
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
      }
      -> file { '/etc/facter/facts.d/role.txt':
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "role=${facts['role']}\n",
      }
    }
  }

  # Build a Hash of the defined roles
  $targets_with_role = get_targets($targets).reduce({}) |$memo, $target| {
    $role = $target.facts['role'].lest || { 'none' }

    $memo[$role].then |$r| {
      $memo + { $role => $r + [$target] }
    }.lest || {
      $memo + { $role => [$target] }
    }
  }

  # If there is a local gitlab-ce package, install it on the gitlab target(s)
  if !$gitlab_package.empty and file::exists($gitlab_package) {
    upload_file($gitlab_package, '/root', $targets_with_role['gitlab'])
    apply(
      $targets_with_role['gitlab'],
      '_description' => "Install cached GitLab package ${basename($gitlab_package)}",
    ) {
      package { 'gitlab-ce':
        ensure => installed,
        source => "/root/${basename($gitlab_package)}",
      }
    }
  }

  # Configure GitLab on the gitlab target(s)
  apply($targets_with_role['gitlab'], '_description' => 'Configure GitLab') {
    include role::gitlab
  }

  run_task('role::import_control_repo', $targets_with_role['gitlab'], 'Import the control repo')

  if $control_repo =~ Undef {
    $remote = "git@${$targets_with_role['gitlab'][0].facts['fqdn']}:puppet/control.git"

    $ssh_config = @("SSH_CONFIG"/L)
      Host ${$targets_with_role['gitlab'][0].facts['fqdn']}
        StrictHostKeyChecking no
      | SSH_CONFIG

    apply($targets_with_role['puppet'], '_description' => 'Generate ssh keys') {
      exec { 'ssh-keygen -f /root/.ssh/id_rsa -t rsa -b 4096 -N ""':
        path    => '/bin:/usr/bin',
        creates => '/root/.ssh/id_rsa.pub',
      }
      -> file { '/root/.ssh/config':
        ensure  => file,
        content => $ssh_config,
      }
    }
    download_file('/root/.ssh/id_rsa.pub', 'sshkeys', $targets_with_role['puppet'])
    $targets_with_role['puppet'].each |$target| {
      run_task(
        'role::add_deploy_key',
        $targets_with_role['gitlab'],
        "Add a deploy key for ${target}",
        'key' => file::read("${system::env('PWD')}/Boltdir/downloads/sshkeys/${target}/id_rsa.pub"),
      )
    }
  } else {
    $remote = $control_repo
  }

  # Bootstrap the runners, pass 1
  apply($targets_with_role['runner'], '_description' => 'Bootstrap GitLab CI runners (pass 1)') {
    include accounts
    include podman
  }

  # Bootstrap the runners, pass 2
  apply($targets_with_role['runner'], '_description' => 'Bootstrap GitLab CI runners (pass 2)') {
    include accounts
    include podman
    include systemd
  }

  # On the puppet server target, configure r10k.
  apply($targets_with_role['puppet'], '_description' => 'Configure r10k') {
    class { 'git': }
    -> class { 'r10k':
      remote => $remote,
    }
    -> exec { 'r10k deploy environment -pv':
      path    => '/opt/puppetlabs/bin:/bin:/usr/bin:/sbin:/usr/sbin',
      creates => '/etc/puppetlabs/code/environments/production/Puppetfile',
    }
  }

  # On the puppet server target, install and start the puppetserver.
  apply($targets_with_role['puppet'], '_description' => 'Install and start server components') {
    include puppetserver
    include profile::puppetserver::config
  }

  # Run the puppet agent to finish.
  run_command(
    'puppet agent -t -w 30 || { [ $? -eq 2 ] && true; };',
    $targets_with_role['puppet'],
    'First Puppet agent run',
    '_env_vars' => {
      'PATH' => '/opt/puppetlabs/bin:/bin:/usr/bin',
    },
  )

  if $choria_user {
    # Get the home directory of the choria user.
    $getent = run_command(
      "getent passwd ${choria_user}",
      $targets_with_role['puppet'],
      "Get information about user '${choria_user}'",
    )
    $home = $getent.ok_set.first.value['stdout'].split(':')[5]

    # Request a choria cert.
    apply(
      $targets_with_role['puppet'],
      '_description' => 'Request a choria cert',
    ) {
      exec { 'choria enroll':
        creates     => "${home}/.puppetlabs/etc/puppet/ssl/certs/${choria_user}.mcollective.pem",
        cwd         => $home,
        path        => ['/bin', '/usr/bin', '/opt/puppetlabs/bin'],
        user        => $choria_user,
        environment => [
          "HOME=${home}",
          "USER=${choria_user}",
        ],
      }
    }
  }

  # Run the puppet agent on the remaining targets.
  run_command(
    'puppet agent -t -w 30 || { [ $? -eq 2 ] && true; };',
    get_targets($targets) - get_targets($targets_with_role['puppet']),
    'First Puppet agent run',
    '_env_vars' => {
      'PATH' => '/opt/puppetlabs/bin:/bin:/usr/bin',
    },
  )
}
