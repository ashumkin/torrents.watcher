#!/usr/bin/env ruby
# encoding: utf-8
# vim: set shiftwidth=2 tabstop=2 expandtab:

require 'test/unit'
require File.expand_path('../../lib/trackerfiledetector', __FILE__)

module TorrentsWatcher

class TestTrackerFileDetector < Test::Unit::TestCase
  TESTED_FOLDER = File.expand_path('../files/test-trackerfiledetector', __FILE__)
  def setup
  end

  def test_is_a_tracker_file
    assert TrackerFileDetector.is_a_tracker_file?(TESTED_FOLDER + '/tracker.file.1')
  end

  def test_is_a_tracker_file_2
    assert TrackerFileDetector.is_a_tracker_file?(TESTED_FOLDER + '/tracker.file.2')
  end

end # class TestTrackerFileDetector

end # module TorrentsWatcher
