# CLI Module
module Middleman::Cli
  # The CLI Build class
  class Build < Thor
    include Thor::Actions

    check_unknown_options!

    namespace :build

    desc 'build [options]', 'Builds the static site for deployment'
    method_option :environment,
                  aliases: '-e',
                  default: ENV['MM_ENV'] || ENV['RACK_ENV'] || 'production',
                  desc: 'The environment Middleman will run under'
    method_option :clean,
                  type: :boolean,
                  default: true,
                  desc: 'Remove orphaned files from build (--no-clean to disable)'
    method_option :glob,
                  type: :string,
                  aliases: '-g',
                  default: nil,
                  desc: 'Build a subset of the project'
    method_option :verbose,
                  type: :boolean,
                  default: false,
                  desc: 'Print debug messages'
    method_option :instrument,
                  type: :string,
                  default: false,
                  desc: 'Print instrument messages'
    method_option :profile,
                  type: :boolean,
                  default: false,
                  desc: 'Generate profiling report for the build'

    # Core build Thor command
    # @return [void]
    def build
      unless ENV['MM_ROOT']
        raise Thor::Error, 'Error: Could not find a Middleman project config, perhaps you are in the wrong folder?'
      end

      require 'middleman-core'
      require 'middleman-core/logger'
      require 'middleman-core/builder'
      require 'fileutils'

      env = options['environment'].to_sym
      verbose = options['verbose'] ? 0 : 1
      instrument = options['instrument']

      @app = ::Middleman::Application.new do
        config[:mode] = :build
        config[:environment] = env
        config[:show_exceptions] = false
        ::Middleman::Logger.singleton(verbose, instrument)
      end

      builder = Middleman::Builder.new(@app,
                                       glob: options['glob'],
                                       clean: options['clean'],
                                       parallel: options['parallel'])

      builder.on_build_event(&method(:on_event))

      if builder.run!
        clean_directories! if options['clean']
      else
        msg = 'There were errors during this build'
        unless options['verbose']
          msg << ', re-run with `middleman build --verbose` to see the full exception.'
        end
        shell.say msg, :red

        exit(1)
      end
    end

    # Tell Thor to send an exit status on a failure.
    def self.exit_on_failure?
      true
    end

    no_tasks do
      # Handles incoming events from the builder.
      # @param [Symbol] event_type The type of event.
      # @param [String] contents The event contents.
      # @param [String] extra The extra information.
      # @return [void]
      def on_event(event_type, target, extra=nil)
        case event_type
        when :error
          say_status :error, target, :red
          shell.say extra, :red if options['verbose']
        when :deleted
          say_status :remove, target, :green
        when :created
          say_status :create, target, :green
        when :identical
          say_status :identical, target, :blue
        when :updated
          say_status :updated, target, :yellow
        else
          say_status event_type, extra, :blue
        end
      end

      # Find empty directories in the build folder and remove them.
      # @return [Boolean]
      def clean_directories!
        all_build_files = File.join(@app.config[:build_dir], '**', '*')

        empty_directories = Dir[all_build_files].select do |d|
          File.directory?(d)
        end

        empty_directories.each do |d|
          remove_file d, force: true if Pathname(d).children.empty?
        end
      end
    end
  end

  # Alias "b" to "build"
  Base.map('b' => 'build')
end
