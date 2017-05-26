require 'fileutils'

module GribConvert
  LEVELS = [1, 2, 3, 5, 7, 10, 20, 30, 50, 70, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600, 650, 700, 750, 800, 850, 900, 925, 950, 975, 1000]
  GRID_SIZE = 25 # we don't want to have too many open files. Limit defaults to 256

  class << self
    def convert_level(level:, path:, dir:)
      base_dir = "#{dir}/L#{level}"
      FileUtils::mkdir_p base_dir

      return if File.exist? "#{base_dir}/.done" # don't reparse

      files = {}

      # start parsing
      command = "grib_get_data -p shortName -w level=#{level} #{path}"

      IO.popen(command) do |io|
        io.gets # skip first line
        while (line = io.gets) do
          lat, lon, value, label = line.split ' '
          next unless label == 'u' || label == 'v'
          next if lat == '' || lon == '' || value == ''

          lat = lat.to_f
          lon = lon.to_f

          grid_lat = (lat / GRID_SIZE).floor * GRID_SIZE
          grid_lon = (lon / GRID_SIZE).floor * GRID_SIZE
          files[grid_lat] ||= {}
          files[grid_lat][grid_lon] ||= File.open("#{base_dir}/C#{grid_lat}_#{grid_lon}.gribp", 'wb')

          files[grid_lat][grid_lon].write "#{[lat].pack('g')}#{[lon].pack('g')}#{[value.to_f].pack('g')}#{label[0]}"
        end
      end

      files.each do |_, file_list|
        file_list.each do |_, file|
          file.close
        end
      end

      FileUtils::touch "#{base_dir}/.done"
    end

    def convert(path)
      puts "Converting #{path}"

      true_start = Time.now

      base_dir = path.split('.').first

      FileUtils::mkdir_p base_dir

      # Note: multithreading this does not help as it must do IO on the same input files
      LEVELS.reverse_each do |level|
        start = Time.now

        convert_level(path: path, level: level, dir: base_dir)

        puts "    converted L#{level} (#{(Time.now - start).round(2)}s)"
      end

      puts "-> Converted #{LEVELS.length} levels (#{(Time.now - true_start).round(2)}s)"
      puts
    end

    def convert_folder(dir, serial:true)
      threads = []
      Dir.entries(dir).each do |entry|
        next unless entry =~ /\.grb2/ # only try to parse grib files

        if serial
          convert "#{dir}/#{entry}"
        else
          threads << Thread.new do
            convert "#{dir}/#{entry}"
          end
        end

      end

      threads.map(&:join) unless serial
    end
  end
end