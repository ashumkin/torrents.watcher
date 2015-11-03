# vim: set tabstop=2 shiftwidth=2 expandtab :

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
end # class ChDir

end # module TorrentsWatcher
