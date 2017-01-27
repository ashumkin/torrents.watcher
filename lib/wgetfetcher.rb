#!/usr/bin/env ruby
# vim: set tabstop=2 shiftwidth=2 expandtab :

require File.expand_path('../customfetcher', __FILE__)

class WgetFetcher < CustomFetcher

  def log(level, msg)
    @owner.log(level, msg)
  end

  def cookies
    return "#{tmp}/#{@basename}.cookies"
  end

  def temp_html
    return "#{tmp}/#{@basename}.html"
  end

  def headers
    return "#{tmp}/#{@basename}.headers"
  end

  def options
    opts = ['-q']
    opts << '--convert-links'
    opts << '--keep-session-cookies'
    opts << "--save-cookies #{cookies}"
    opts << "--load-cookies #{cookies}"
    opts << ['--server-response', "--output-file #{headers}"]
    opts.join(' ')
  end

  def response_is_gzipped?(headers_file)
    File.open(headers_file, 'r') do |f|
      while line = f.gets do
        if /Content-Encoding: gzip/i.match(line)
          log(Logger::DEBUG, 'Content is gzipped')
          return true
        end
      end
    end
    return false
  end

  def resave_gzipped_file(headers, file)
    if response_is_gzipped?(headers)
      require 'zlib'
      content = nil
      Zlib::GzipReader.open(file) do |f|
        content = f.read
      end
      File.open(file, 'w') do |f|
        f.write(content)
      end
    end
  end

  def get(url)
    @output_file = temp_html
    file = "-O #{@output_file}"
    cmd = "wget #{file.to_s} #{options} #{url}"
    data = @data
    if data.kind_of?(Hash)
      method_post = data[:method_post]
      is_to_download_file = data[:is_to_download_file]
      post_data = ''
    elsif !data.empty?
      method_post = true
      post_data = data
    end
    params = []
    params << ['--content-disposition', '--timestamping'] if is_to_download_file
    params.push("--post-data \"#{post_data}\"") if method_post
    cmd << ' ' << params.join(' ')
    log(Logger::DEBUG, cmd)
    system(cmd)
    result = $? == 0
    if result
      resave_gzipped_file(headers, @output_file)
    end
    return result
  end
end
