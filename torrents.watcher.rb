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

class ::Logger
	EXTRA_DEBUG = -1
end

class TCmdLineOptions < OptionParser
	attr_reader :options

	def initialize(args)
		super()
		@version = '0.5'
		@options = TOptions.new
		@script_name = 'torrents.watcher'
		@options.config_dir = ENV['HOME'] + '/.' + @script_name
		@options.plugins = File.dirname(__FILE__) + '/trackers.d/'
		@options.plugins_mask = '*.tracker'

		@options.list_trackers = false
		@options.relogin = false
		@options.sync = false
		@options.run = false
		@options.dry_run = false
		@options.levels = {}
		@options.def_levels = [:common, :run, :sync]
		@options.def_levels.each do |level|
			@options.levels[level] = Logger::INFO
		end
		@options.def_levels_joined  = @options.def_levels.join(',')
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

	def lock_file
		return self.cache + '/.' + @script_name + '.lock'
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

	def set_log_level(category, value)
		if category
			category.map!{ |a| a.to_sym }
		else
			category = @options.def_levels
		end
		category.each do |level|
			@options.levels[level] = value
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

		on('-d', '--debug [' + @options.def_levels_joined + ']', Array, 'Debug mode. Print all messages',
				@options.def_levels_joined) do |l|
			set_log_level(l, Logger::DEBUG)
		end

		on('-x', '--extra-debug', 'Extra debug mode') do
			set_log_level([:common], Logger::EXTRA_DEBUG)
		end

		on('-l', '--list-trackers', 'List supported trackers') do
			@options.list_trackers = true
			set_log_level(nil, Logger::WARN)
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

		on('-q', '--quiet [' + @options.def_levels_joined + ']', Array, 'Quiet mode', @options.def_levels_joined) do |q|
			set_log_level(q, Logger::ERROR)
		end

		on('-v', '--verbose [' + @options.def_levels_joined + ']', Array, 'Verbose mode', @options.def_levels_joined) do |q|
			set_log_level(q, Logger::INFO)
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
		@valid, @config = self.do_read_config_file_v1(file)
		# if file exists but not valid Ruby config
		if @valid === false
			@valid, @config = self.do_read_config_file_v2(file)
		end
		return @valid, @config
	end

	def self.do_read_config_file_v1(file)
		content = ''
		return nil, {} unless File.exists?(file)
		File.open(file, 'r') do |f|
			content = f.read
		end
		begin
			conf = eval(content)
		rescue SyntaxError => se
			conf = []
		end
		if conf.kind_of?(Hash) && !conf.keys[0].nil?
			return true, conf
		else
			return false, {}
		end
	end

	def self.do_read_config_file_v2(file)
		config = {}
		File.open(file, 'r') do |f|
			while line = f.gets
				line.strip!
				if m = /^#/.match(line)
					# skip commented line
					next
				elsif m = /^tracker:?\s+(.+)$/i.match(line)
					tracker = m[1].to_sym
					config[tracker] = {}
					config[tracker][:torrents] = []
					config[tracker][:enabled] = true
				elsif !tracker
					next
				elsif m = /^(http:\/\/\S+)(\s+(.+))?$/i.match(line)
					torrent = m[1]
					if re = m[2]
						# strip whitespaces around
						# and extract <regexp> from /<regexp>/
						re.strip!.gsub!(/^\/|\/$/, '')
						torrent = { torrent => Regexp.new(re) }
					end
					config[tracker][:torrents] << torrent
				elsif m = /^(\w+)\s+(.+)$/.match(line)
					key = m[1].to_sym
					value = m[2]
					config[tracker][key] = value
				end
			end
		end
		config.each do |tracker, conf|
			conf[:enabled] = eval(conf[:enabled])
		end
		return true, config
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
		torrents = [torrents] if torrents.kind_of?(Hash)
		links = {}
		params = ['--content-disposition', '-N']
		if torrents.kind_of?(Array)
			ts = {}
			torrents.each do |t|
				if t.kind_of?(Hash)
					ts.merge!(t)
				else
					ts[t] = true
				end
			end
			torrents = ts
		end
		torrents.each do |t, re|
			log_separator(t)
			if run_wget(t)
				links.merge!(scan_torrent(t, re))
			end
			log_separator(nil, '<')
		end
		params << '--post-data ""' if post
		ChDir.new(tmp) do
			log_separator('FETCHING: BEGIN')
			links.each do |link, name|
				log_separator("FETCHING: #{link}")
				log(Logger::INFO, "Fetching: #{name}")
				run_wget(link, params)
				filename = get_downloaded_filename
				if filename && file_is_torrent(temp_html)
					log(Logger::DEBUG, "Moving #{temp_html} -> #{filename}")
					FileUtils.mv(temp_html, filename)
				end
			end
			log_separator('FETCHING: END')
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
		if @owner.ruby18
			# Iconv must already be loaded in check_login
			line = Iconv.iconv('UTF-8', @charset, line)[0]
		else
			line.encode!('UTF-8', @charset)
		end
	end

	def check_login
		r = true
		success_re = login_method[:success_re] if login_method
		# iconv is deprecated in Ruby 1.9.x
		require 'iconv' if (@charset = scanhtml4charset) && @owner.ruby18
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

	def log_separator(header, char = '>')
		@owner.log_separator(header, char)
	end

	def cleanup
		log(Logger::INFO, 'Cleanup for ' + @name.to_s)
		File.unlink(cookies) if File.exists?(cookies)
	end
