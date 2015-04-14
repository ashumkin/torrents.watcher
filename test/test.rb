#!/usr/bin/env ruby
# vim: set shiftwidth=2 tabstop=2 expandtab:

require 'test/unit'
require File.expand_path('../../torrents.watcher.rb', __FILE__)

module TorrentsWatcher

class TestTOptions < Test::Unit::TestCase
  TESTED_FOLDER = File.expand_path('../files/test-options', __FILE__)

  def setup
    @options = TOptions.new
    @options.plugins_mask = '*.tracker'
  end

  def test_files
    @options.plugins = TESTED_FOLDER
    assert_equal([TESTED_FOLDER + '/test-1.tracker'], @options.files)
  end

  def test_files_trailing_delimiter
    @options.plugins = TESTED_FOLDER + '/'
    assert_equal([TESTED_FOLDER + '/test-1.tracker'], @options.files)
  end

end # class TestTOptions

# mock owner class
class TestTrackerOwner
  def log(severity, msg)
    $stderr.puts('Severity=%d. %s' % [severity, msg]) if $DEBUG
  end

  def logins
    { :'test-tracker-1' => {:enabled => true } }
  end
end # class TestTrackerOwner

class TestTracker < Test::Unit::TestCase
  TESTED_FOLDER = File.expand_path('../files/test-tracker/', __FILE__)
  TESTED_CONFIG = File.expand_path('../files/test-tracker/config-v', __FILE__)

  def setup
    @tracker = Tracker.new(TestTrackerOwner.new, TESTED_FOLDER + '/test-1.tracker')
  end

  def test_class_test_enabled
    assert Tracker.test_enabled(nil), 'Nil'
    assert Tracker.test_enabled(true), 'True'
    assert !Tracker.test_enabled(false), 'False'
    assert !Tracker.test_enabled(0), 'Integer: 0'
    assert Tracker.test_enabled(1), 'Integer: 1'
    assert Tracker.test_enabled(2), 'Integer: 2'
  end

  def test_class_do_read_config_file_v1
    valid, config = Tracker.do_read_config_file_v1(TESTED_CONFIG + '1')
    assert valid
    assert_equal 2, config.keys.count, 'Trackers count'
    assert_equal :'test-tracker-1', config.keys.first
    config = config[config.keys.first]
    assert_equal 1, config[:enabled], 'Enabled'
    assert_equal 'tracker-1-login', config[:login]
    assert_equal 'tracker-1-password', config[:password]
    assert_equal 2, config[:torrents].count, 'Count'
  end

  def test_class_do_read_config_file_v2
    valid, config = Tracker.do_read_config_file_v2(TESTED_CONFIG + '2')
    assert valid
    assert_equal 3, config.keys.count, 'Trackers count'
    assert_equal :'test-tracker-2', config.keys.first
    config = config[config.keys.first]
    assert_equal 1, config[:enabled], 'Enabled'
    assert_equal 'tracker-2-login', config[:login]
    assert_equal 'tracker-2-password', config[:password]
    assert_equal 2, config[:torrents].count, 'Count'
  end

  def test_initials
    assert(@tracker.valid)
    assert_equal(:'test-tracker-1', @tracker.name)
    assert_equal Hash, @tracker.login_method.class
    assert_equal(true, @tracker.enabled)
  end

  def test_initials_not_valid
    @tracker = Tracker.new(TestTrackerOwner.new, TESTED_FOLDER + '/test-1.tracker.not-valid')
    assert !@tracker.valid
    assert_nil @tracker.name
    assert_equal(false, @tracker.enabled)
    assert_equal nil, @tracker.login_method
  end
end # class TestTracker

class TestTrackersList < Test::Unit::TestCase
  TESTED_FOLDER = File.expand_path('../files/test-trackerslist/', __FILE__)
  TESTED_CONFIG = File.expand_path('../files/test-trackerslist/.config', __FILE__)
  def setup
    args = []
    args << '--dry-run'
    args << '--config' << TESTED_CONFIG
    @opts = TCmdLineOptions.new(args)
    @opts.options.plugins = TESTED_FOLDER
    assert_equal TESTED_CONFIG, @opts.options.config
  end

  def test_count
    list = TrackersList.new(TestTrackerOwner.new, @opts)
    assert_equal 2, list.count
    return list
  end

  def test_find_tracker
    list = test_count

    tracker = list.find_tracker(:'test-tracker-2')
    assert_equal :'test-tracker-2', tracker.name

    tracker = list.find_tracker(:'test-tracker-1')
    assert_equal :'test-tracker-1', tracker.name
  end
end # class TestTrackersList

end # module TorrentsWatcher
