# frozen_string_literal: true

run_with_host_vars do |vars|
  vars.dig(:password_store, :push)&.tap do |push|
    push.each do |entry|
      describe file(entry[:dest]) do
        it { should exist }
        it { should be_file }
        it { should be_mode(Integer(entry[:mode] || '0600',8)) }
        it { should be_owned_by(entry[:owner] || 'root') }
        it { should be_grouped_into(entry[:group] || 'root') }
        its('content') do
          cmd = %W[
            GNUPGHOME=#{GNUPGHOME}
            PASSWORD_STORE_DIR=#{PASSWORD_STORE_DIR}
            pass #{entry[:src]}
          ].join(' ')

          should eq `#{cmd}`.chomp
        end
      end
    end
  end
end
