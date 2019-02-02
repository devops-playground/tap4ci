# frozen_string_literal: true

Vagrant.configure(2) do |config|
  config.vm.provision(:shell,
                      privileged: true,
                      path: "#{__dir__}/provision_script.sh",
                      args: ENV['http_proxy'] || ENV['HTTP_PROXY'])

  # Val's local development bridge workarround
  # if `ip route list`.match?(%r{^[0-9./]+ dev br0 proto kernel src [0-9.]+$})
  if `ip route list` =~ %r{^[0-9./]+ dev br0 proto kernel src [0-9.]+$}
    config.vm.network(
      :public_network,
      dev: 'br0',
      mode: 'bridge',
      type: 'bridge'
    )
  end
end
