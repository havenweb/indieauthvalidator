require 'sinatra'
require 'open-uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'digest'
require "base64"

STATE = {}
ENDPOINTS = [
"authorization_endpoint",
"token_endpoint",
"micropub",
"microsub"
]
HISTORY = []
SCOPES = [
"profile", 
"email",
"read", 
"create", 
"update", 
"delete", 
"media",
"invalid"
]
## STATE["request_state"]
### code_verifier (random 128 chars of [A-Z][a-z][0-9]), internal state, not sent!
### state (random string?) examples uses 10 characters
### me (user-endered URL, cononicalized)

def wrap_html(content)
<<-HTMLPAGE
<html>
<head>
</head>
<body>
<a href='/'>Home</a><br/>
<p>History:<br/></p>
<ul>
<li>#{HISTORY.join("</li><li>")}</li>
</ul>
<p>Current state:<br/></p>
<p>#{JSON.pretty_generate(STATE).gsub("\n","\n<br/>").gsub(" ","&nbsp;")}</p>
#{content}
</body>
</html>
HTMLPAGE
end

def canonicalize_url(url_in)
  url_out = url_in
  url_out = "https://" + url_out unless (url_out.start_with? "http://" or url_out.start_with? "https://")
  url_out = url_out + "/" unless url_out.count("/") >= 3
  url_out
end

def generate_random(len)
  letters = []
  letters += "abcdefghijklmnopqrstuvwxyz".split('')
  letters += "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split('')
  letters += "1234567890".split('')
  word = ""
  len.times do
    word << letters[(rand * letters.length).to_i]
  end
  word
end

def resolve_metadata_json(url)
  metadata = {}
  metadata_url = ""
  URI.open(url) do |f|
    doc = Nokogiri::HTML(f.read)
    doc.xpath("//link[@rel='indieauth-metadata']").each do |l|
      metadata_url = l["href"]
    end
  end
  unless metadata_url.empty?
    URI.open(metadata_url) do |f|
      json = JSON.parse(f.read)
      metadata = json
    end
  end
  metadata
end

def resolve_metadata_rel(url)
  metadata = {}
  URI.open(url) do |f|
    doc = Nokogiri::HTML(f.read)
    ENDPOINTS.each do |endpoint|
      doc.xpath("//link[@rel='#{endpoint}']").each do |l|
        metadata[endpoint] = l["href"]
      end
    end
  end
  metadata
end

def resolve_metadata(url)
  json = resolve_metadata_json(url)
  if json.empty?
    HISTORY << "No JSON metadata for url: #{url}"
  else
    HISTORY << "Found json metadata for url: #{url}"
    return json
  end
  rel_meta = resolve_metadata_rel(url)
  if rel_meta.empty?
    HISTORY << "No metadata rel links for url: #{url}"
  else
    HISTORY << "Found metadata rel links for url: #{url}"
    return rel_meta
  end
  return {}
end

def create_request(request_state) # hash with code_verifier, state, and me
  {
    "response_type" => "code",
    "client_id" => "http://localhost:4567/",
    "redirect_uri" => "http://localhost:4567/redirect",
    "state" => request_state["state"],
    "code_challenge" => Base64.urlsafe_encode64(Digest::SHA256.digest(request_state["code_verifier"])).chomp("="),
    "code_challenge_method" => "S256",
    "scope" => request_state["scope"]
  }  
end

def create_profile_request(request_state, response)
  {
    "grant_type" => "authorization_code",
    "code" => response["code"],
    "client_id" => "http://localhost:4567/",
    "redirect_uri" => "http://localhost:4567/redirect",
    "code_verifier" => request_state["code_verifier"]
  }
end

get '/' do
checkboxes=""
SCOPES.each do |scope|
checkboxes << <<-CHECKBOX
<input type="checkbox" name="#{scope}" value="#{scope}">
<label for="#{scope}">#{scope}</label><br>
CHECKBOX
end
login_form = <<-FORM
<form action="/action_page">
#{checkboxes}
<input type="text" name="url"> <input type="submit" value="Submit">
</form>
FORM
wrap_html(login_form)
end

get '/action_page' do
  HISTORY << "Form filled out with params: #{params.to_s}"
  url = canonicalize_url(params["url"])
  scopes = []
  SCOPES.each do |scope|
    if params[scope] == scope
      scopes << scope
    end
  end
  scopes_str = scopes.join(" ")
  STATE["url"] = url
  metadata = resolve_metadata(url)
  STATE["metadata"] = metadata
  STATE["request_state"] = {
    "code_verifier" => generate_random(120),
    "state" => generate_random(20),
    "me" => url
  }
  if scopes_str.length > 0
    HISTORY << "Including scopes: #{scopes_str}"
    STATE["request_state"]["scope"] = scopes_str
  else
    HISTORY << "No scopes included in request"
  end
  auth_url = STATE['metadata']['authorization_endpoint'] + "?" + URI.encode_www_form(create_request(STATE["request_state"]))
  HISTORY << "redirecting to #{auth_url}"
  redirect(auth_url)
end

get '/redirect' do
  STATE["auth_response"] = params
  HISTORY << "authorization_endpoint redirected back to our app with an auth_response"
  content = "Successfully hit redirect<br/>"
  content += "<a href='/fetch_profile'>Fetch Profile</a></br>"
  content += "<a href='/fetch_token'>Fetch Token</a></br>"

  wrap_html(content)
end

get '/fetch_profile' do
  post_params = create_profile_request(STATE["request_state"], STATE["auth_response"])

  url = URI.parse(STATE["metadata"]["authorization_endpoint"])
  resp = Net::HTTP.post_form(url, post_params)
  while resp.is_a?(Net::HTTPRedirection) do
    HISTORY << "Redirect in response, goin to : #{resp['location'] || ''}"
    url = URI.parse(resp['location'])
    resp = Net::HTTP.post_form(url, post_params)
  end
  if resp.is_a?(Net::HTTPSuccess)
    STATE["profile_response"] = JSON.parse(resp.body)
  else
    STATE["profile_response"] = {class: resp.class, inspect: resp.inspect}
  end
  wrap_html("fetched profile")
end

get '/fetch_token' do
  post_params = create_profile_request(STATE["request_state"], STATE["auth_response"])
  url = URI.parse(STATE["metadata"]["token_endpoint"])
  resp = Net::HTTP.post_form(url, post_params)
  while resp.is_a?(Net::HTTPRedirection) do
    HISTORY << "Redirect in response, goin to : #{resp['location'] || ''}"
    url = URI.parse(resp['location'])
    resp = Net::HTTP.post_form(url, post_params)
  end
  if resp.is_a?(Net::HTTPSuccess)
    STATE["token_response"] = JSON.parse(resp.body)
  else
    STATE["token_response"] = {class: resp.class, inspect: resp.inspect}
  end
  wrap_html("fetched token")
  
end
