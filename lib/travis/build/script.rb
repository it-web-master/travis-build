require 'erb'
require 'core_ext/hash/deep_merge'
require 'core_ext/hash/deep_symbolize_keys'
require 'core_ext/object/false'

module Travis
  module Build
    class Script
      autoload :Addons,         'travis/build/script/addons'
      autoload :Android,        'travis/build/script/langs/android'
      autoload :C,              'travis/build/script/langs/c'
      autoload :Cpp,            'travis/build/script/langs/cpp'
      autoload :Clojure,        'travis/build/script/langs/clojure'
      autoload :Dsl,            'travis/build/script/dsl'
      autoload :Erlang,         'travis/build/script/langs/erlang'
      autoload :Go,             'travis/build/script/langs/go'
      autoload :Groovy,         'travis/build/script/langs/groovy'
      autoload :Haskell,        'travis/build/script/langs/haskell'
      autoload :Helpers,        'travis/build/script/helpers'
      autoload :NodeJs,         'travis/build/script/langs/node_js'
      autoload :ObjectiveC,     'travis/build/script/langs/objective_c'
      autoload :Perl,           'travis/build/script/langs/perl'
      autoload :Php,            'travis/build/script/langs/php'
      autoload :PureJava,       'travis/build/script/langs/pure_java'
      autoload :Python,         'travis/build/script/langs/python'
      autoload :Ruby,           'travis/build/script/langs/ruby'
      autoload :Scala,          'travis/build/script/langs/scala'
      autoload :DirectoryCache, 'travis/build/script/shared/directory_cache'
      autoload :Git,            'travis/build/script/shared/git'
      autoload :Jdk,            'travis/build/script/shared/jdk'
      autoload :Jvm,            'travis/build/script/shared/jvm'
      autoload :RVM,            'travis/build/script/shared/rvm'
      autoload :Services,       'travis/build/script/services'
      autoload :Stages,         'travis/build/script/stages'

      TEMPLATES_PATH = File.expand_path('../script/templates', __FILE__)

      STAGES = {
        builtin: [:configure, :checkout, :pre_setup, :paranoid_mode, :export, :setup, :announce],
        custom:  [:before_install, :install, :before_script, :script, :after_result, :after_script]
      }

      class << self
        def defaults
          Git::DEFAULTS.merge(self::DEFAULTS)
        end
      end

      include Addons, Git, Helpers, Services, Stages, DirectoryCache

      attr_reader :stack, :data, :options

      def initialize(data, options = {})
        @stack = []
        @data = Data.new({ config: self.class.defaults }.deep_merge(data.deep_symbolize_keys))
        @options = options

        stack << AstProxy.new(stack, Shell::Ast::Script.new)
        run_stages if check_config
      end

      def compile
        code = [template('header.sh')]
        code << Shell.generate(sexp)
        code << template('footer.sh')
        code.join("\n")
      end

      def sexp
        sh.to_sexp
      end

      def cache_slug
        "cache"
      end

      private

        def check_config
          case data.config[:".result"]
          when 'not_found'
            echo 'Could not find .travis.yml, using standard configuration.', ansi: :red
            true
          when 'server_error'
            echo 'Could not fetch .travis.yml from GitHub.', ansi: :red
            cmd 'travis_terminate 2', timing: false
            false
          else
            true
          end
        end

        def config
          data.config
        end

        def configure
          fix_resolv_conf unless data.skip_resolv_updates?
          fix_etc_hosts   unless data.skip_etc_hosts_fix?
        end

        def export
          set 'TRAVIS', 'true', echo: false
          set 'CI', 'true', echo: false
          set 'CONTINUOUS_INTEGRATION', 'true', echo: false
          set 'HAS_JOSH_K_SEAL_OF_APPROVAL', 'true', echo: false

          newline if data.env_vars_groups.any?(&:announce?)

          data.env_vars_groups.each do |group|
            echo "Setting environment variables from #{group.source}", ansi: :green if group.announce?
            group.vars.each { |var| set var.key, var.value, echo: var.echo?, secure: var.secure? }
          end

          newline if data.env_vars_groups.any?(&:announce?)
        end

        def finish
          push_directory_cache
        end

        def pre_setup
          start_services
          setup_apt_cache if data.cache? :apt
          fix_ps4
          run_addons(:after_pre_setup)
        end

        def setup
          setup_directory_cache
        end

        def announce
          # overwrite
        end

        def template(filename)
          ERB.new(File.read(File.expand_path(filename, TEMPLATES_PATH))).result(binding)
        end

        def paranoid_mode
          if data.paranoid_mode?
            newline
            echo "Sudo, services, addons, setuid and setgid have been disabled.", ansi: :green
            newline
            cmd 'sudo -n sh -c "sed -e \'s/^%.*//\' -i.bak /etc/sudoers && rm -f /etc/sudoers.d/travis && find / -perm -4000 -exec chmod a-s {} \; 2>/dev/null"', timing: false
          end
        end

        def setup_apt_cache
          if data.hosts && data.hosts[:apt_cache]
            echo 'Setting up APT cache', ansi: :green
            cmd %(echo 'Acquire::http { Proxy "#{data.hosts[:apt_cache]}"; };' | sudo tee /etc/apt/apt.conf.d/01proxy &> /dev/null), timing: false
          end
        end

        def fix_resolv_conf
          cmd %(grep '199.91.168' /etc/resolv.conf > /dev/null || echo 'nameserver 199.91.168.70\nnameserver 199.91.168.71' | sudo tee /etc/resolv.conf &> /dev/null), timing: false
        end

        def fix_etc_hosts
          cmd %(sudo sed -e 's/^\\(127\\.0\\.0\\.1.*\\)$/\\1 '`hostname`'/' -i'.bak' /etc/hosts), timing: false
          cmd %(sudo bash -c 'echo "87.98.253.108 getcomposer.org" >> /etc/hosts'), timing: false
        end

        def fix_ps4
          set "PS4", "+ "
        end
    end
  end
end
