#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

require File.expand_path('../configreader', __FILE__)

class ConfigReaderYAML < ConfigReader
  def normalize_config(config)
    config.each do |k, v|
      v[:torrent][:match_re] = Regexp.new(v[:torrent][:match_re])
      if v[:login].kind_of?(Hash)
        v[:login][:success_re] = Regexp.new(v[:login][:success_re]) if v[:login][:success_re]
      end
    end
    return config
  end

  def read(file, logmsg = nil)
    super
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
end # class ConfigReaderYAML
