#!/usr/bin/env ruby

=begin
=end

require 'optparse'
require 'ostruct'
require 'pp'
require 'logger'
require 'fileutils'

module TorrentsWatcher

class ChDir
	def initialize(dir)
		return unless block_given?
		od = Dir.pwd
		begin
			Dir.chdir(dir)
			yield dir
		ensure
			Dir.chdir(od)
		end
	end
end

class TOptions < OpenStruct
	def files
		# remove trailing path separator
		return Dir[plugins.gsub(/\/$/, '') + '/' + plugins_mask]
	end
end

class TCmdLineOptions < OptionParser
	attr_reader :options

	def initialize(args)
		super()
		@version = '0.3'
		@options = TOptions.new
		@options.config_dir = ENV['HOME'] + '/.torrents.watcher'
		@options.plugins = File.dirname(__FILE__) + '/trackers.d/'
		@options.plugins_mask = '*.tracker'
		@options.level = Logger::INFO
		@options.relogin = false
		@options.sync = false
		@options.run = false
		@options.dry_run = false
		init
		begin
			@args = args.dup
			@args_parsed = parse!(args)
		rescue ParseError
			warn $!
			Kernel::warn self
			exit!(1)
		return
		end
		init_configs
		validate
	end

	def cache
		return @options.cache
	end

private
	def init_configs
		@options.config = @options.config_dir + '/.configrc' unless @options.config
		@options.cache = @options.config_dir + '/cache'
	end

	def validate
		# if there are non-options parameters
		# or there are no parameters at all
		# show usage
		if @args.empty? || !@args_parsed.empty?
			puts self
			exit(1)
		end
	end

	def init
		separator ''
		separator 'Options:'

		on('-C', '--clean',
				'Clean up cache (remove *.torrent-files)') do |c|
			@options.cleanup = true
		end

		on('-c', '--config CONFIG',
				'Use configuration file CONFIG instead of ~/.torrents.watcher.rc') do |c|
			@options.config = c
		end

		on('-D', '--dir DIR', 'Directory of config and cache. Default is ~/.torrents.watcher/') do |d|
			@options.config_dir = d
		end

		on('-d', '--debug', 'Debug mode. Print all messages') do
			@options.level = Logger::DEBUG
		end

		on('-L', '--relogin', 'Relogin (clean cookies)') do
			@options.relogin = true
		end

		on('-n', '--dry-run', 'Dry run. Do not copy files (implies --sync)') do
			@options.dry_run = true
		end

		on('-r', '--run', 'Run fetching') do
			@options.run = true
		end

		on('-R', '--no-run', 'DO NOT fetching (can be used with --sync)') do
			@options.run = false
		end

		on('-s', '--sync FOLDER', 'Sync with transmission watch folder') do |f|
			@options.sync_folder = f
			@options.sync = true
		end

		on('-S', '--no-sync', 'DO NOT sync (can be used with --run)') do |f|
			@options.sync = false
		end

		on('-q', '--quiet', 'Quiet mode') do
			@options.level = Logger::ERROR
		end

		on_tail('-h', '--help', 'Show this help') do
			puts self
			exit
		end
	end
end

class Tracker
	attr_reader :name

	def initialize(owner, config)
		@owner = owner
		@enabled = true
		@valid, @hash = self.class.read_config_file(config)
		unless @valid
			log(Logger::WARN, "WARNING! File #{config} is not a valid tracker description!")
			return
		end
		@name = @hash.keys[0]
		# only the one configuration only per file
		@hash = @hash[@name]
		# enabled if enabled both in config and in plugin
		@enabled = self.class.test_enabled(@hash[:enabled])
		@enabled &&= self.class.test_enabled(logins[:enabled]) if logins
		@login_method = nil
	end

	def self.test_enabled(enabled)
		unless enabled.nil?
			if enabled.kind_of?(Integer)
				return enabled != 0
			else
				return enabled
			end
		end
		return true
	end

	def self.read_config_file(file)
		content = ''
		return nil, {} unless File.exists?(file)
		File.open(file, 'r') do |f|
			content = f.read
		end
		begin
			hash = eval(content)
		rescue SyntaxError => se
			hash = {}
		end
		if hash.kind_of?(Hash) && !hash.keys[0].nil?
			return true, hash
		else
			return false, {}
		end
	end

	def login_method
		# use caching
		return @login_method if @login_method
		if @hash[:login].kind_of?(Symbol)
			log(Logger::DEBUG, 'Using ' + @hash[:login].to_s + ' login details')
			@login_method = @owner.find_tracker(@hash[:login]).login_method
		else
			@login_method = @hash[:login]
		end
		return @login_method
	end

