# @summary GitLab role
#
# @example
#   include role::gitlab
class role::gitlab {
  include gitlab
  include git # For importing the control repo
  if $facts['os']['family'] == 'RedHat' and $facts['os']['name'] != 'Fedora' {
    include epel
  }
  include profile::gitlab
}
