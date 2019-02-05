# frozen_string_literal: true

def current_host_vars
  host_vars_path = attribute('host_vars_path',
                             default: nil,
                             description: 'An host_vars file path')

  host_vars = HOST_VARS / host_vars_path            # first try normal host_vars
  return host_vars if host_vars.exist?

  host_vars = KITCHEN_HOST_VARS / host_vars_path    # then kitchen playbooks one
  return host_vars if host_vars.exist?

  nil
end
