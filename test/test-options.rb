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

end # module TorrentsWatcher
