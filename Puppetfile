forge "https://forge.puppet.com/"

# stdlib is required by many other modules.
mod 'puppetlabs-stdlib', '8.1.0'

# Manages the puppetserver package and service.
mod 'puppet-puppetserver', '3.0.1'

# puppetdb is needed in order to use exported resources.
mod 'puppetlabs-puppetdb', '7.9.0'

# These modules are all dependencies for puppetdb.
mod 'puppetlabs-inifile', '5.2.0'
mod 'puppetlabs-postgresql', '7.5.0'
mod 'puppetlabs-apt', '8.3.0'
mod 'puppetlabs-concat', '7.1.1'
mod 'puppetlabs-firewall', '3.2.0'

# r10k gives us dynamic Puppet environments.
mod 'puppet-r10k', '10.1.1'

# These modules are all dependencies for r10k.
mod 'puppetlabs-ruby', '1.0.1' # Required by puppet-r10k
mod 'puppetlabs-vcsrepo', '5.0.0' # Required by puppet-r10k
mod 'puppetlabs-git', '0.5.0' # Required by puppet-r10k

# Enables the EPEL repository on RHEL/CentOS.
mod 'puppet-epel', '4.0.0'

mod 'puppetlabs-puppetserver_gem', '1.1.1' # Required for eyaml.
mod 'puppetlabs-translate', '2.2.0' # Required by puppetlabs-apt
mod 'herculesteam-augeasproviders_core', '3.1.0' # Required by puppet-puppetserver
mod 'camptocamp-augeas', '1.9.0' # Required by puppet-puppetserver

# mcollective with NATS as message queue
mod 'choria-mcollective', '0.13.4'
mod 'choria-mcollective_agent_puppet', '2.4.1'
mod 'choria-mcollective_agent_package', '5.3.0'
mod 'choria-mcollective_agent_service', '4.0.1'
mod 'choria-mcollective_agent_filemgr', '2.0.1'
mod 'choria-mcollective_util_actionpolicy', '3.2.0'
mod 'choria-mcollective_choria', '0.21.2'
mod 'choria-choria', '0.26.2'

mod 'puppet-systemd', '3.5.1'
mod 'puppetlabs-augeas_core', '1.2.0' # Required by puppet-puppetserver, camptocamp-augeas
mod 'puppet-gitlab', '8.0.0'
mod 'puppet-gitlab_ci_runner', '4.1.0'
mod 'puppetlabs-accounts', '7.1.1'
mod 'southalc-podman', '0.5.2'
mod 'saz-sudo', '7.0.2'
mod 'puppetlabs-selinux_core', '1.2.0' # Required by southalc-podman
