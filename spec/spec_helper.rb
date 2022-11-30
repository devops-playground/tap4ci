# frozen_string_literal: true

require 'bundler/setup'
require 'pathname'

# Useful pathnames
SPEC = Pathname.new(__dir__).expand_path
ROOT = SPEC.dirname
NAME = ROOT.basename.to_s
$LOAD_PATH.unshift(ROOT / 'lib')
HOST_VARS = ROOT / 'host_vars'
FIXTURES = SPEC / 'fixtures'
KITCHEN = SPEC / 'kitchen'
SUPPORT = SPEC / 'support'
GNUPG = FIXTURES / 'gnupg'
PASSWORD_STORE = FIXTURES / 'password-store'
PLAYBOOKS = KITCHEN / 'playbooks'
KITCHEN_HOST_VARS = PLAYBOOKS / 'host_vars'

# Test-Kitchen provider (default: 'docker', available: 'vagrant')
KITCHEN_PROVIDER = ENV['KITCHEN_PROVIDER'] ||= 'docker'
# True if Test-kitchen run inside a (Docker) container
DOCKERIZED = KITCHEN_PROVIDER == 'docker'

# Override GnuPG home for tests
GNUPGHOME = ENV['GNUPGHOME'] = "/tmp/.#{NAME}_gnupg"
# Override Password-Store directory for tests
PASSWORD_STORE_DIR = ENV['PASSWORD_STORE_DIR'] = "/tmp/.#{NAME}_password-store"

# Load specification support files in alphabetical order
SUPPORT.glob('*.rb').sort.each { |support| require support }

# Remove SSH auth socket from Test-Kitchen environment
ENV.delete('SSH_AUTH_SOCK')

# Use shoulda syntax
require 'rspec'
RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
  config.raise_errors_for_deprecations!
end

# test-kitchen pre_converge lifecycle script
PRE_CONVERGE_SCRIPT = <<~EOSCRIPT.inspect
  if [ -d /tmp/.#{NAME}_password-store ]; then
    rm -rf /tmp/.#{NAME}_password-store ;
  fi ;
  if [ -d /tmp/.#{NAME}_gnupg ]; then
    rm -rf /tmp/.#{NAME}_gnupg ;
  fi ;
  cp -a #{PASSWORD_STORE} /tmp/.#{NAME}_password-store ;
  cp -a #{GNUPG} /tmp/.#{NAME}_gnupg ;
  printf \"\\n\\033[36;1m####### pre_converge done ########\\033[0m\\n\\n\"
EOSCRIPT

$PROGRAM_NAME = "spec[#{NAME}]"
