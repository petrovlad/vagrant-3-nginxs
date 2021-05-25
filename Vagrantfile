NETWORK_BASE = "192.168.56."
WORKSTATION_IP_HOST = 1
VM_IP_HOST = 10
Vagrant.configure("2") do |config|

  config.vm.box = "sbeliakou/centos"

  # loadbalancer config
  # ip: .10
  config.vm.define "nginx-loadbalancer" do |subconfig|
    subconfig.vm.network "private_network", ip: "#{NETWORK_BASE}#{VM_IP_HOST}"
    subconfig.vm.hostname = "nginx-server"
    subconfig.vm.provision "shell", path: "lb_provision.sh", args: "#{NETWORK_BASE}#{VM_IP_HOST + 1} #{NETWORK_BASE}#{VM_IP_HOST + 2}"

    subconfig.vm.provider "virtualbox" do |vb|
      vb.name = "Vagrant-NGINX-LB"
      vb.memory = "512"
    end
  end

  # backend servers config
  # ip's: .11, .12
  nginx_dict = { 1 => "nginx-backend1", 2 => "nginx-backend2"}
  (1..2).each do |i|
    config.vm.define nginx_dict[i] do |subconfig|
      subconfig.vm.network "private_network", ip: "#{NETWORK_BASE}#{VM_IP_HOST + i}"
      subconfig.vm.hostname = nginx_dict[i]
      subconfig.vm.provision 'shell', path: "backend_provision.sh", args: "#{i} #{NETWORK_BASE}#{WORKSTATION_IP_HOST}"
      subconfig.vm.provider "virtualbox" do |vb|
        vb.name = "Vagrant-NGINX-BACKEND#{i}"
        vb.memory = "512"
      end
    end
  end
end
