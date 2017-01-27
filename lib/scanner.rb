#!/usr/bin/env ruby
# encoding: utf-8
# vim: set tabstop=2 shiftwidth=2 expandtab :

require 'logger'

class TorrentScanner

  def initialize(tracker)
    @tracker = tracker
  end

  def log(level, msg)
    @tracker.log(level, msg)
  end

  def do_replace_torrent(torrent_config, url)
    match_re = torrent_config[:match_re]
    replace = torrent_config[:replace]
    # return hash to use source link as a referer
    return { url.gsub(match_re, replace) => { :name => url, :url => url } }
  end

  def do_scan_torrent(file, torrent_config, url, config)
    config = [config] unless config.kind_of?(Array)
    match_re = torrent_config[:match_re]
    mi = match_index = torrent_config[:match_index] || 0
    if mi.kind_of?(Array)
      mi = match_index = mi.dup
    end
    if mi.kind_of?(Array)
      match_index = mi.shift
    else
      mi = [mi]
    end
    links = {}
    File.open(file) do |f|
      log(Logger::DEBUG, 'Scanning file %s for %s' % [file, match_re])
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

  def scan(file, torrent_config, url, conf)
    if torrent_config[:replace_url]
      return do_replace_torrent(torrent_config, url)
    else
      return do_scan_torrent(file, torrent_config, url, conf)
    end
  end

end
