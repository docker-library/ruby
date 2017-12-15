VERSIONS_TO_BUILD = %w(2.3 2.4)
TAG_TO_FIND = /ENV\s+RUBY_VERSION\s+(.+)/
NAME = "callumj/ruby-jemalloc"

require 'open3'

def run_command(cmd)
  Open3.popen3(cmd) do |stdout, stderr, status, thread|
    Thread.new do
      while line = stdout.gets do
        puts(line)
      end
    end
    while line = stderr.gets do
      puts(line)
    end
  end
end

path = File.expand_path(File.dirname(__FILE__))
VERSIONS_TO_BUILD.each do |version|
  dockerfiles = Dir.glob("#{path}/#{version}/**/Dockerfile")
  dockerfiles.each do |path|
    next if path.match(/(onbuild|alpine)/)

    contents = File.read(path)
    tag = TAG_TO_FIND.match(contents)
    full_version = tag[1]
    base = path[path.index(version)..-1].gsub("/Dockerfile", "").gsub("#{version}/", "").gsub(/\//, "-")
    final_tag = "#{full_version}-#{base}"
    image_name = "#{NAME}:#{final_tag}"
    Dir.chdir(File.dirname(path)) do
      run_command("docker build -t #{image_name} .")
      run_command("docker push #{image_name}")
    end
  end
end
