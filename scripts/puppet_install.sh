#!/bin/bash

set -e

# Bootstrap the puppet module configuration
# Source the profile to get the path
. /etc/profile.d/puppet-agent.sh
puppet module install puppet/r10k
puppet apply /vagrant/bootstrap.pp
puppet apply /etc/puppetlabs/code/environments/production/manifests/site.pp

# If puppet successfully applied changes, it returns 2.
# Vagrant sees a non-zero return code as a failure. If puppet returns 2,
# return a zero so vagrant doesn't report an error
puppet agent -t --waitforcert || [ $? -eq 2 ] && /bin/true

su -- vagrant -c 'mco choria request_cert'
