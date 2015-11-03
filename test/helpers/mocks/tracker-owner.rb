# vim: set shiftwidth=2 tabstop=2 expandtab:

module TorrentsWatcher

# mock owner class
class TestTrackerOwner
  def log(severity, msg)
    $stderr.puts('Severity=%d. %s' % [severity, msg]) if $DEBUG
  end

  def logins
    { :'test-tracker-1' => {:enabled => true } }
  end
end # class TestTrackerOwner

end # module TorrentsWatcher
