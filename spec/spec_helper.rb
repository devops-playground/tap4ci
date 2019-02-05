# frozen_string_literal: true

require 'bundler/setup'
require 'pathname'

# Useful pathnames
SPEC = Pathname.new(__dir__).expand_path
ROOT = SPEC.dirname
NAME = ROOT.basename.to_s
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

$PROGRAM_NAME = "spec[#{NAME}]"
