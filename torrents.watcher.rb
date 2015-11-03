#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

require File.expand_path('../lib/watcher.rb', __FILE__)

cmdLine = TorrentsWatcher::CmdLineOptions.new(ARGV.dup)
watcher = TorrentsWatcher::Watcher.new(File.basename(__FILE__), cmdLine)
watcher.run