private
	def name_with_subst
		if @hash[:login].kind_of?(Symbol)
			return @hash[:login]
		else
			return @name
		end
	end

	def logins
		name = name_with_subst
		return nil unless @owner.logins[name]
		r = @owner.logins[name].dup
		# use own avalability but referenced
		r[:enabled] = @owner.logins[@name][:enabled]
		return r
	end

	def tmp
		dir = @owner.opts.cache
		FileUtils.mkdir_p(dir)
		return dir
	end

	def cookies
		name = name_with_subst
		return "#{tmp}/#{name}.cookies"
	end

	def check_login_url
		return login_method[:check] || login_url
	end

	def login_url
		return login_method[:form]
	end

	def temp_html
		return "#{tmp}/#{@name}.html"
	end

	def headers
		return "#{tmp}/#{@name}.headers"
	end

	def wget_options
		opts = ['-q']
		opts << '--convert-links'
		opts << '--keep-session-cookies'
		opts << "--save-cookies #{cookies}"
		opts << "--load-cookies #{cookies}"
		opts << ['--server-response', "--output-file #{headers}"]
		opts.join(' ')
	end

	def login_data
		fields = login_method[:fields]
		data = ''
		fields.each do |k, v|
			data << '&'
			if v.kind_of?(::Symbol)
				# if config for tracker is set
				if logins
					# set param name as symbol
					k = v
					# set value as value of param from config
					v = logins[v].to_s
				else
					v = ''
				end
			end
			data << "#{k.to_s}=#{v}"
		end
		return "\"#{data}\""
	end

	def run_wget(url, data = '', tofile = true)
		file = "-O #{temp_html}" if tofile
		cmd = "wget #{file.to_s} #{wget_options} #{url}"
		data = data.join(' ') if data.kind_of?(Array)
		cmd << ' ' << data.to_s
		log(Logger::DEBUG, cmd)
		system(cmd)
		r = $? == 0
		log(Logger::ERROR, "Error wget execution") unless r
		return r
	end

	def check_already_logged_in
		return false unless run_wget(check_login_url)
		return check_login
	end

	def login
		# check already logged in?
		return true if check_already_logged_in
		# no? try to log in
		return false unless run_wget(login_url, ['--post-data', login_data])
		# check
		return check_login
	end

	def do_replace_torrent(url, regexp)
		match_re = @hash[:torrent][:match_re]
		replace = @hash[:torrent][:replace]
		# return hash to use source link as a referer
		return { url.gsub(match_re, replace) => url }
	end

	def do_scan_torrent(url, regexp)
		match_re = @hash[:torrent][:match_re]
		mi = match_index = @hash[:torrent][:match_index].dup
		match_index ||= 0
		if mi.kind_of?(Array)
			match_index = mi.shift
		else
			mi = [mi]
		end
		a = {}
		File.open(temp_html) do |f|
			while line = f.gets
				line = convert_line(line) if @charset
				if m = match_re.match(line)
					link = m[match_index]
					log(Logger::DEBUG, "Found #{link} (#{m[0]})")
					if regexp.kind_of?(TrueClass) \
							|| regexp.match(line)
						log(Logger::DEBUG, 'Matched to ' + regexp.to_s)
						if mi.size == 1
							name = m[mi[0]]
						else
							name = mi.map { |i| m[i] }
						end
						a[link] = name
					else
						log(Logger::DEBUG, 'But not matched to ' + regexp.to_s)
					end
				end
			end
		end
		return a
	end

	def scan_torrent(url, regexp)
		return unless @hash[:torrent]
		if @hash[:torrent][:replace_url]
			return do_replace_torrent(url, regexp)
		else
			return do_scan_torrent(url, regexp)
		end
	end

	def get_downloaded_filename
		File.open(headers, 'r') do |f|
			while line = f.gets
				if m = /Content-Disposition: attachment; filename="(.+)"/i.match(line)
					f = m[1].gsub(/\\([0-8]{3})/) { [$1.to_i(8)].pack('C')}
					log(Logger::DEBUG, 'Filename is ' + f)
					return f
				end
			end
		end
	end

	def file_is_torrent(filename)
		File.open(filename, 'r') do |f|
			if (f.read(11) == 'd8:announce')
				return true
			end
		end
		log(Logger::DEBUG, "#{filename} is NOT a torrent file!")
		return false
	end

	def fetch_urls
		post = @hash[:torrent][:post]
		torrents = @hash[:torrent][:url]
		torrents = logins[:torrents] unless torrents
		torrents = [torrents] if torrents.kind_of?(String)
		torrents = @owner.logins[@name][:torrents] if torrents == :config
		links = {}
		params = ['--content-disposition', '-N']
		if torrents.kind_of?(Array)
			ts = {}
			torrents.each do |t|
				ts[t] = true
			end
			torrents = ts
		end
		torrents.each do |t, re|
			log(Logger::INFO, "Checking #{t}")
			if run_wget(t)
				links.merge!(scan_torrent(t, re))
			end
		end
		params << '--post-data ""' if post
		ChDir.new(tmp) do
			links.each do |link, name|
				log(Logger::INFO, "Fetching #{link} / #{name}")
				run_wget(link, params)
				filename = get_downloaded_filename
				if filename && file_is_torrent(temp_html)
					log(Logger::DEBUG, "Moving #{temp_html} -> #{filename}")
					FileUtils.mv(temp_html, filename)
				end
			end
		end
	end

	def scanhtml4charset
		File.open(temp_html, 'r') do |f|
			while line = f.gets
				begin
					if m = /content=('|")text\/html;\s*charset=(\S+)\1/i.match(line)
						charset = m[2]
						return charset
					end
				rescue
					next
				end
			end
		end
		return nil
	end

	def convert_line(line)
		if /^1.9/.match(RUBY_VERSION)
			line.encode!('UTF-8', @charset)
		else
			# Iconv must already be loaded in check_login
			line = Iconv.iconv('UTF-8', @charset, line)[0]
		end
	end

	def check_login
		r = true
		success_re = login_method[:success_re] if login_method
		# iconv is deprecated in Ruby 1.9.x
		require 'iconv' if (@charset = scanhtml4charset) && !/^1.9/.match(RUBY_VERSION)
		r = File.size(temp_html) == 0 if File.exists?(temp_html)
		File.open(temp_html, 'r') do |f|
			while line = f.gets
				line = convert_line(line) if @charset
				if success_re.match(line)
					r = true
					break
				end
			end
		end
		# invert flag and check
		r = !r
		if r
			log(Logger::INFO, "Logged in successfully")
		else
			log(Logger::INFO, "NOT logged in")
		end
		return r
	end

	def log(severity, msg)
		@owner.log(severity, msg)
	end

	def cleanup
		log(Logger::INFO, 'Cleanup for ' + @name.to_s)
		File.unlink(cookies) if File.exists?(cookies)
	end
public
	def run
		cleanup if @owner.opts.options.relogin
		return unless @valid && @enabled
		log(Logger::INFO, "Tracker #{name} is being checked")
		return unless login
		fetch_urls
	end
end

class TrackersList < ::Array
	attr_reader :opts, :logins

	def initialize(owner, opts)
		super()
		@owner = owner
		@opts = opts
		FileUtils.mkdir_p(@opts.options.config_dir)
		file = @opts.options.config
		@valid, @logins = Tracker.read_config_file(file)
		unless @valid
			if @valid.nil?
				log(Logger::ERROR, "Config #{file} is absent")
			else
				log(Logger::WARN, "WARNING! Config #{file} is not valid")
			end
		end
		read
	end

	def log(severity, msg)
		@owner.log(severity, msg)
	end

	def run
		return unless @valid
		self.each do |tracker|
			tracker.run
		end
	end

	def find_tracker(name)
		self.each do |t|
			return t if t.name === name
		end
	end

private
	def read
		@opts.options.files.each do |file|
			self << Tracker.new(self, file)
		end
	end
end

class TWatcher
	def initialize(opts)
		@opts = opts
		@logger = Logger.new(STDOUT)
		@logger.level = @opts.options.level
		@trackers = TrackersList.new(self, @opts)
	end

	def log(severity, msg)
		@logger.log(severity, msg)
	end

	def run
		if @opts.options.cleanup
			cleanup
		else
			@trackers.run if @opts.options.run
			sync(@opts.options.sync_folder) if @opts.options.sync
		end
	end

private
	def cleanup
		Dir["#{@opts.cache}/*.torrent"].sort.each do |t|
			s = 'Dry run. ' if @opts.options.dry_run
			log(Logger::INFO, "#{s.to_s}Removing #{t}")
			unless @opts.options.dry_run
				File.unlink(t)
			end
		end
	end

	def sync(folder)
		unless File.exists?(folder)
			log(Logger::ERROR, "Folder #{folder} DOES NOT exist!")
			return false
		end
		# remove trailing path delimiter
		folder.gsub!(/\/$/, '')
		Dir["#{@opts.cache}/*.torrent"].sort.each do |t|
			file = "#{folder}/#{File.basename(t)}.loaded"
			copy = ! File.exists?(file)
			if ! copy
				log(Logger::DEBUG, "File #{file} exists")
				copy = File.size(file) != File.size(t)
				log(Logger::DEBUG, "But size match") unless copy
			else
				log(Logger::DEBUG, "File #{file} DOES NOT exist")
			end
			if copy
				file = "#{folder}/#{File.basename(t)}"
				s = 'Dry run. ' if @opts.options.dry_run
				log(Logger::INFO, "#{s.to_s}Copy #{t} -> #{file}")
				unless @opts.options.dry_run
					FileUtils.cp(t, file)
				end
			end
		end
	end
end

end

# if run directly
if __FILE__ == $0
	cmdLine = TorrentsWatcher::TCmdLineOptions.new(ARGV.dup)
	watcher = TorrentsWatcher::TWatcher.new(cmdLine)
	watcher.run
end
