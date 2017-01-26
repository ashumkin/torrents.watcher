#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

class ConfigReader
  def initialize(owner)
    @owner = owner
  end

  def read(file, logmsg = nil)
    return nil, {} unless File.exists?(file)
    @owner.log(Logger::DEBUG, logmsg % [file]) if logmsg
    return true, {}
  end
end
