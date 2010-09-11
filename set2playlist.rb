#!/usr/bin/env ruby

require 'rubygems'
require 'net/https'
require 'uri'
require 'json'
require 'pp'
require 'uri'
require 'optparse'
require 'ostruct'

PVERSION = "0.1"

if RUBY_PLATFORM =~ /mswin|mingw/
    require 'win32ole'
elsif RUBY_PLATFORM =~ /darwin/
    require 'appscript'
else
    raise("Unsupported operating system.")
end

class String
    def red; colorize(self, "\e[1m\e[31m"); end
    def green; colorize(self, "\e[1m\e[32m"); end
    def dark_green; colorize(self, "\e[32m"); end
    def yellow; colorize(self, "\e[1m\e[33m"); end
    def blue; colorize(self, "\e[1m\e[34m"); end
    def dark_blue; colorize(self, "\e[34m"); end
    def pur; colorize(self, "\e[1m\e[35m"); end
    def colorize(text, color_code)  "#{color_code}#{text}\e[0m" end
end

class ParseOptions

    def self.parse(args)
        options = OpenStruct.new
        options.playlist_name = 'Setlist'
        options.play = true

        opts = OptionParser.new do |opts|
            opts.banner = "Usage: #{$0} [options]"

            opts.separator " "
            opts.separator "Mandatory options:"

            opts.on("-e", "--event-id=id", String, "Specifies the last.fm event id") { |u| options.event_id = u }
            opts.on("-s", "--setlist-id=id", String, "Specifies the setlist.fm setlist id") { |u| options.setlist_id = u }

            opts.separator " "
            opts.separator "Specific options:"

            opts.on("-n", "--playlist_name", String, "Specifies the playlist name, if not 'Setlist' will be used instead.") { |n| options.playlist_name = n }
            opts.on("-v", "--[no-]verbose", "Run verbosely") { |v| options.verbose = v }
            opts.on("-p", "--[no-]play", "Play playlist (default true)") { |p| options.play = p }
            opts.separator " "

            opts.separator "Common options:"
            opts.on_tail("-h", "--help", "Show this message") do
                puts opts
                exit
            end

            opts.on_tail("--version", "Show version") do
                puts PVERSION
                exit
            end
        end

        opts.parse!(args)
        options
    end

end

options = ParseOptions.parse(ARGV)
if options.event_id.nil? and options.setlist_id.nil?
    $stderr.puts "Missing event or setlist id. Please run '#{$0} -h' for help."
    exit 1
end

if not options.event_id.nil? 
    url = URI.parse("http://api.setlist.fm/rest/0.1/setlist/lastFm/#{options.event_id}.json")
else
    url = URI.parse("http://api.setlist.fm/rest/0.1/setlist/#{options.setlist_id}.json")
end

request = Net::HTTP::Get.new(url.request_uri)
http = Net::HTTP.new(url.host, url.port)
res = http.start do |ht|
    ht.request(request)
end

begin
    json = JSON.parse(res.body)
rescue => e
    puts "Invalid response from setlist.fm api:- #{e}".red
    exit
end

artist = json['setlist']['artist']['@name']

iTunes = Appscript.app("iTunes.app")
iTunes.launch unless iTunes.is_running?

playlist = iTunes.playlists[artist].exists ? iTunes.playlists[artist] : nil
iTunes.delete(playlist) unless playlist.nil?

system <<EOF
osascript -e '
tell application "iTunes"
    make new playlist with properties {name:"#{artist}", shuffle:false}
    set new_playlist to playlist "#{artist}"
    duplicate tracks whose artist is "#{artist}" to new_playlist
    set view of front browser window to user playlist "#{artist}" of source "Library"
end tell
' > /dev/null 2>&1
EOF

sleep 1

playlist = iTunes.playlists[artist].exists ? iTunes.playlists[artist] : nil
dest_playlist = iTunes.playlists[options.playlist_name].exists ? iTunes.playlists[options.playlist_name] : iTunes.make(:new => :user_playlist, :with_properties => { :name => options.playlist_name })
dest_playlist.tracks.get.each{ |tr| tr.delete }

whose, tracks = Appscript.its, playlist.tracks

json['setlist']['sets']['set'].each do |result|
    result['song'].each do |song|
        title = song['@name']

        track_ref = tracks[whose.name.eq(title).and(whose.video_kind.eq(:none)).and(whose.podcast.eq(false))].first
        if not track_ref.exists
            # Try contains for some sort of match (mixed results)
            track_ref = tracks[whose.name.contains(title).and(whose.video_kind.contains(:none)).and(whose.podcast.contains(false))].first
        end

        if track_ref.exists
            print "* [Found]".green
            iTunes.add(track_ref.location.get, :to => dest_playlist) # Add the track to our playlist.
        else
            print "* [Not found]".red
        end
        print " " + song['@name']
        puts
    end
end

playlist.delete

dest_playlist.play if options.play
