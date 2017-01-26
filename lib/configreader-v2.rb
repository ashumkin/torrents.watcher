#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

require File.expand_path('../configreader', __FILE__)

class ConfigReaderV2 < ConfigReader
  def read(file, logmsg = nil)
    valid, config = super
    return valid, config unless valid
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
end # class ConfigReaderV2
