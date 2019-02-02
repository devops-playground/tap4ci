require 'kitchen/driver/docker'
require 'pathname'

module Kitchen
  module Driver
    class Docker
      # https://github.com/test-kitchen/kitchen-docker/pull/294 [#1]
      default_config :build_tempdir, Dir.pwd

      def build_image(state)
        cmd = "build"
        cmd << " --no-cache" unless config[:use_cache]
        extra_build_options = config_to_options(config[:build_options])
        cmd << " #{extra_build_options}" unless extra_build_options.empty?
        dockerfile_contents = dockerfile
        build_context = config[:build_context] ? '.' : '-'
        # [#1]
        dockerfile_build_path = Pathname.pwd
        build_tempdir =  config[:build_tempdir]
        if build_tempdir
          dockerfile_build_path += build_tempdir
          logger.warn " ---> *** build_tempdir set (#{build_tempdir}) ***"
        end
        file = Tempfile.new('Dockerfile-kitchen', dockerfile_build_path)
        output = begin
          file.write(dockerfile)
          file.close
          docker_command("#{cmd} -f #{Shellwords.escape(dockerfile_path(file))} #{build_context}", :input => dockerfile_contents)
        ensure
          file.close unless file.closed?
          file.unlink
        end
        parse_image_id(output)
      end

      # Monkey patche [#1] fail if not here
      def dockerfile_path(file)
        config[:build_context] ? Pathname.new(file.path).relative_path_from(Pathname.pwd).to_s : file.path
      end
    end
  end
end
