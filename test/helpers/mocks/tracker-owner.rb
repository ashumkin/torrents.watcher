# vim: set shiftwidth=2 tabstop=2 expandtab:

module TorrentsWatcher

# mock owner class
class TestTrackerOwner
  attr_accessor :opts
  def log(severity, msg)
    $stderr.puts('Severity=%d. %s' % [severity, msg]) if $DEBUG
  end

  def log_separator(header, char = '>', count = 10)
    s = char.to_s * count
    if header
      s = "#{s} #{header} #{s}"
    end
    log(Logger::INFO, s)
  end

  def logins
    { :'test-tracker-1' => {:enabled => true } }
  end

end # class TestTrackerOwner

end # module TorrentsWatcher
