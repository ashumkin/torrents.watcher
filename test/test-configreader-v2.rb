#!/usr/bin/env ruby
# vim: set shiftwidth=2 tabstop=2 expandtab:

require 'test/unit'
require File.expand_path('../../lib/configreader-v2', __FILE__)

module TorrentsWatcher

class TestConfigReaderV2 < Test::Unit::TestCase
  TESTED_CONFIG = File.expand_path('../files/test-tracker/config-v2', __FILE__)

  def setup
    @configreader = ConfigReaderV2.new(self)
  end

  def test_class_do_read
    valid, config = @configreader.read(TESTED_CONFIG)
    assert valid
    assert_equal 3, config.keys.count, 'Trackers count'
    assert_equal :'test-tracker-2', config.keys.first
    config = config[config.keys.first]
    assert_equal 1, config[:enabled], 'Enabled'
    assert_equal 'tracker-2-login', config[:login]
    assert_equal 'tracker-2-password', config[:password]
    assert_equal 2, config[:torrents].count, 'Count'
  end
end # class TestConfigReaderV2

end # module TorrentsWatcher
