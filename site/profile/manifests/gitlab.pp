# @summary Additional GitLab server configuration
#
# @example
#   include profile::gitlab
class profile::gitlab (
  Variant[
    String[1],
    Array[String[1]]
  ] $packages = [
    'jq',
    'python3-gitlab',
  ],
) {
  package { $packages:
    ensure => installed,
  }

  if defined(Class['epel']) and defined(Package['python3-gitlab']) {
    Class['epel'] -> Package['python3-gitlab']
  }
}
