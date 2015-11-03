#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

=begin
=end

require 'logger'
require 'fileutils'
require File.expand_path('../tracker.rb', __FILE__)
require File.expand_path('../../helpers/logger.rb', __FILE__)

module TorrentsWatcher

class TrackerList < ::Array
  attr_reader :opts, :logins

  def initialize(owner, opts)
    super()
    @owner = owner
    @opts = opts
    FileUtils.mkdir_p(@opts.options.config_dir)
    file = @opts.options.config
    @valid, @logins = Tracker.read_config_file(file, self, 'Reading config file %s')
    unless @valid
      if @valid.nil?
        log(Logger::ERROR, "Config #{file} is absent")
      else
        log(Logger::WARN, "WARNING! Config #{file} is not valid")
      end
    end
    dump_config(@logins)
    read
  end

  def list
    self.each do |tracker|
      puts tracker.name
    end
  end

  def log(severity, msg)
    @owner.log(severity, msg)
  end

  def log_separator(header, char = '>')
    @owner.log_separator(header, char)
  end

  def run
    return unless @valid
    log_separator('RUN: BEGIN')

    self.each do |tracker|
      tracker.run
    end
    log_separator('RUN: END', '<')
  end

  def find_tracker(name)
    self.each do |t|
      return t if t.name === name
    end
  end

private
  def read
    @opts.options.files.each do |file|
      self << Tracker.new(self, file)
    end
  end

  def dump_config(file)
    log(Logger::EXTRA_DEBUG, file.inspect)
  end
end # class TrackerList

end # module TorrentsWatcher

