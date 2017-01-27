#!/usr/bin/env ruby
# encoding: utf-8
# vim: set tabstop=2 shiftwidth=2 expandtab :

class HeaderProcessor

  def self.get_downloaded_filename(headers_file)
    File.open(headers_file, 'r') do |f|
      while line = f.gets
        if m = /Content-Disposition: attachment;\s*filename="(.+)"/i.match(line)
          f = m[1].gsub(/\\([0-8]{3})/) do
            [$1.to_i(8)].pack('C')
          end
          return f
        end
      end
    end
  end

end
