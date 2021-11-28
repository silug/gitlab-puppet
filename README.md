# gitlab-puppet
## Bootstrap a Puppet + GitLab environment

This repo contains a Vagrantfile and a Bolt plan that will build a GitLab
server, GitLab runners (with the Docker executor configured to use rootless
`podman`), and a Puppet server with the following configured out of the box:
* [r10k](https://forge.puppet.com/puppet/r10k) (with this repo as its control repo)
* [Choria](http://choria.io/)
* [PuppetDB](https://puppet.com/docs/puppetdb/)

## Prerequisites

In order to use this project, you'll need
[Vagrant](https://vagrantup.com/) and
[Bolt](https://puppet.com/docs/bolt/latest/bolt.html) installed.

### Configuring

The following environment variables are used to configure the Vagrant environment:

| Environment variable | Default value                    | Description                                    |
| -------------------- | -------------                    | -----------                                    |
| `IP_SUBNET`          | `192.168.32`                     | The internal IP subnet used by Vagrant         |
| `PUPPET_VERSION`     | none (use the latest)            | The Puppet agent version                       |
| `PUPPET_RELEASE`     | `7`                              | The Puppet major release version               |
| `EL_RELEASE`         | `8`                              | The EL release of the base box                 |
| `BOX`                | `centos/${EL_RELEASE}`           | The base box name                              |
| `GITLAB_PACKAGE`     | `gitlab-ce-*.rpm` (if it exists) | The name of a locally-cached GitLab CE package |

## See also

For a simpler Puppet server/agent configuration, see
[basic-aio](https://github.com/puppet-bootstrap/basic-aio).
To get started with just an agent, take a look at
[sandbox](https://github.com/puppet-bootstrap/sandbox).  For a simple control
repo example, see
[minimal-control](https://github.com/puppet-bootstrap/minimal-control).
