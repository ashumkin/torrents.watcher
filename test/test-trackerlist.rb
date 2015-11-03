#!/usr/bin/env ruby
# vim: set shiftwidth=2 tabstop=2 expandtab:

require 'test/unit'
require File.expand_path('../../torrents.watcher.rb', __FILE__)
require File.expand_path('../helpers/mocks/tracker-owner.rb', __FILE__)

module TorrentsWatcher

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
