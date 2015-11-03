#!/usr/bin/env ruby
# vim: set shiftwidth=2 tabstop=2 expandtab:

require 'test/unit'
require File.expand_path('../../lib/options.rb', __FILE__)
require File.expand_path('../../lib/trackerlist.rb', __FILE__)
require File.expand_path('../helpers/mocks/tracker-owner.rb', __FILE__)

module TorrentsWatcher

class TestTrackerPredefined < Test::Unit::TestCase
  def setup
    args = ['--dry-run']
    args << '--debug' if Rake.application.options.trace
    @opts = CmdLineOptions.new(args)
  end

  def test_validity
    list = TrackerList.new(TestTrackerOwner.new, @opts)
    assert_not_equal 0, list.count
    list.each do |tracker|
      assert tracker.valid, 'Invalid tracker description: ' + tracker.file
    end
  end

end # class TestTrackersList

end # module TorrentsWatcher
