require 'rubygems'
require 'sinatra'
require 'sinatra/json'
require 'json'
require 'rest_client'
require 'hipchat-api'
require 'xmpp4r/client'
require 'xmpp4r/muc/helper/simplemucclient'
require 'rubygems'
require 'bundler'

Bundler.require

helpers do
  def call_workflow(username,token,workflow_id,event,params)
    puts "calling workflow #{workflow_id}"
    RestClient.get("http://factor.io/workflows/#{workflow_id}/call.json?auth_token=#{token}&speaker=#{URI::encode(params[:speaker])}&message=#{URI::encode(params[:message])}")
  end

  def start_bot(username,token,workflow_id,event,params)
    job_info = {:username=>username,:token=>token,:workflow_id=>workflow_id.to_s,:event=>event}.to_json
    puts "starting bot (#{workflow_id}): #{job_info}"

    @job = Thread.new do
      puts "Bot thread started"
      user_jid=params["user_jid"] + "/bot"
      hipchat_username=params["username"]
      full_name=params["name"]
      hipchat_password=params["password"]
      hipchat_token=params["token"]
      room_name = params["room_name"]

      puts "Connecting to room '#{room_name}'"
      hipchat=HipChat::API.new(hipchat_token) # App API Auth Token for Factor
      room_jid =  hipchat.rooms_show(room_name)["room"]["xmpp_jid"]

      puts "Logging in as '#{user_jid}'"
      xmpp = Jabber::Client::new(Jabber::JID::new(user_jid))
      muc = Jabber::MUC::SimpleMUCClient.new(xmpp)
      xmpp.connect
      xmpp.auth(hipchat_password)

      begin
        muc.join "#{room_jid}/#{full_name}", hipchat_password
        puts "Joined room"
      rescue => e
        puts "Failed to join room: #{e.message}"
      end

      puts "Announcing #{user_jid} is online"
      # xmpp.send(Jabber::Presence.new.set_type(:available))
      pres = Jabber::Presence.new.set_type(:available)
      
      # x = Jabber::X.new
      # x.add_namespace("http://jabber.org/protocol/muc")
      # element = REXML::Element.new 'history'
      # element.add_attribute("maxstanzas","0")
      # x.add_element(element)
      # pres.add_element(x)

      xmpp.send(pres);
      puts "Announced #{user_jid} is online"



      case event
      when "MessageReceived"
        puts "Starting to listen for messages"
        muc.on_message do |time,speaker,message|
          call_workflow(username,token,workflow_id,event,{:time=>time,:speaker=>speaker,:message=>message})
        end
        puts "Listening for messages"
      when "Joined"
        puts "Starting to listen for joins"
        muc.on_join do |time,speaker|
          call_workflow(username,token,workflow_id,event,{:time=>time,:speaker=>speaker})
        end
        puts "Listening for joins"
      when "Leave"
        puts "Starting to listen for leaves"
        muc.on_leave do |time,speaker|
          call_workflow(username,token,workflow_id,event,{:time=>time,:speaker=>speaker})
        end
        puts "Listening for leaves"
      when "PrivateMessageReceived"
        puts "Starting to listen for private messages"
        muc.on_private_message do |time,speaker,message|
          call_workflow(username,token,workflow_id,event,{:time=>time,:speaker=>speaker,:message=>message})
        end
        puts "Listening for private messages"
      when "RoomMessageReceived"
        puts "Starting to listen for room messages"
        muc.on_room_message do |time,message|
          call_workflow(username,token,workflow_id,event,{:time=>time,:message=>message})
        end
        puts "Listening for room messages"
      when "SubjectChange"
        puts "Starting to listen for subject changes"
        muc.on_subject do |time,speaker,subject|
          call_workflow(username,token,workflow_id,event,{:time=>time,:speaker=>speaker,:subject=>subject})
        end
        puts "Listening for subject changes"
      end
      
      
      begin
        sleep 1 while true
      rescue SystemExit, Interrupt
        puts "Closing"
        xmpp.close
        chat_thread.join
        puts "Closed"
      end

    end
    
    settings.listeners[job_info]=@job
    @message = "Listener started"
    @message
  end

  def stop_bot(username,token,workflow_id,event)
    job_info = {:username=>username,:token=>token,:workflow_id=>workflow_id.to_s,:event=>event}.to_json
    puts "stopping bot (#{workflow_id}): #{job_info}"
    if settings.listeners.include?(job_info)
      job = settings.listeners[job_info]
      job.kill
    end
  end
end

configure do
  set :listeners, {}
end

post '/' do
  data = JSON.parse(request.body.read)
  username = data["username"]
  token = data["token"]
  workflow_id = data["workflow_id"]
  event = data["event"]
  params = data["parameters"]
  puts "Parameters: #{params.to_json}"
  message = start_bot(username,token,workflow_id,event,params)
  response = {:message=>message}
  json response
end

delete '/' do
  # data = JSON.parse(request.body.read)
  username = params["username"]
  token = params["token"]
  workflow_id = params["workflow_id"]
  event = params["event"]

  stop_bot(username,token,workflow_id,event)
  response = {:message=>"bot has stopped"}
  json response
end
