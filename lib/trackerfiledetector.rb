#!/usr/bin/env ruby
# encoding: utf-8
# vim: set tabstop=2 shiftwidth=2 expandtab :

class TrackerFileDetector

  def self.is_a_tracker_file?(file)
    File.open(file, 'r') do |f|
      if (f.read(15) =~ /^d\d+:announce/)
        return true
      end
    end
    return false
  end

end
