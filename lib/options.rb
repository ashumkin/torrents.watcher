#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

require 'optparse'
require 'ostruct'
require 'logger'
require 'fileutils'
require File.expand_path('../../helpers/logger.rb', __FILE__)

module TorrentsWatcher

class Options < OpenStruct
  def files
    # remove trailing path separator
    return Dir[plugins.gsub(/\/$/, '') + '/' + plugins_mask]
  end
end # class Options

class CmdLineOptions < OptionParser
  attr_reader :options

  def initialize(args)
    super()
    @options = Options.new
    @script_name = 'torrents.watcher'
    @options.config_dir = ENV['HOME'] + '/.' + @script_name
    @options.plugins = File.expand_path('../../trackers.d/', __FILE__)
    @options.plugins_mask = '*.tracker'

    @options.list_trackers = false
    @options.relogin = false
    @options.sync = false
    @options.run = false
    @options.dry_run = false
    @options.levels = {}
    @options.def_levels = [:common, :run, :sync]
    @options.def_levels.each do |level|
      @options.levels[level] = Logger::INFO
    end
    @options.def_levels_joined  = @options.def_levels.join(',')
    init
    begin
      @args = args.dup
      @args_parsed = parse!(args)
    rescue ParseError
      warn $!
      Kernel::warn self
      exit!(1)
    return
    end
    init_configs
    validate
  end

  def cache
    return @options.cache
  end

  def lock_file
    return self.cache + '/.' + @script_name + '.lock'
  end

private
  def init_configs
    @options.config = @options.config_dir + '/.configrc' unless @options.config
    @options.cache = @options.config_dir + '/cache'
  end

  def validate
    # if there are non-options parameters
    # or there are no parameters at all
    # show usage
    if @args.empty? || !@args_parsed.empty?
      puts self
      exit(1)
    end
  end

  def set_log_level(category, value)
    if category
      category.map!{ |a| a.to_sym }
    else
      category = @options.def_levels
    end
    category.each do |level|
      @options.levels[level] = value
    end
  end

  def init
    separator ''
    separator 'Options:'

    on('-C', '--clean',
        'Clean up cache (remove *.torrent-files)') do |c|
      @options.cleanup = true
    end

    on('-c', '--config CONFIG',
        'Use configuration file CONFIG instead of ~/.torrents.watcher.rc') do |c|
      @options.config = c
    end

    on('-D', '--dir DIR', 'Directory of config and cache. Default is ~/.torrents.watcher/') do |d|
      @options.config_dir = d
    end

    on('-d', '--debug [' + @options.def_levels_joined + ']', Array, 'Debug mode. Print all messages',
        @options.def_levels_joined) do |l|
      set_log_level(l, Logger::DEBUG)
    end

    on('-x', '--extra-debug', 'Extra debug mode') do
      set_log_level([:common], Logger::EXTRA_DEBUG)
    end

    on('-l', '--list-trackers', 'List supported trackers') do
      @options.list_trackers = true
      set_log_level(nil, Logger::WARN)
    end

    on('-L', '--relogin', 'Relogin (clean cookies)') do
      @options.relogin = true
    end

    on('-n', '--dry-run', 'Dry run. Do not copy files (implies --sync)') do
      @options.dry_run = true
    end

    on('-r', '--run', 'Run fetching') do
      @options.run = true
    end

    on('-R', '--no-run', 'DO NOT fetching (can be used with --sync)') do
      @options.run = false
    end

    on('-s', '--sync FOLDER', 'Sync with transmission watch folder') do |f|
      @options.sync_folder = f
      @options.sync = true
    end

    on('-S', '--no-sync', 'DO NOT sync (can be used with --run)') do |f|
      @options.sync = false
    end

    on('-q', '--quiet [' + @options.def_levels_joined + ']', Array, 'Quiet mode', @options.def_levels_joined) do |q|
      set_log_level(q, Logger::ERROR)
    end

    on('-v', '--verbose [' + @options.def_levels_joined + ']', Array, 'Verbose mode', @options.def_levels_joined) do |q|
      set_log_level(q, Logger::INFO)
    end

    on_tail('-h', '--help', 'Show this help') do
      puts self
      exit
    end
  end
end # class TCmdLineOptions

end # module TorrentsWatcher

