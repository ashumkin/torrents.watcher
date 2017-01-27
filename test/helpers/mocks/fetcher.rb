# vim: set shiftwidth=2 tabstop=2 expandtab:

require File.expand_path('../../../../lib/customfetcher', __FILE__)

class TMockFetcher < CustomFetcher

  def get(url)
    File.open(@output_file, 'w') do |f|
      f.write("Torrent #{@owner.name} fetched")
    end
  end
end
