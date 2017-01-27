#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

require 'logger'
require File.expand_path('../chdir', __FILE__)
require File.expand_path('../configreader-yaml', __FILE__)
require File.expand_path('../wgetfetcher', __FILE__)
require File.expand_path('../headerprocessor', __FILE__)
require File.expand_path('../trackerfiledetector', __FILE__)
require File.expand_path('../scanner', __FILE__)

module TorrentsWatcher

class Tracker
  attr_reader :file, :name, :valid, :enabled
  attr_accessor :url_fetcher

  def initialize(owner, config)
    @owner = owner
    @file = config
    @enabled = true
    @valid, @config = ConfigReaderYAML.new(self).read(@file, 'YAML: Reading tracker description file %s')
    unless @valid
      log(Logger::WARN, "WARNING! File #{config} is not a valid tracker description!")
      @enabled = false
      return
    end
    @name = @config.keys[0]
    # the only one configuration per file
    @config = @config[@name]
    # enabled if enabled both in config and in plugin
    @enabled = self.class.test_enabled(@config[:enabled])
    # disable if user config for tracker is absent
    @enabled &&= logins ? self.class.test_enabled(logins[:enabled]) : false
    @login_method = nil
    test_config
    log(Logger::DEBUG, 'Tracker: %s; Enabled: %s' % [@name, @enabled.to_s.upcase])
    @url_fetcher = WgetFetcher.new(self)
  end

  def self.test_enabled(enabled)
    unless enabled.nil?
      if enabled.kind_of?(Integer)
        return enabled != 0
      else
        return enabled
      end
    end
    return true
  end

  def login_method
    # use caching
    return @login_method if @login_method
    if @config[:login].kind_of?(::Symbol)
      log(Logger::DEBUG, 'Using ' + @config[:login].to_s + ' login details')
      @login_method = @owner.find_tracker(@config[:login]).login_method
    else
      @login_method = @config[:login]
    end
    return @login_method
  end

private
  def test_config
    raise '%s: No :torrect section!' % @name unless @config[:torrent]
    raise '%s: :match_re must be a Regexp!' % @name unless @config[:torrent][:match_re].kind_of?(Regexp)
    mi = @config[:torrent][:match_index]
    unless mi.nil? || mi.kind_of?(Integer) || (mi.kind_of?(Array) && mi.size == 2)
      raise '%s: :match_index must be an integer or an array of two integers!' % @name
    end
  end

  def name_with_subst
    if @config[:login].kind_of?(::Symbol)
      return @config[:login]
    else
      return @name
    end
  end

  def logins
    name = name_with_subst
    return nil unless @owner.logins[name]
    r = @owner.logins[name].dup
    # use own avalability but referenced
    # and disable if absent in user config
    r[:enabled] = @owner.logins[@name] ? @owner.logins[@name][:enabled] : false
    return r
  end

  def tmp
    dir = @owner.opts.cache
    FileUtils.mkdir_p(dir)
    return dir
  end

  def check_login_url
    return login_method[:check] || login_url
  end

  def login_url
    return login_method[:form]
  end

  def login_data
    fields = login_method[:fields]
    data = ''
    fields.each do |k, v|
      data << '&'
      if v.kind_of?(::Symbol)
        # if config for tracker is set
        if logins
          # set param name as symbol
          k = v
          # set value as value of param from config
          v = logins[v].to_s
        else
          v = ''
        end
      end
      data << "#{k.to_s}=#{v}"
    end
    return "#{data}"
  end

  def run_url_fetcher(url_fetcher, url, data = '')
    url_fetcher.basename = name_with_subst
    url_fetcher.tmp = tmp
    url_fetcher.data = data
    result = url_fetcher.get(url)
    log(Logger::ERROR, 'Error getting URL: %s' % url) unless result
    return result
  end

  def check_already_logged_in
    return false unless run_url_fetcher(@url_fetcher, check_login_url)
    return check_login(@url_fetcher)
  end

  def login
    # check already logged in?
    return true if check_already_logged_in
    # no? try to log in
    return false unless run_url_fetcher(@url_fetcher, login_url, login_data)
    # check
    return check_login(@url_fetcher)
  end

  def do_fetch_link(link, config, params)
    name = config[:name]
    log(Logger::INFO, "Fetching: #{name}")
    params[:is_to_download_file] = true
    run_url_fetcher(@url_fetcher, link, params)
    filename = HeaderProcessor.get_downloaded_filename(@url_fetcher.headers)
    log(Logger::DEBUG, 'Filename is ' + filename) if filename
    file_is_torrent = TrackerFileDetector.is_a_tracker_file?(@url_fetcher.output_file)
    if filename && file_is_torrent
      log(Logger::DEBUG, "Moving #{@url_fetcher.output_file} -> #{filename}")
      FileUtils.mv(@url_fetcher.output_file, filename)
    elsif ! file_is_torrent
      log(Logger::DEBUG, "#{@url_fetcher.output_file} is NOT a torrent file!")
    end
  end

  def notify(link, config)
    name = config[:name]
    mailto = config[:mailto]
    url = config[:url]
    # extract params
    mailto, params = mailto.split('?', 2)
    params = params.split('|')
    tmp_file = "#{tmp}/#{name}.notify"
    if File.exists?(tmp_file)
      log(Logger::DEBUG, "Notification file for #{name} already exists. Skipping.")
      return
    end
    log(Logger::INFO, "Notifying for #{name}")
    File.open(tmp_file, 'w') do |f|
      f.puts(params)
      f.puts <<EOT
