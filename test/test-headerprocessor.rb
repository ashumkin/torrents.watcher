#!/usr/bin/env ruby
# encoding: utf-8
# vim: set shiftwidth=2 tabstop=2 expandtab:

require 'test/unit'
require File.expand_path('../../lib/headerprocessor', __FILE__)

module TorrentsWatcher

class TestHeaderProcessor < Test::Unit::TestCase
  TESTED_FOLDER = File.expand_path('../files/test-headerprocessor', __FILE__)
  def setup
  end

  def test_downloaded_filename_lowercase
    assert_equal("downloaded_file.torrent", HeaderProcessor.get_downloaded_filename(TESTED_FOLDER + '/1'))
  end

  def test_downloaded_filename_caps
    assert_equal("downloaded_file.torrent", HeaderProcessor.get_downloaded_filename(TESTED_FOLDER + '/2'))
  end

  def test_downloaded_filename_space
    assert_equal("downloaded_file.torrent", HeaderProcessor.get_downloaded_filename(TESTED_FOLDER + '/3'))
  end

  def test_downloaded_filename_russian_name
    assert_equal("downloaded_file.torrent", HeaderProcessor.get_downloaded_filename(TESTED_FOLDER + '/4'))
  end

end # class TestHeaderProcessor

end # module TorrentsWatcher
