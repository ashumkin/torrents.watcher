#!/usr/bin/env ruby
# encoding: utf-8
# vim: set shiftwidth=2 tabstop=2 expandtab:

require 'rake'
require 'rake/testtask'

task :default => :test

Rake::TestTask.new do |t|
  t.ruby_opts |= ['-d'] if Rake.application.options.trace
end
