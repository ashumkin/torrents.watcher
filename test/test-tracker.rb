#!/usr/bin/env ruby
# vim: set shiftwidth=2 tabstop=2 expandtab:

require 'test/unit'
require File.expand_path('../../lib/tracker.rb', __FILE__)
require File.expand_path('../helpers/mocks/tracker-owner.rb', __FILE__)

module TorrentsWatcher

class TestTracker < Test::Unit::TestCase
  TESTED_FOLDER = File.expand_path('../files/test-tracker/', __FILE__)
  TESTED_CONFIG = TESTED_FOLDER + '/config-v'

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

end # module TorrentsWatcher
