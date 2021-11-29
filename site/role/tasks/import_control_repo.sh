#!/bin/bash

warn() {
    echo "$@" >&2
}

die() {
    warn "$@"
    exit 1
}

set -e

umask 077

# Create a ssh keypair.
[ -f ~/.ssh/id_rsa ] || ssh-keygen -N '' -f ~/.ssh/id_rsa

# Configure ssh to localhost.
[ -f ~/.ssh/config ] || cat > ~/.ssh/config <<END_CONFIG
Host localhost
  StrictHostKeyChecking no
END_CONFIG

# Generate a random 20-character token for root.
if [ ! -f ~/.root_token ] ; then
    dd if=/dev/urandom bs=128 count=1 2>/dev/null | sha1sum | cut -c1-20 > ~/.root_token
fi

token="$( cat ~/.root_token )"

# Insert the root access token for API access.
sudo gitlab-rails r "
  token = PersonalAccessToken.find_by_token('${token}')
  if token.nil?
    user = User.find_by_username('root')
    token = user.personal_access_tokens.create(scopes: Gitlab::Auth::all_available_scopes, name: 'Automation token')
    token.set_token('${token}')
    token.save!
  end" || die "Failed to insert root access token"

# Configure the gitlab command-line utility.
[ -f ~/.python-gitlab.cfg ] || cat > ~/.python-gitlab.cfg <<END
[global]
default = local-root
ssl_verify = false

[local-root]
url = http://localhost
private_token = ${token}
END

# Add the generated ssh key to the root user.
my_id=$( gitlab -o json user list | jq -r '.[] | select(.username == "root") | .id' )
if [ -z "$( gitlab -o json user-key list --user-id 1 | jq '.[] | select((.key | split(" ") | .[1]) == "'$( awk '{print $2}' ~/.ssh/id_rsa.pub )'")' )" ] ; then
    gitlab user-key create \
        --user-id "$my_id" \
        --title 'Local root' \
        --key "$( cat ~/.ssh/id_rsa.pub )" \
        || die "Failed to add the root ssh key"

    # Force a rebuild of authorized_keys.
    echo 'yes' | sudo gitlab-rake gitlab:shell:setup
fi

# Create a top-level /puppet group.
out=$( gitlab -o json group list | jq '.[] | select(.name == "puppet")' )
if [ -z "$out" ] ; then
    out=$( gitlab -o json group create --name puppet --path puppet --visibility public )
    if [ "$?" -ne 0 ] ; then
        die "Failed to create /puppet group"
    fi
fi
id=$( echo "$out" | jq -r .id )

# Create the /puppet/control project.
out=$( gitlab -o json project list | jq '.[] | select(.path_with_namespace == "puppet/control")' )
if [ -z "$out" ] ; then
    out=$( gitlab -o json project create --name control --namespace "$id" --visibility public )
    if [ "$?" -ne 0 ] ; then
        die "Failed to create /puppet/control project"
    fi
fi

# Push /vagrant to /puppet/control.
cd /vagrant
git remote set-url origin git@localhost:puppet/control.git
git push -u origin production
