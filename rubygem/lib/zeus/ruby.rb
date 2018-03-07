ROOT_PATH = File.expand_path(Dir.pwd)
require 'bundler'
require 'zeus'
require 'zeus/m'
require 'zeus/plan'

### This is a pretty sloppy copy/paste job for now to see whether it works.
### Most stuff here comes from rails.rb, and has been trimmed down to serve
### as a base plan for anything that does not require Rails. The common
### stuff should be extracted, or the Rails plan should inherit from Ruby.

def gem_is_bundled?(gem)
  gemfile_lock_contents = File.read(ROOT_PATH + "/Gemfile.lock")
  gemfile_lock_contents.scan(/^\s*#{gem} \(([^=~><]+?)\)/).flatten.first
end

if version = gem_is_bundled?('method_source')
  gem 'method_source', version
end

module Zeus
  class Ruby < Plan
    def boot
      _monkeypatch_rake
      $LOAD_PATH.unshift "./lib"
    end

    def _monkeypatch_rake
      if version = gem_is_bundled?('rake')
        gem 'rake', version
      end
      require 'rake/testtask'
      Rake::TestTask.class_eval {

        # Create the tasks defined by this task lib.
        def define
          desc "Run tests" + (@name==:test ? "" : " for #{@name}")
          task @name do
            rubyopt = ENV['RUBYOPT']
            ENV['RUBYOPT'] = nil # bundler sets this to require bundler :|
            puts "zeus test #{file_list_string}"
            ret = system "zeus test #{file_list_string}"
            ENV['RUBYOPT'] = rubyopt
            ret
          end
          self
        end

        alias_method :_original_define, :define

        def self.inherited(klass)
          return unless klass.name == "TestTaskWithoutDescription"
          klass.class_eval {
            def self.method_added(sym)
              class_eval do
                if !@rails_hack_reversed
                  @rails_hack_reversed = true
                  alias_method :define, :_original_define
                  def desc(*)
                  end
                end
              end
            end
          }
        end
      }
    end

    def after_fork
    end

    def prerake
      require 'rake'
    end

    def rake
      Rake.application.run
    end

    def default_bundle
      Bundler.require(:default)
      Zeus::LoadTracking.add_feature('./Gemfile.lock')
    end

    def development_environment
      Bundler.require(:development)
    end

    def test_environment
      Bundler.require(:default, :development, :test)
      $LOAD_PATH.unshift ".", "./lib", "./test", "./spec"
    end

    def test_helper
      if File.exists?(ROOT_PATH + "/spec/spec_helper.rb")
        # RSpec < 3.0
        require 'spec_helper'
      elsif File.exists?(ROOT_PATH + "/test/minitest_helper.rb")
        require 'minitest_helper'
      else
        require 'test_helper'
      end
    end

    def test(argv=ARGV)
      # if there are two test frameworks and one of them is RSpec,
      # then "zeus test/rspec/testrb" without arguments runs the
      # RSpec suite by default.
      if using_rspec?(argv)
        RSpec.configuration.start_time = Time.now
        ARGV.replace(argv)
        # if no directory is given, run the default spec directory
        argv << "spec" if argv.empty?
        if RSpec::Core::Runner.respond_to?(:invoke)
          RSpec::Core::Runner.invoke
        else
          RSpec::Core::Runner.run(argv)
        end
      else
        require 'minitest/autorun' if using_minitest?
        # Minitest and old Test::Unit
        Zeus::M.run(argv)
      end
    end

    def using_rspec?(argv)
      defined?(RSpec) && (argv.empty? || spec_file?(argv))
    end

    def using_minitest?
      defined?(:MiniTest) || defined?(:Minitest)
    end

    SPEC_DIR_REGEXP = %r"(^|/)spec"
    SPEC_FILE_REGEXP = /.+_spec\.rb$/

    def spec_file?(argv)
      argv.any? do |arg|
        arg.match(Regexp.union(SPEC_DIR_REGEXP, SPEC_FILE_REGEXP))
      end
    end
  end
end
