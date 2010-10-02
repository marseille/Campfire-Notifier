require 'rubygems'
require 'twitter/json_stream'
require 'json'
require 'yaml'

# sudo gem install twitter-stream -s http://gemcutter.org
# http://github.com/voloko/twitter-stream
config_file = "#{ENV["HOME"]}/.campfirerc"
token = ""
url = "https://aghq.campfirenow.com/"
if !FileTest.exists?(config_file)
  print "What is your api key for campfire?\ndon't worry you only have to enter it once! :"
  token = gets
  token = token[0..token.length-2]  
  File.open("#{ENV["HOME"]}/.campfirerc", "w") { |writer|
    writer.write("campfire_config:\n  API_KEY: #{token}")
  }
else 
  a = YAML::load_file(config_file)
  token = a["campfire_config"]["API_KEY"]
end

json_rooms = IO.popen("curl -u #{token}:X https://aghq.campfirenow.com/presence.json")
cool_rooms = JSON.parse(json_rooms.readlines.first)["rooms"]
rooms = cool_rooms.collect {|room| [room["name"],room["id"]]}
room_lookup = {}
cool_rooms.each do |room|
  room_lookup[room["id"]] = room["name"]
end

options = {  
  :host => 'streaming.campfirenow.com',
  :auth => "#{token}:x"
}

EventMachine::run do      
  rooms.each do |room_id|
    Thread.new {    
        stream = Twitter::JSONStream.connect({:path => "/room/#{room_id[1]}/live.json", 
                                                                       :host => "streaming.campfirenow.com",
                                                                       :auth => "#{token}:x"})            
        stream.each_item do |item|
          begin
            message = JSON.parse(item)         
            message_content =  message["body"]
            author_id = message["user_id"]
            room_number = message["room_id"]
            room_name = room_lookup[room_number]
            user = IO.popen("curl -u 5caa15e24a6a838aba12751b252559d093f4e172:X https://aghq.campfirenow.com/users/#{author_id}.json")
            user_name = JSON.parse(user.readlines.first)["user"]["name"]                  
            system("notify-send --expire-time=100 '#{room_name}: #{user_name}' '#{message_content}'")
          rescue => e
            system("notify-send 'ERROR' '#{e.message.to_s}'")
            p e.message
          end
        end
       
        stream.on_error do |message|
          system("notify-send 'ERROR!!!!'")
          p "ERROR:#{message.inspect}"
        end
       
        stream.on_max_reconnects do |timeout, retries|
          system("notify-send 'ERROR' 'Tried #{retries} times to connect.'")
          p "'ERROR' 'Tried #{retries} times to connect.'"
          exit
        end    
    }
  end  
end