To: #{mailto}

Notification mail for #{name}.
URL: #{url}.
Link: #{link}.
EOT
    end
    s = 'Dry run. ' if @owner.opts.options.dry_run
    cmd = '%scat "%s" | msmtp -t "%s"' % [s, tmp_file, mailto]
    log(Logger::DEBUG, cmd)
    unless @owner.opts.options.dry_run
      system(cmd)
    end
  end

  def fetch_urls
    post = @config[:torrent][:post]
    torrents = @config[:torrent][:url]
    torrents = logins[:torrents] unless torrents
    torrents = [torrents] if torrents.kind_of?(String)
    torrents = @owner.logins[@name][:torrents] if torrents == :config
    torrents = [torrents] if torrents.kind_of?(Hash)
    if torrents.kind_of?(Array)
      ts = {}
      torrents.each do |t|
        if t.kind_of?(Hash)
          t.each do |k ,v|
            # if such values already set,
            # make an array and append new value to it
            if a = ts[k]
              a = [a] unless a.kind_of?(Array)
              v = a + [v]
            end
            ts[k] = v
          end
        else
          ts[t] = true
        end
      end
      torrents = ts
    end
    links = {}
    if torrents
      torrents.each do |t, conf|
        log_separator(t)
        if run_url_fetcher(@url_fetcher, t)
          if @config[:torrent]
            torrent_scanner = TorrentScanner.new(self)
            urls = torrent_scanner.scan(@url_fetcher.output_file, @config[:torrent], t, conf)
            links.merge!(urls)
          end
        end
        log_separator(nil, '<')
      end
    end
    ChDir.new(tmp) do
      log_separator('PROCESSING: BEGIN')
      links.each do |link, config|
        mailto = config[:mailto]
        log_separator("PROCESSING: #{link}")
        if mailto
          notify(link, config)
        else
          do_fetch_link(link, config, {:method_post => post})
        end
      end
      log_separator('PROCESSING: END')
    end
  end

  def scanhtml4charset(output_file)
    File.open(output_file, 'r') do |f|
      while line = f.gets
        begin
          if m = /content=('|")text\/html;\s*charset=(\S+)\1/i.match(line) \
              || m = /meta charset=(")(\S+)\1/i.match(line)
            charset = m[2]
            return charset
          end
        rescue
          next
        end
      end
    end
    return nil
  end

  def convert_line(line)
    if line.respond_to?('encode!')
      line.encode!('UTF-8', @charset)
    else
      # iconv is deprecated in Ruby 1.9.x
      require 'iconv'
      line = Iconv.iconv('UTF-8', @charset, line)[0]
    end
  end

  def check_login(url_fetcher)
    r = true
    success_re = login_method[:success_re] if login_method
    @charset = scanhtml4charset(url_fetcher.output_file)
    r = File.size(url_fetcher.output_file) == 0 if File.exists?(url_fetcher.output_file)
    File.open(url_fetcher.output_file, 'r') do |f|
      while line = f.gets
        line = convert_line(line) if @charset
        if success_re && success_re.match(line)
          r = true
          break
        end
      end
    end
    # invert flag and check
    r = !r
    if r
      log(Logger::INFO, "Logged in successfully")
    else
      log(Logger::INFO, "NOT logged in")
    end
    return r
  end

  def log_separator(header, char = '>')
    @owner.log_separator(header, char)
  end

  def cleanup
    log(Logger::INFO, 'Cleanup for ' + @name.to_s)
    File.unlink(cookies) if File.exists?(cookies)
  end

public
  def log(severity, msg)
    @owner.log(severity, msg)
  end

  def run
    cleanup if @owner.opts.options.relogin
    return unless @valid && @enabled
    log_separator(name, '/')
    log(Logger::INFO, "Tracker #{name} is being checked")
    return unless login
    fetch_urls
    log_separator(name, '\\')
  end
end # class Tracker

end # module TorrentsWatcher
