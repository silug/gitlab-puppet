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
group_id=$( echo "$out" | jq -r .id )
group_runner_token=$( gitlab -o json group get --id "$group_id" | jq -r .runners_token )

# Create the /puppet/control project.
out=$( gitlab -o json project list | jq '.[] | select(.path_with_namespace == "puppet/control")' )
if [ -z "$out" ] ; then
    out=$( gitlab -o json project create --name control --namespace "$group_id" --visibility public )
    if [ "$?" -ne 0 ] ; then
        die "Failed to create /puppet/control project"
    fi
fi

# Import the puppet-deployment repo.
out=$( gitlab -o json project list | jq '.[] | select(.path_with_namespace == "puppet/puppet-deployment")' )
if [ -z "$out" ] ; then
    out=$( gitlab -o json project create --name puppet-deployment --namespace "$group_id" --visibility public --import-url https://github.com/silug/puppet-deployment.git )
    if [ "$?" -ne 0 ] ; then
        die "Failed to create /puppet/control project"
    fi
fi
project_id=$( echo "$out" | jq -r .id )
project_runner_token=$( gitlab -o json project get --id "$project_id" | jq -r .runners_token )

# Generate a random 20-character token for deployments.
if [ ! -f ~/.read_api_token ] ; then
    dd if=/dev/urandom bs=128 count=1 2>/dev/null | sha1sum | cut -c1-20 > ~/.read_api_token
fi

read_api_token="$( cat ~/.read_api_token )"

# Insert the token for read-only API access.
sudo gitlab-rails r "
  token = PersonalAccessToken.find_by_token('${read_api_token}')
  if token.nil?
    user = User.find_by_username('root')
    token = user.personal_access_tokens.create(scopes: Gitlab::Auth::all_available_scopes, name: 'Read-only token')
    token.set_token('${read_api_token}')
    token.save!
  end" || die "Failed to insert read_api access token"

# Set the GITLAB_API_TOKEN variable on the puppet-deployment project.
out=$( gitlab -o json project-variable list --project-id "$project_id" | jq '.[] | select(.key == "GITLAB_API_TOKEN")' )
if [ -z "$out" ] ; then
    # Note: We're using curl here because the gitlab command-line tool doesn't
    # know about "masked".
    out=$( curl -s --request POST \
        --header "PRIVATE-TOKEN: $token" \
        "http://$( hostname -f )/api/v4/projects/${project_id}/variables" \
        --form "key=GITLAB_API_TOKEN" \
        --form "value=$read_api_token" \
        --form "masked=true" )
    [ "$( echo "$out" | jq -r .key )" = GITLAB_API_TOKEN ] || die "Failed to add GITLAB_API_TOKEN variable"
fi

# Update the control repo with local CI configuration.
cd /vagrant
changes=()

#### FIXME: This block needs to be migrated to eyaml
#### or some kind of secrets management.

# Configure the group docker runners.
secret_file=data/roles/runner.d/secret.yaml
if [ ! -f "$secret_file" ] ; then
    mkdir -p "${secret_file%/*}"

    cat > "$secret_file" << END_GROUP_RUNNER
---
gitlab_ci_runner::runner_defaults:
  url: http://$( hostname -f )
  registration-token: "$group_runner_token"
  executor: docker
  docker:
    image: 'docker.io/library/ubuntu:trusty'
END_GROUP_RUNNER

    changes+=( "$secret_file" )
fi

# Configure the deployment project shell runner.
secret_file=data/roles/puppet.d/secret.yaml
if [ ! -f "$secret_file" ] ; then
    mkdir -p "${secret_file%/*}"

    cat > "$secret_file" << END_PROJECT_RUNNER
---
gitlab_ci_runner::runner_defaults:
  url: http://$( hostname -f )
  registration-token: "$project_runner_token"
  executor: shell
END_PROJECT_RUNNER

    changes+=( "$secret_file" )
fi

#### End FIXME.

if [ ! -f .gitlab-ci.yml ] ; then
    cat > .gitlab-ci.yml << 'END_GITLAB_CI_YML'
---
stages:
  - test
  - deploy

yamllint:
  stage: test
  image: docker.io/library/python:alpine
  script:
    - |
      pip install yamllint
      yamllint data site/*/data
  tags:
    - docker

deploy_environment:
  stage: deploy
  only:
    refs:
      - branches
  except:
    changes:
      - Puppetfile
  variables:
    PUPPET_DEPLOYMENT_TYPE: environment
    PUPPET_ENVIRONMENT: $CI_COMMIT_BRANCH
  trigger:
    project: puppet/puppet-deployment


deploy_environment_modules:
  stage: deploy
  only:
    refs:
      - branches
    changes:
      - Puppetfile
  variables:
    PUPPET_DEPLOYMENT_TYPE: environment_modules
    PUPPET_ENVIRONMENT: $CI_COMMIT_BRANCH
  trigger:
    project: puppet/puppet-deployment
END_GITLAB_CI_YML
    changes+=( .gitlab-ci.yml )
fi

if [ ${#changes[@]} -gt 0 ] ; then
    git add "${changes[@]}"
    GIT_AUTHOR_NAME='Import Bot' \
        GIT_COMMITTER_NAME='Import Bot' \
        GIT_AUTHOR_EMAIL=import-bot@$( hostname -f ) \
        GIT_COMMITTER_EMAIL=import-bot@$( hostname -f ) \
        git commit -m "Import site-specific changes to ${changes[*]}"
fi

# Push /vagrant to /puppet/control.
git remote set-url origin git@localhost:puppet/control.git
git push -u origin production
