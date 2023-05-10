require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "sinatra/content_for"

# this ruby idiom finds the absolute path name for this file's parent directory
root = File.expand_path("..", __FILE__)
# otherwise we're using relative paths, which are based on where the program
# is called from--not the location of the file itself!

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

helpers do
  
end

not_found do
  "Nothing here yo."
end

before do
  
end

get "/" do
  @files = Dir.glob(root + "/data/*").map do |path| # pattern matching files
    File.basename(path) # returns only the basename, e.g. 'about.txt'
  end
  erb :index
end
