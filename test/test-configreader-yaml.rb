#!/usr/bin/env ruby
# vim: set shiftwidth=2 tabstop=2 expandtab:

require 'test/unit'
require File.expand_path('../../lib/configreader-yaml', __FILE__)

module TorrentsWatcher

class TestConfigReaderYAML < Test::Unit::TestCase
  TESTED_FOLDER = File.expand_path('../files/test-tracker/', __FILE__)

  def setup
    @configreader = ConfigReaderYAML.new(self)
  end

  def test_class_do_read
    valid, config = @configreader.read(TESTED_FOLDER + '/test-1.tracker')
    assert valid
    assert_equal 1, config.keys.count, 'Trackers count'
    assert_equal :'test-tracker-1', config.keys.first
    config = config[config.keys.first]
    assert_equal 1, config[:enabled], 'Enabled'
    assert_equal 'http://www.kinokopilka.tv/login', config[:login][:check]
    assert_equal 'http://www.kinokopilka.tv/user_sessions', config[:login][:form]
    assert_equal :login, config[:login][:fields][:user]
    assert_equal :password, config[:login][:fields][:password]
    assert_equal 1, config[:login][:fields][:remember_me]
  end
end # class TestConfigReaderYAML

end # module TorrentsWatcher
