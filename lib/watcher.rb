#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

require 'logger'
require 'fileutils'
require File.expand_path('../chdir.rb', __FILE__)
require File.expand_path('../options.rb', __FILE__)
require File.expand_path('../tracker.rb', __FILE__)
require File.expand_path('../trackerlist.rb', __FILE__)
require File.expand_path('../version.rb', __FILE__)

module TorrentsWatcher

class Watcher
  def initialize(appname, opts)
    @opts = opts
    @logger = Logger.new(STDOUT)
    @logger.level = @opts.options.levels[:common]
    log_separator(appname + ' version ' + VERSION)
    log_separator('BEGIN', '-')
    @trackers = TrackerList.new(self, @opts)
  end

  def log(severity, msg)
    @logger.log(severity, msg)
  end

  def log_separator(header, char = '>', count = 10)
    s = char.to_s * count
    if header
      s = "#{s} #{header} #{s}"
    end
    log(Logger::INFO, s)
  end

  def run
    begin
      Signal.trap("HUP") do
        $stderr.puts "#{$$}: I'm working"
      end
    if @opts.options.list_trackers
      list
      return
    end
    @logger.level = @opts.options.levels[:common]
    unless check_lock
      log(Logger::ERROR, @opts.lock_file + ' exists. Remove it if you`re sure another instance is not running. Exiting')
      return
    end
    set_lock
    begin
      if @opts.options.cleanup
        cleanup
      else
        @logger.level = @opts.options.levels[:run]
        @trackers.run if @opts.options.run
        @logger.level = @opts.options.levels[:sync]
        sync(@opts.options.sync_folder) if @opts.options.sync
      end
    ensure
      @logger.level = @opts.options.levels[:common]
      remove_lock
    end
    ensure
      log_separator('END', '-')
    end
  end

private
  def check_lock
    return true unless File.exists?(@opts.lock_file)
    log(Logger::DEBUG, @opts.lock_file + ' file exists')
    File.open(@opts.lock_file, 'r') do |f|
      pid = f.gets
      # if file is not empty
      pid.chomp! if pid
      log(Logger::DEBUG, 'PID is equal to ' + pid.to_s)
      begin
        r = Process.kill("HUP", pid.to_i) if pid.to_i > 0
      rescue Errno::ESRCH
        # no such process ID
        r = 0
      rescue
        r = -1
      end
      log(Logger::DEBUG, 'KILL result = ' + r.to_s)
      return r == 0
    end
  end

  def list
    @trackers.list
  end

  def remove_lock
    log(Logger::DEBUG, 'Removing .lock file: ' + @opts.lock_file)
    File.unlink(@opts.lock_file)
  end

  def set_lock
    # simple "touch" equivalent
    log(Logger::DEBUG, 'Setting .lock file: ' + @opts.lock_file)
    File.open(@opts.lock_file, 'w') do |f|
      f.write($$)
    end
  end

  def cleanup
    log_separator('CLEANUP: BEGIN')
    Dir["#{@opts.cache}/*.torrent", "#{@opts.cache}/*.notify"].sort.each do |t|
      s = 'Dry run. ' if @opts.options.dry_run
      log(Logger::INFO, "#{s.to_s}Removing #{t}")
      unless @opts.options.dry_run
        File.unlink(t)
      end
    end
    log_separator('CLEANUP: END', '<')
  end

  def file_exists?(filename)
    ['.loaded', '.added', ''].each do |ext|
      # .loaded, .added extensions are for those transmission servers
      # that add such extensions for already loaded torrent files
      file = filename + ext
      if File.exists?(file)
        return true, file
      else
        log(Logger::DEBUG, "File #{file} DOES NOT exist")
      end
    end
    return false, filename
  end

  def sync(folder)
    log_separator('SYNC: BEGIN')
    unless File.exists?(folder)
      log(Logger::ERROR, "Folder #{folder} DOES NOT exist!")
      return false
    end
    # remove trailing path delimiter
    folder.gsub!(/\/$/, '')
    Dir["#{@opts.cache}/*.torrent"].sort.each do |t|
      file = folder + '/' + File.basename(t)
      exists, file_e = file_exists?(file)
      if exists
        log(Logger::DEBUG, "File #{file_e} exists")
        f_size_source = File.size(t)
        f_size_dest = File.size(file_e)
        exists = f_size_source == f_size_dest
        if exists
          log(Logger::DEBUG, "And size (#{f_size_source}) matches")
        else
          log(Logger::DEBUG, "But size (#{f_size_dest}) does not match (#{f_size_source})")
        end
      end
      unless exists
        s = 'Dry run. ' if @opts.options.dry_run
        log(Logger::INFO, "#{s.to_s}Copy #{t} -> #{file}")
        unless @opts.options.dry_run
          FileUtils.cp(t, file)
        end
      end
    end
    log_separator('SYNC: END', '<')
  end
end # class Watcher

end # module TorrentsWatcher
