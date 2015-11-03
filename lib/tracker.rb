#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

require 'logger'
require File.expand_path('../chdir.rb', __FILE__)

module TorrentsWatcher

class Tracker
  attr_reader :file, :name, :valid, :enabled

  def initialize(owner, config)
    @owner = owner
    @file = config
    @enabled = true
    @valid, @hash = self.class.read_config_file(@file, self, 'Reading tracker description file %s')
    unless @valid
      log(Logger::WARN, "WARNING! File #{config} is not a valid tracker description!")
      @enabled = false
      return
    end
    @name = @hash.keys[0]
    # only the one configuration only per file
    @hash = @hash[@name]
    # enabled if enabled both in config and in plugin
    @enabled = self.class.test_enabled(@hash[:enabled])
    # disable if user config for tracker is absent
    @enabled &&= logins ? self.class.test_enabled(logins[:enabled]) : false
    @login_method = nil
    test_config
    log(Logger::DEBUG, 'Tracker: %s; Enabled: %s' % [@name, @enabled.to_s.upcase])
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

  def self.read_config_file(file, owner, message)
    return nil, {} unless File.exist?(file)
    if owner.kind_of?(Tracker)
      owner.log(Logger::DEBUG, 'v3: ' + message % file)
      @valid, @config = self.do_read_config_file_v3(file)
    else
      owner.log(Logger::DEBUG, 'v2: ' + message % file)
      @valid, @config = self.do_read_config_file_v2(file)
    end
    owner.log(Logger::DEBUG, 'File valid? ' + @valid.to_s.upcase)
    return @valid, @config
  end

  def self.do_read_config_file_v2(file)
    config = {}
    File.open(file, 'r') do |f|
      while line = f.gets
        line.strip!
        if m = /^#/.match(line)
          # skip commented line
          next
        elsif m = /^tracker:?\s+(.+)$/i.match(line)
          tracker = m[1].to_sym
          config[tracker] = {}
          config[tracker][:torrents] = []
          config[tracker][:enabled] = true
        elsif !tracker
          next
        # tracker topic URL must start with "http://"
        # or equal to ":url" (for those trackers which have fixed URL)
        elsif m = /^(http:\/\/\S+)(\s+.+)?$/i.match(line) \
            || m = /^(:url)$/.match(line)
          torrent = m[1]
          if re = m[2]
            re.strip!
            mailto = nil
            # if we want to notify by mail only
            if m = /mailto:(.+)/i.match(re)
              # regexp must be before "mailto:" string
              re = $`.strip
              mailto = m[1].strip
            end
            # extract <regexp> from /<regexp>/
            re.gsub!(/^\/|\/$/, '')
            torrent = { torrent => { :regexp => Regexp.new(re), :mailto => mailto } }
          end
          config[tracker][:torrents] << torrent
        elsif m = /^(\w+)\s+(.+)$/.match(line)
          key = m[1].to_sym
          value = m[2]
          config[tracker][key] = value
        end
      end
    end
    config.each do |tracker, conf|
      conf[:enabled] = eval(conf[:enabled]) if conf[:enabled].kind_of?(String)
      # disable tracker if no URLs set to track
      # to avoid redundant fetches
      if conf[:torrents].size == 0
        conf[:enabled] = false
      end
    end
    return true, config
  end

  def self.normalize_config(config)
    config.each do |k, v|
      v[:torrent][:match_re] = Regexp.new(v[:torrent][:match_re])
      if v[:login].kind_of?(Hash)
        v[:login][:success_re] = Regexp.new(v[:login][:success_re]) if v[:login][:success_re]
      end
    end
    return config
  end

  def self.do_read_config_file_v3(file)
    require 'yaml'
    config = nil
    begin
      config = YAML::load_file(file)
    rescue
    end
    if config
      config = normalize_config(config)
      return config.keys.size > 0, config
    else
      return false, {}
    end
  end

  def login_method
    # use caching
    return @login_method if @login_method
    if @hash[:login].kind_of?(::Symbol)
      log(Logger::DEBUG, 'Using ' + @hash[:login].to_s + ' login details')
      @login_method = @owner.find_tracker(@hash[:login]).login_method
    else
      @login_method = @hash[:login]
    end
    return @login_method
  end

private
  def test_config
    raise '%s: No :torrect section!' % @name unless @hash[:torrent]
    raise '%s: :match_re must be a Regexp!' % @name unless @hash[:torrent][:match_re].kind_of?(Regexp)
    mi = @hash[:torrent][:match_index]
    unless mi.nil? || mi.kind_of?(Integer) || (mi.kind_of?(Array) && mi.size == 2)
      raise '%s: :match_index must be an integer or an array of two integers!' % @name
    end
  end

  def name_with_subst
    if @hash[:login].kind_of?(::Symbol)
      return @hash[:login]
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

  def cookies
    name = name_with_subst
    return "#{tmp}/#{name}.cookies"
  end

  def check_login_url
    return login_method[:check] || login_url
  end

  def login_url
    return login_method[:form]
  end

  def temp_html
    return "#{tmp}/#{@name}.html"
  end

  def headers
    return "#{tmp}/#{@name}.headers"
  end

  def wget_options
    opts = ['-q']
    opts << '--convert-links'
    opts << '--keep-session-cookies'
    opts << "--save-cookies #{cookies}"
    opts << "--load-cookies #{cookies}"
    opts << ['--server-response', "--output-file #{headers}"]
    opts.join(' ')
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
    return "\"#{data}\""
  end

  def run_wget(url, data = '', tofile = true)
    file = "-O #{temp_html}" if tofile
    cmd = "wget #{file.to_s} #{wget_options} #{url}"
    data = data.join(' ') if data.kind_of?(Array)
    cmd << ' ' << data.to_s
    log(Logger::DEBUG, cmd)
    system(cmd)
    r = $? == 0
    log(Logger::ERROR, "Error wget execution") unless r
    return r
  end

  def check_already_logged_in
    return false unless run_wget(check_login_url)
    return check_login
  end

  def login
    # check already logged in?
    return true if check_already_logged_in
    # no? try to log in
    return false unless run_wget(login_url, ['--post-data', login_data])
    # check
    return check_login
  end

  def do_replace_torrent(url)
    match_re = @hash[:torrent][:match_re]
    replace = @hash[:torrent][:replace]
    # return hash to use source link as a referer
    return { url.gsub(match_re, replace) => url }
  end

  def do_scan_torrent(url, config)
    config = [config] unless config.kind_of?(Array)
    match_re = @hash[:torrent][:match_re]
    mi = match_index = @hash[:torrent][:match_index] || 0
    if mi.kind_of?(Array)
      mi = match_index = mi.dup
    end
    if mi.kind_of?(Array)
      match_index = mi.shift
    else
      mi = [mi]
    end
    links = {}
    File.open(temp_html) do |f|
      log(Logger::DEBUG, 'Scanning file %s for %s' % [temp_html, match_re])
      while line = f.gets
        line = convert_line(line) if @charset
        if m = match_re.match(line)
          link = m[match_index]
          log(Logger::DEBUG, "Found #{link} (#{m[0]})")
          config.each do |conf|
            if conf.kind_of?(TrueClass)
              matched = re = true
              mailto = nil
            else
              re = conf[:regexp]
              mailto = conf[:mailto]
              matched = re.match(line)
            end
            unless matched
              log(Logger::DEBUG, 'But not matched to ' + re.to_s)
            else
              log(Logger::DEBUG, 'Matched to ' + re.to_s)
              if mi.size == 1
                name = m[mi[0]]
              else
                name = mi.map { |i| m[i] }
              end
              links[link] = { :name => name, :mailto => mailto , :url => url }
            end
          end
        end
      end
    end
    return links
  end

  def scan_torrent(url, conf)
    return unless @hash[:torrent]
    if @hash[:torrent][:replace_url]
      return do_replace_torrent(url)
    else
      return do_scan_torrent(url, conf)
    end
  end

  def get_downloaded_filename
    File.open(headers, 'r') do |f|
      while line = f.gets
        if m = /Content-Disposition: attachment; filename="(.+)"/i.match(line)
          f = m[1].gsub(/\\([0-8]{3})/) { [$1.to_i(8)].pack('C')}
          log(Logger::DEBUG, 'Filename is ' + f)
          return f
        end
      end
    end
  end

  def file_is_torrent(filename)
    File.open(filename, 'r') do |f|
      if (f.read(15) =~ /^d\d+:announce/)
        return true
      end
    end
    log(Logger::DEBUG, "#{filename} is NOT a torrent file!")
    return false
  end

  def do_fetch_link(link, config, post)
    name = config[:name]
    log(Logger::INFO, "Fetching: #{name}")
    params = ['--content-disposition', '-N']
    params << '--post-data ""' if post
    run_wget(link, params)
    filename = get_downloaded_filename
    if filename && file_is_torrent(temp_html)
      log(Logger::DEBUG, "Moving #{temp_html} -> #{filename}")
      FileUtils.mv(temp_html, filename)
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
    post = @hash[:torrent][:post]
    torrents = @hash[:torrent][:url]
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
    torrents.each do |t, conf|
      log_separator(t)
      if run_wget(t)
        links.merge!(scan_torrent(t, conf))
      end
      log_separator(nil, '<')
    end
    ChDir.new(tmp) do
      log_separator('PROCESSING: BEGIN')
      links.each do |link, config|
        mailto = config[:mailto]
        log_separator("PROCESSING: #{link}")
        if mailto
          notify(link, config)
        else
          do_fetch_link(link, config, post)
        end
      end
      log_separator('PROCESSING: END')
    end
  end

  def scanhtml4charset
    File.open(temp_html, 'r') do |f|
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
      # Iconv must already be loaded in check_login
      line = Iconv.iconv('UTF-8', @charset, line)[0]
    end
  end

  def check_login
    r = true
    success_re = login_method[:success_re] if login_method
    # iconv is deprecated in Ruby 1.9.x
    require 'iconv' if (@charset = scanhtml4charset) && ! String.new.respond_to?('encode!')
    r = File.size(temp_html) == 0 if File.exists?(temp_html)
    File.open(temp_html, 'r') do |f|
      while line = f.gets
        line = convert_line(line) if @charset
        if success_re.match(line)
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
