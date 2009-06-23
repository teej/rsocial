require "rubygems"
require "json"
require "timeout"
require 'net/http'

module RSocial
	
	FACEBOOK_NETWORK = "Facebook"
	BEBO_NETWORK = "Bebo"
	
	class SessionNotSet < StandardError; end
	class InvalidSignature < StandardError; end
	
	def process_params
	end
	
	def validate_sig(x, enc="fb_sig")
		sig = x[enc]
		return (sig == get_sig(x, enc))
	end
	
	def clean_params(hash, enc)
		new_hash = {}
		regex = Regexp.new(enc + "_")
		key_start = enc.size + 1
		hash.each {|k,v|
			new_hash[k[key_start..-1]] = v if k =~ regex
			#if network == FACEBOOK_NETWORK
			#elsif network == BEBO_NETWORK
			#	new_hash[k[7..-1]] = v.to_s.sub(/%2C/, ",") if k =~ /fb_sig_/
			#end
		}
		new_hash
	end
	
	def get_sig(params, enc)
		args = []
		pars = clean_params(params.dup, enc)
		pars.each { |k,v|
			args << "#{k}=#{v}"
		}
		request_str = args.sort.join("")
		digest = Digest::MD5.hexdigest("#{request_str}#{api_secret}")
		return digest
	end
	
	def get_bebo_sig(params)
		args = []
		params.each { |k,v|
			args << "#{k}=#{v}"
		}
		request_str = args.sort.join("")
		digest = Digest::MD5.hexdigest("#{request_str}#{SNCONFIG["bebo_secret"]}")
		return digest
	end
	
	def get_req_str(params)
		x = ""
		params.each do |k,v|
			x += "#{k}|#{v}|#{v.class}|<br>"
		end
 		x
	end
	
	def api_key
		key = ""
		key = SNCONFIG["facebook_key"] if network == FACEBOOK_NETWORK
		key = SNCONFIG["bebo_key"] if network == BEBO_NETWORK
		return key
	end
	
	def api_secret
		key = ""
		key = SNCONFIG["facebook_secret"] if network == FACEBOOK_NETWORK
		key = SNCONFIG["bebo_secret"] if network == BEBO_NETWORK
		return key
	end
	
	def canvas_page
		page = ""
		page = SNCONFIG["facebook_canvas"] if network == FACEBOOK_NETWORK
		page = SNCONFIG["bebo_canvas"] if network == BEBO_NETWORK
		return page
	end
	
	def network
		 params[:fb_sig_network] || FACEBOOK_NETWORK
	end
	
	def require_facebook_session
		
		#in canvas
		if params["fb_sig_in_canvas"] == "1" && params["fb_sig_added"] != "1"
			render :text=> %|<fb:redirect url="http://www.facebook.com/add.php?api_key=#{api_key}" />|
		
		#in iframe
		elsif (fbsession.nil? || fbsession.user_id.nil?) && params["fb_sig_added"] != "1"
			render :text => %|<script>window.top.location="http://www.facebook.com/add.php?api_key=#{api_key}";</script>|
		end
	end
	
	def grab_facebook_session
		if validate_sig(params)
			rsession = SocialSession.new(:api_key=>api_key, :api_secret=>api_secret, :network=>network, \
				:session_key=>params[:fb_sig_session_key], :user_id=>params[:fb_sig_user])
			if params[:fb_sig_in_iframe] == "1"
				session[:rsocial_session] = rsession
				session_not_set if request.cookies["_session_id"].to_s.blank?
			end
		else
			raise InvalidSignature, "Bad sig #{get_sig(params)} % #{params["fb_sig"]} % #{api_secret} % #{get_req_str(params)}"
		end
		true
		
	end
	
	def session_not_set
