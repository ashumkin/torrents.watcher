#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

class CustomFetcher
  attr_accessor :output_file, :data, :basename, :tmp

  def initialize(owner)
    @owner = owner
    @basename = nil
    @data = nil
    @tmp = nil
    @output_file = nil
  end

end