public
	def run
		cleanup if @owner.opts.options.relogin
		return unless @valid && @enabled
		log_separator(name, '/')
		log(Logger::INFO, "Tracker #{name} is being checked")
		return unless login
		fetch_urls
		log_separator(name, '\\')
	end
end

class TrackersList < ::Array
	attr_reader :opts, :logins, :ruby18

	def initialize(owner, opts)
		super()
		@ruby18 = RUBY_VERSION =~ /^1\.8/
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
		dump_config(@logins)
		read
	end

	def list
		self.each do |tracker|
			puts tracker.name
		end
	end

	def log(severity, msg)
		@owner.log(severity, msg)
	end

	def log_separator(header, char = '>')
		@owner.log_separator(header, char)
	end

	def run
		return unless @valid
		log_separator('RUN: BEGIN')

		self.each do |tracker|
			tracker.run
		end
		log_separator('RUN: END', '<')
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

	def dump_config(file)
		log(Logger::EXTRA_DEBUG, file.inspect)
	end
end

class TWatcher
	def initialize(opts)
		@opts = opts
		@logger = Logger.new(STDOUT)
		@logger.level = @opts.options.levels[:common]
		log_separator(File.basename(__FILE__) + ' version ' + opts.version)
		log_separator('BEGIN', '-')
		@trackers = TrackersList.new(self, @opts)
	end

	def log(severity, msg)
		@logger.log(severity, msg)
	end

	def log_separator(header, char = '>', count = 10)
		s = char.to_s * count
		if header
			s = "#{s} #{header} #{s}"
		end
		log(Logger::INFO, s)
	end

	def run
		begin
			Signal.trap("HUP") do
				$stderr.puts "#{$$}: I'm working"
			end
		if @opts.options.list_trackers
			list
			return
		end
		@logger.level = @opts.options.levels[:common]
		unless check_lock
			log(Logger::ERROR, @opts.lock_file + ' exists. Remove it if you`re sure another instance is not running. Exiting')
			return
		end
		set_lock
		begin
			if @opts.options.cleanup
				cleanup
			else
				@logger.level = @opts.options.levels[:run]
				@trackers.run if @opts.options.run
				@logger.level = @opts.options.levels[:sync]
				sync(@opts.options.sync_folder) if @opts.options.sync
			end
		ensure
			@logger.level = @opts.options.levels[:common]
			remove_lock
		end
		ensure
			log_separator('END', '-')
		end
	end

private
	def check_lock
		return true unless File.exists?(@opts.lock_file)
		log(Logger::DEBUG, @opts.lock_file + ' file exists')
		File.open(@opts.lock_file, 'r') do |f|
			pid = f.gets
			# if file is not empty
			pid.chomp! if pid
			log(Logger::DEBUG, 'PID is equal to ' + pid.to_s)
			begin
				r = Process.kill("HUP", pid.to_i) if pid.to_i > 0
			rescue Errno::ESRCH
				# no such process ID
				r = 0
			rescue
				r = -1
			end
			log(Logger::DEBUG, 'KILL result = ' + r.to_s)
			return r == 0
		end
	end

	def list
		@trackers.list
	end

	def remove_lock
		log(Logger::DEBUG, 'Removing .lock file: ' + @opts.lock_file)
		File.unlink(@opts.lock_file)
	end

	def set_lock
		# simple "touch" equivalent
		log(Logger::DEBUG, 'Setting .lock file: ' + @opts.lock_file)
		File.open(@opts.lock_file, 'w') do |f|
			f.write($$)
		end
	end

	def cleanup
		log_separator('CLEANUP: BEGIN')
		Dir["#{@opts.cache}/*.torrent"].sort.each do |t|
			s = 'Dry run. ' if @opts.options.dry_run
			log(Logger::INFO, "#{s.to_s}Removing #{t}")
			unless @opts.options.dry_run
				File.unlink(t)
			end
		end
		log_separator('CLEANUP: END', '<')
	end

	def sync(folder)
		log_separator('SYNC: BEGIN')
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
		log_separator('SYNC: END', '<')
	end
end

end

# if run directly
if __FILE__ == $0
	cmdLine = TorrentsWatcher::TCmdLineOptions.new(ARGV.dup)
	watcher = TorrentsWatcher::TWatcher.new(cmdLine)
	watcher.run
end
