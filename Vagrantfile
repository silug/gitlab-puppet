# -*- mode: ruby -*-
# vi: set ft=ruby et st=2 sw=2 :
ENV['VAGRANT_EXPERIMENTAL'] = 'typed_triggers'

ip_subnet = ENV['IP_SUBNET'] || '192.168.32'
puppet_version = ENV['PUPPET_VERSION'] || ''
puppet_release = puppet_version.empty? ? (ENV['PUPPET_RELEASE'] || '7') : puppet_version.split('.').first
el_release = ENV['EL_RELEASE'] || '8'
box = ENV['BOX'] || "centos/#{el_release}"
gitlab_package = ENV['GITLAB_PACKAGE'] || Dir.glob("#{Dir.pwd}/gitlab-ce-*.rpm").last

Vagrant.configure('2') do |config|
  config.vm.box = box
  config.vm.synced_folder '.', '/vagrant', disabled: true

  config.vm.define 'puppet' do |puppet|
    %w[virtualbox libvirt].each do |provider|
      puppet.vm.provider provider do |p|
        p.memory = '3072'
        p.cpus = 2
        p.name = 'puppet.vagrant' if provider == 'virtualbox'
        p.qemu_use_session = false if provider == 'libvirt'
      end
    end

    puppet.vm.hostname = 'puppet.vagrant'
    puppet.vm.network 'private_network', ip: "#{ip_subnet}.5"
  end

  config.vm.define 'agent' do |agent|
    %w[virtualbox libvirt].each do |provider|
      agent.vm.provider provider do |p|
        p.name = 'agent.vagrant' if provider == 'virtualbox'
        p.qemu_use_session = false if provider == 'libvirt'
      end
    end

    agent.vm.hostname = 'agent.vagrant'
    agent.vm.network 'private_network', ip: "#{ip_subnet}.6"
  end

  config.vm.define 'gitlab' do |gitlab|
    gitlab.vm.network 'forwarded_port', guest: 80, host: 8080
    gitlab.vm.synced_folder '.', '/vagrant', disabled: false

    %w[libvirt virtualbox].each do |provider|
      gitlab.vm.provider provider do |p|
        p.memory = '6144'
        p.cpus = 2
        p.qemu_use_session = false if provider == 'libvirt'
        p.name = 'gitlab.vagrant' if provider == 'virtualbox'
      end
    end

    gitlab.vm.hostname = 'gitlab.vagrant'
    gitlab.vm.network 'private_network', ip: "#{ip_subnet}.10"
  end

  (1..2).each do |n|
    name = sprintf("runner%02d", n)
    config.vm.define name do |runner|
      %w[libvirt virtualbox].each do |provider|
        runner.vm.provider provider do |p|
          p.memory = '4096'
          p.cpus = 2
          p.qemu_use_session = false if provider == 'libvirt'
          p.name = "#{name}.vagrant" if provider == 'virtualbox'
        end
      end

      runner.vm.hostname = "#{name}.vagrant"
      runner.vm.network 'private_network', ip: "#{ip_subnet}.#{ 10 + n }"
    end
  end

  config.trigger.before [:up, :provision, :reload], type: :command do |trigger|
    trigger.info = 'Initializing bolt'
    trigger.run = { inline: 'bolt module install' }
  end

  config.trigger.after [:up, :provision, :reload], type: :command do |trigger|
    trigger.info = 'Running bolt plan'
    trigger.run = {
      inline: [
        'bolt plan run role -t all --run-as root',
        "puppet_release=#{puppet_release}",
        "puppet_version=#{puppet_version}",
        "demo=true",
        "gitlab_package=#{gitlab_package}",
      ].join(' ')
    }
  end
end
