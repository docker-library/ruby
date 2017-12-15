path = File.expand_path(File.dirname(__FILE__))
dockerfiles = Dir.glob("#{path}/**/Dockerfile")

dockerfiles.each do |file|
  text = File.read(file)
  text.gsub!(/apt-get install -y --no-install-recommends/, "apt-get install -y --no-install-recommends libjemalloc-dev")
  text.gsub!(/\.\/configure/, "./configure --with-jemalloc")

  # To write changes to the file, use:
  File.open(file, "w") { |file| file.puts(text) }
end