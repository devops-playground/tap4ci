# frozen_string_literal: true

def run_with_host_vars(&block)
  host_vars = current_host_vars

  return unless host_vars&.exist?

  vars = YAML.safe_load(host_vars.read, symbolize_names: true)

  puts "run_with_host_vars(host_vars: #{host_vars.inspect})"
  block.call(vars)
end
