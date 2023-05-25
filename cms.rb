require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "sinatra/content_for"
require "redcarpet"
# require "fileutils"

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
# relative paths are based on where the program is called from...
# so instead we need absolute paths based on the location of the file itself

def render_markdown(file_text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(file_text)
end

def load_file_content(path)
  file_contents = File.read(path)
  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    file_contents
  when ".md"
    erb render_markdown(file_contents)
  end
end

def valid_filename?(filename)
  filename.match?(/\..*/)
end

def valid_credentials?(username, password)
  username == "admin" && password == "secret"
end

helpers do
  
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
    @password = params[:password]
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

get "/new" do
  erb :new
end

post "/new" do
  if valid_filename?(params[:filename])
    file_path = File.join(data_path, params[:filename])
    File.open(file_path, 'w') do |file|
      file.write(params[:contents])
    end
  
    session[:message] = "#{params[:filename]} has been created."
    redirect "/"
  else
    session[:message] = "A filename and extension are required."
    redirect "/new"
  end
end

get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  file_path = File.join(data_path, params[:filename])

  if File.file?(file_path)
    @file_name = File.basename(file_path)
    @content = File.read(file_path)
    erb :edit
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

post "/:filename/edit" do
  file_path = File.join(data_path, params[:filename])
  File.open(file_path, 'w') do |file|
    file.write(params[:contents])
  end

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/delete" do
  filepath = File.join(data_path, params[:filename])
  File.delete(filepath)

  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end
