require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "sinatra/content_for"
require "redcarpet"
require "psych"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

not_found do
  status 404
  erb :not_found
end

# `__FILE__` refers to the current file (`cms.rb`)
# method provides absolute path from root to parent of current file (`cms.rb`)
def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__) # then adds `/test/data`
  else
    File.expand_path("../data", __FILE__) # or just `/data`
  end
end

def credentials_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
end
# relative paths are based on where the program is called from...
# so instead we need absolute paths based on the location of the file itself

def load_user_credentials
  Psych.load_file(credentials_path)
end

def render_markdown(file_text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(file_text)
end

def load_file_content(path)
  file_contents = File.read(path)
  case File.extname(path)
  when ".md"
    erb render_markdown(file_contents)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    file_contents
  end
end

def valid_filename?(filename)
  filename.match?(/\.(txt|md)/)
end

def format_for_yaml(users_hash)
  formatted_string = "{\n  "

  users_hash.each_with_index do |(user, pw), idx|
    to_append = "#{user}: #{pw}"
    if idx == users_hash.size - 1
      to_append << "\n}\n"
    else
      to_append << ",\n  "
    end

    formatted_string << to_append
  end

  formatted_string
end

### insecure note for development/practice purposes: all Zelda character passwords are hashed from "#{username}password" ###
def valid_credentials?(username, password)
  authorized_users = load_user_credentials
  if authorized_users.key?(username)
    BCrypt::Password.new(authorized_users[username]) == password
  else
    false
  end
end

def require_signin
  unless user_signed_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

helpers do
  def user_signed_in?
    session.key?(:username)
  end
end

before do
  
end

get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path| # pattern matching files
    File.basename(path) # returns only the basename, e.g. 'about.txt'
  end
  erb :index
end

get "/users/signin" do
  erb :sign_in
end

post "/users/signin" do
  if valid_credentials?(params[:username], params[:password])
    session[:username] = params[:username]
    session[:message] = "Welcome!"
    redirect "/"
  else
    @username = params[:username]
    session[:message] = "Invalid credentials"
    status 422
    erb :sign_in
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

get "/users/register" do
  erb :register
end

post "/users/register" do
  new_user = params[:username]
  authorized_users = load_user_credentials
  hashed = BCrypt::Password.create(params[:password]).to_s # use #to_s to avoid adding a Password object
  authorized_users[new_user] = hashed

  # take modified hash and write it back to 'users.yml'
  updated_users = format_for_yaml(authorized_users)
  File.open(credentials_path, 'w+') do |file|
    file.write(updated_users)
  end

  session[:username] = new_user
  session[:message] = "Welcome aboard, #{session[:username]}!"
  redirect "/"
end

get "/new" do
  require_signin
  erb :new
end

post "/new" do
  require_signin

  filename = File.basename(params[:filename])
  if valid_filename?(params[:filename])
    file_path = File.join(data_path, filename)
    new_file = File.new(file_path, 'w+')
  
    session[:message] = "#{filename} has been created."
    redirect "/"
  else
    session[:message] = "A filename and either .txt or .md extension are required."
    redirect "/new"
  end
end

get "/:filename" do
  filename = File.basename(params[:filename])
  file_path = File.join(data_path, filename)

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  require_signin

  filename = File.basename(params[:filename])
  file_path = File.join(data_path, filename)

  if File.file?(file_path)
    @file_name = filename
    @content = File.read(file_path)
    erb :edit
  else
    session[:message] = "#{filename} does not exist."
    redirect "/"
  end
end

post "/:filename/edit" do
  require_signin

  filename = File.basename(params[:filename])
  file_path = File.join(data_path, filename)
  File.open(file_path, 'w') do |file|
    file.write(params[:contents])
  end

  session[:message] = "#{filename} has been updated."
  redirect "/"
end

post "/:filename/delete" do
  require_signin

  filename = File.basename(params[:filename])
  file_path = File.join(data_path, filename)
  File.delete(file_path)

  session[:message] = "#{filename} has been deleted."
  redirect "/"
end

post "/:filename/duplicate" do
  require_signin

  filename = File.basename(params[:filename])
  file_path = File.join(data_path, filename)
  contents = File.read(file_path)

  duplicate_file_name = "copy_of_#{filename}"
  duplicate_path = File.join(data_path, duplicate_file_name)
  File.open(duplicate_path, 'w+') do |file|
    file.write(contents)
  end

  session[:message] = "#{filename} has been duplicated."
  redirect "/"
end
