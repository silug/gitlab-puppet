# frozen_string_literal: true

require 'spec_helper'
require 'facter'
require 'facter/role__puppetserver__r10k_remote'

def r10k_yaml
  '/etc/puppetlabs/r10k/r10k.yaml'
end

def config
  {
    cachedir: '/opt/puppetlabs/puppet/cache/r10k',
    sources: {
      'puppet' => {
        'basedir' => '/etc/puppetlabs/code/environments',
        'remote'  => 'file:///vagrant/',
      },
    },
  }
end

describe :role__puppetserver__r10k_remote, type: :fact do
  subject(:fact) { Facter.fact(:role__puppetserver__r10k_remote) }

  before :each do
    Facter.clear

    allow(File).to receive(:exist?).and_call_original

    allow(YAML).to receive(:load_file).and_call_original
  end

  context 'on a non-Linux system' do
    before :each do
      allow(Facter.fact(:kernel)).to receive(:value).and_return('Darwin')
      allow(File).to receive(:exist?).with(r10k_yaml).and_return(true)
      allow(YAML).to receive(:load_file).with(r10k_yaml).and_return(config)
    end

    it 'returns nil' do
      expect(fact.value).to eq(nil)
    end
  end

  context 'on Linux with no r10k.yaml' do
    before :each do
      allow(Facter.fact(:kernel)).to receive(:value).and_return('Linux')
      allow(File).to receive(:exist?).with(r10k_yaml).and_return(false)
    end

    it 'returns nil' do
      expect(fact.value).to eq(nil)
    end
  end

  context 'on Linux with a r10k.yaml' do
    before :each do
      allow(Facter.fact(:kernel)).to receive(:value).and_return('Linux')
      allow(File).to receive(:exist?).with(r10k_yaml).and_return(true)
      allow(YAML).to receive(:load_file).with(r10k_yaml).and_return(config)
    end

    it 'returns the expected value' do
      expect(fact.value).to eq(config[:sources]['puppet']['remote'])
    end
  end
end
