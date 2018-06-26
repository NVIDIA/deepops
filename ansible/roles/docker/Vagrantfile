# -*- mode: ruby -*-
# vi: set ft=ruby ts=2 sw=2 tw=0 et :

role = File.basename(File.expand_path(File.dirname(__FILE__)))

ENV['ANSIBLE_ROLES_PATH'] = "../"

boxes = [
  {
    :name => "ubuntu-1404",
    :box => "ubuntu/trusty64",
    :ip => '10.0.77.12',
    :cpu => "20",
    :ram => "256"
  },
  {
    :name => "ubuntu-1604",
    :box => "ubuntu/xenial64",
    :ip => '10.0.77.13',
    :cpu => "20",
    :ram => "512"
  },
  {
    :name => "debian-jessie",
    :box => "debian/jessie64",
    :ip => '10.0.77.14',
    :cpu => "20",
    :ram => "256"
  },
  {
    :name => "debian-stretch",
    :box => "debian/stretch64",
    :ip => '10.0.77.16',
    :cpu => "20",
    :ram => "256"
  },
  {
    :name => "ubuntu-1604-python3",
    :box => "ubuntu/xenial64",
    :ip => '10.0.77.15',
    :cpu => "20",
    :ram => "512"
  },
]

Vagrant.configure("2") do |config|
  boxes.each do |box|
    config.vm.define box[:name] do |vms|
      vms.vm.box = box[:box]
      vms.vm.box_url = box[:url]

      vms.vm.provider "virtualbox" do |v|
        v.customize ["modifyvm", :id, "--cpuexecutioncap", box[:cpu]]
        v.customize ["modifyvm", :id, "--memory", box[:ram]]
      end

      vms.vm.network :private_network, ip: box[:ip]

      vms.vm.provision :ansible do |ansible|
        ansible.playbook = "tests/vagrant.yml"
        ansible.verbose = "vv"
        ansible.host_vars = {
          "ubuntu-1604-python3" => {
            "ansible_python_interpreter" => "/usr/bin/python3",
            # "ansible_user" => "ubuntu"
          }
        }
        ansible.raw_arguments  = [
          "--diff",
        ]
      end
    end
  end
end