#		raise SessionNotSet, "The session isn't being set."
	end
	
	def fbsession
		session[:rsocial_session] || SocialSession.new(:api_key=>api_key, :api_secret=>api_secret, :network=>network, \
				:session_key=>params[:fb_sig_session_key], :user_id=>params[:fb_sig_user])
	end
	
	def api_key_of(netw = FACEBOOK_NETWORK)
		case netw
			when FACEBOOK_NETWORK
				return SNCONFIG["facebook_key"]
			when BEBO_NETWORK
				return SNCONFIG["bebo_key"]
			else
				return ""
		end
	end
	
	def api_secret_of(netw = FACEBOOK_NETWORK)
		case netw
			when FACEBOOK_NETWORK
				return SNCONFIG["facebook_secret"]
			when BEBO_NETWORK
				return SNCONFIG["bebo_secret"]
			else
				return ""
		end
	end
	
	def create_new_sn_client(args)
		SocialSession.new(:api_key=>api_key_of(args[:network]), :api_secret=>api_secret_of(args[:network]), :network=>args[:network],
			:session_key=>args[:session_key], :user_id=>args[:user_id])
	end
	
	class SocialRequest
		
		attr_reader :raw_data, :response
		
		def initialize(network)
			@network = network
			@raw_data = ""
			@response = {}
		end
		
		def post(params)
			
			port = 80
			http_server = Net::HTTP.new(api_server_base, port)
			http_request = Net::HTTP::Post.new(api_server_path)
			http_request.form_data = params
			
			begin
				timeout(8) {
					@raw_data = http_server.start{|http| http.request(http_request)}.body
					@response = JSON.parse(@raw_data) if params[:format] == "json"
					@response = Hash.from_xml(@raw_data) if params[:format] == "xml"
				}
			rescue TimeoutError
				@raw_data = ""
				@response = {"error_msg"=>"(error_code) Facebook timed out", "error"=>"Bebo timed out"}
			rescue JSON::ParserError
				@response = @raw_data
			end
			
			return self
			
		end
		
		def api_server_base
			server = ""
			server = "api.facebook.com" if @network == FACEBOOK_NETWORK
			#server = "69.63.176.141" if @network == FACEBOOK_NETWORK
			server = "apps.bebo.com" if @network == BEBO_NETWORK
			return server
		end
		
		def api_server_path
			return "/restserver.php"
		end
		
		def has_errors?
			error_key = nil
			error_key = "error_code" if @network == FACEBOOK_NETWORK
			error_key = "error" if @network == BEBO_NETWORK
			return @response.to_s.include?(error_key)
		end
		
		def error_message
			error_msg = ""
			error_msg = @response["error_msg"] if @network == FACEBOOK_NETWORK
			error_msg = @response["error"] if @network == BEBO_NETWORK
			return error_msg
		end
		
	end
	
	class SocialSession
		
		class RemoteStandardError < StandardError; end
		class ExpiredSessionStandardError < StandardError; end
		class NotActivatedStandardError < StandardError; end
		
		attr_reader :user_id, :session_key, :expires, :network, :api_key, :canvas_type
		
		def initialize(args = {})

			@api_key = args[:api_key]
			@api_secret = args[:api_secret]
			@user_id = args[:user_id]
			@session_key = args[:session_key]
			@expires = args[:expires] || 0
			@network = args[:network] || FACEBOOK_NETWORK
			
		end
		
		def session_user_id
			user_id
		end
		
		def is_activated?
			return true #(@session_key != nil)
		end
		
		def api_namespace
			return "facebook" if @network == FACEBOOK_NETWORK
			return "socialNetwork" if @network == BEBO_NETWORK
		end
		
		def build_signature(params)
			args = []
			params.each { |k,v|
				args << "#{k}=#{v}"
			}
			request_str = args.sort.join("")
			return Digest::MD5.hexdigest("#{request_str}#{@api_secret}")
		end
		
		def post_request(params)
			response = RSocial::SocialRequest.new(@network)
			response.post(params)
		end
		
		def method_missing(method_symbol, *params)
			tokens = method_symbol.to_s.split("_")
			return call_method(tokens.join("."), params.first)
		end
		
		def call_method(method, params={}) # :nodoc:
			
			if !is_activated?
				raise NotActivatedStandardError, "You must activate the session before using it."
			end
			
			
			params = {} if (!params)
			params = params.dup
			
			params[:format] ||= "json"
			params[:method] = "#{api_namespace}.#{method}"
			params[:api_key] = @api_key
			params[:v] = "1.0"
			params[:session_key] = @session_key
			params[:call_id] = Time.now.to_f.to_s
			
			params.each{|k,v| params[k] = v.join(",") if v.is_a?(Array)}
			params[:sig] = build_signature(params)
			
			response = post_request(params)
			
			# error checking    
			if response.has_errors?
				raise RemoteStandardError, response.error_message
				return nil
			end
			  
			return response
			
		end
		
	end
end
