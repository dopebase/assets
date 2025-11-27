#!/usr/bin/env ruby
# create-link-images.rb
# Scans a directory of images and generates an HTML file with <img> tags

require 'optparse'
require 'pathname'

options = {
	output: 'generated.html',
	base_url: 'https://raw.githubusercontent.com/dopebase/assets/refs/heads/main',
	repo_prefix: 'apps'
}

parser = OptionParser.new do |opts|
	opts.banner = "Usage: create-link-images.rb [options] <folder>"

	opts.on('-o', '--output FILE', 'Output HTML file (default: generated.html)') { |v| options[:output] = v }
	opts.on('-b', '--base-url URL', 'Base raw URL for images') { |v| options[:base_url] = v }
	opts.on('-p', '--repo-prefix PATH', 'Repo prefix/path to prepend (default: apps)') { |v| options[:repo_prefix] = v }
	opts.on('-h', '--help', 'Prints this help') { puts opts; exit }
end

parser.parse!

if ARGV.empty?
	puts parser
	exit 1
end

folder = ARGV.shift
# Resolve folder: accept absolute, relative, or relative to repo_prefix (e.g. "apps/")
dir = Pathname.new(folder)
unless dir.exist?
	# try prefixing with the repo_prefix (common usage: pass path relative to prefix)
	prefixed = Pathname.new(File.join(options[:repo_prefix], folder))
	if prefixed.exist?
		dir = prefixed
	else
		puts "Folder not found: #{folder}"
		puts "Tried: #{folder} and #{prefixed}"
		exit 1
	end
end

IMAGE_EXTS = %w[.png .jpg .jpeg .gif .svg .webp]

def read_bytes(path, n)
	File.open(path, 'rb') { |f| f.read(n) }
end

def png_size(path)
	data = read_bytes(path, 24)
	return nil unless data && data.bytesize >= 24
	png_sig = "\x89PNG\r\n\x1A\n"
	return nil unless data[0,8] == png_sig
	# width: bytes 16..19, height: bytes 20..23 (big-endian)
	width = data[16,4].unpack('N').first
	height = data[20,4].unpack('N').first
	[width, height]
rescue
	nil
end

def gif_size(path)
	data = read_bytes(path, 10)
	return nil unless data && data.bytesize >= 10
	return nil unless data[0,6] =~ /GIF8[79]a/
	# width little-endian bytes 6..7, height 8..9
	width = data[6,2].unpack('v').first
	height = data[8,2].unpack('v').first
	[width, height]
rescue
	nil
end

def jpeg_size(path)
	File.open(path, 'rb') do |f|
		return nil unless f.read(2) == "\xFF\xD8" # SOI
		loop do
			marker, = f.read(1).unpack('C') rescue nil
			break if marker.nil?
			# markers are 0xFF followed by type
			while marker == 0xFF
				marker, = f.read(1).unpack('C') rescue nil
			end
			break if marker.nil?
			type = marker
			# read segment length
			if type == 0xDA # Start of Scan - image data follows
				break
			end
			length_bytes = f.read(2)
			break if length_bytes.nil? || length_bytes.bytesize < 2
			seg_len = length_bytes.unpack('n').first
			# SOF0 (0xC0), SOF2 (0xC2) contain width/height
			if [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].include?(type)
				body = f.read(seg_len - 2)
				return nil if body.nil? || body.bytesize < 6
				height = body[1,2].unpack('n').first
				width = body[3,2].unpack('n').first
				return [width, height]
			else
				f.seek(seg_len - 2, IO::SEEK_CUR)
			end
		end
	end
	nil
rescue
	nil
end

def image_size(path)
	ext = File.extname(path).downcase
	case ext
	when '.png'
		png_size(path)
	when '.gif'
		gif_size(path)
	when '.jpg', '.jpeg'
		jpeg_size(path)
	else
		nil
	end
end

files = Dir.children(dir).select do |f|
	p = dir + f
	p.file? && IMAGE_EXTS.include?(File.extname(f).downcase)
end.sort

if files.empty?
	puts "No images found in #{dir}"
	exit 1
end

html = []

files.each_with_index do |f, idx|
	local_path = (dir + f).cleanpath.to_s
	# build repo path: prefix + provided folder + filename
	# assume folder argument is relative to repo prefix
	repo_path = [options[:repo_prefix], folder, f].join('/').gsub(%r{//+}, '/')
	src = [options[:base_url].chomp('/'), repo_path].join('/')
	alt = File.basename(f, '.*').gsub(/[-_]+/, ' ').strip
	size = image_size(local_path)
	w_attr = size ? " width=\"#{size[0]}\"" : ''
	h_attr = size ? " height=\"#{size[1]}\"" : ''
	css_class = "alignnone shadow size-large wp-image-#{1000 + idx}"
	img = %Q{<img src="#{src}" alt="#{alt}"#{w_attr}#{h_attr} class="#{css_class}" />}
	html << img
end


File.write(options[:output], html.join("\n"))
puts "Wrote #{options[:output]} with #{files.size} images."

puts <<~USAGE
Usage examples:
	# From repo root, list images under apps/react-native/react-native-dating-app
	ruby create-link-images.rb react-native/react-native-dating-app -o generated.html

	# If you want to change the raw Github base URL or repo prefix:
	ruby create-link-images.rb react-native/react-native-dating-app -b https://raw.githubusercontent.com/dopebase/assets/refs/heads/main -p apps -o out.html
USAGE

