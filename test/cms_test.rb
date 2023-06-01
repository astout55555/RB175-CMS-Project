ENV["RACK_ENV"] = "test"

require "fileutils"

require "minitest/autorun"
require "rack/test"
require "minitest/reporters"
Minitest::Reporters.use!

require_relative "../cms"

class CmsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w+") do |file|
      file.write(content)
    end
  end

  def write_users_yml_file(content = "")
    File.open(credentials_path, "w+") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"
    create_document "history.txt"

    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "/about.md"
    assert_includes last_response.body, "/changes.txt"
    assert_includes last_response.body, "/history.txt"
  end

  def test_sign_in_page
    get "/users/signin"
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<form action="/users/signin")
  end

  def test_sign_in_valid
    write_users_yml_file "{ test_user: #{BCrypt::Password.create("test_password")} }"

    post "/users/signin", username: "test_user", password: "test_password"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_equal "test_user", session[:username]
    assert_nil session[:message]
  end

  def test_invalid_sign_in
    write_users_yml_file "{ test_user: #{BCrypt::Password.create("test_password")} }"

    post "/users/signin", username: "test_badname", password: "test_badpw"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid credentials"
    assert_includes last_response.body, %q(<form action="/users/signin")
    assert_nil session[:username]
  end

  def test_sign_out
    get "/", {}, { "rack.session" => { username: "admin" } }
    assert_equal "admin", session[:username]
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    assert_equal "You have been signed out.", session[:message]
    assert_equal 302, last_response.status
    
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:username]
    assert_nil session[:message]
    assert_includes last_response.body, %q(<a class="user_status" href="/users/signin">)
  end

  def test_viewing_text_documents
    create_document "history.txt", "2019 - Ruby 2.7 released."

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "2019 - Ruby 2.7 released."
  end

  def test_viewing_markup_doc
    create_document "about.md", "# Ruby is..."

    get "/about.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_nonexistant_file_error
    get "/notafile.ext"
    assert_equal 302, last_response.status
    assert_equal "notafile.ext does not exist.", session[:message]

    get last_response["Location"] # Request the page that the user was redirected to
    assert_equal 200, last_response.status
    assert_nil session[:message]
  end

  def test_file_edit_form_signed_out
    create_document "changes.txt"

    get "/changes.txt/edit"
    assert_equal "You must be signed in to do that.", session[:message]
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]
  end

  def test_file_edit_form_admin
    create_document "changes.txt"

    get "/changes.txt/edit", {}, admin_session
    assert_equal 200, last_response.status

    assert_includes last_response.body, "Edit content of changes.txt"
    assert_includes last_response.body, %q(<form action="/changes.txt/edit" method="post">)
  end

  def test_updating_document_signed_out
    create_document "changes.txt"

    post "/changes.txt/edit", contents: "new content"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]
    assert_includes last_response.body, "Sign In"

    get "/changes.txt"
    assert_equal 200, last_response.status
    refute_includes last_response.body, "new content"
  end

  def test_updating_document_admin
    post "/changes.txt/edit", {contents: "new content"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_new_doc_form_signed_out
    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]
  end

  def test_new_doc_form_admin
    get "/new", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit">Create)
  end

  def test_create_document_signed_out
    post "/new", filename: "test_file.md"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]

    get "/"
    refute_includes last_response.body, "test_file.md"

    get "/test_file.md"
    assert_equal 302, last_response.status
    assert_equal "test_file.md does not exist.", session[:message]
  end

  def test_create_document_admin
    post "/new", {filename: "test_file.md"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test_file.md has been created.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]

    get "/"
    assert_includes last_response.body, "test_file.md"

    get "/test_file.md"
    assert_equal 200, last_response.status
  end

  def test_new_doc_validation
    post "/new", {filename: "test_file"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "A filename and either .txt or .md extension are required.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]
    assert_includes last_response.body, %q(<button type="submit">Create)

    get "/test_file"
    assert_equal 302, last_response.status
    assert_equal "test_file does not exist.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]

    post "/new", {filename: "test_file.png"}
    assert_equal 302, last_response.status
    assert_equal "A filename and either .txt or .md extension are required.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]
    assert_includes last_response.body, %q(<button type="submit">Create)

    get "/"
    refute_includes last_response.body, "test_file"

    get "/test_file.png"
    assert_equal 302, last_response.status
    assert_equal "test_file.png does not exist.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]

    post "/new", filename: ""
    assert_equal 302, last_response.status
    assert_equal "A filename and either .txt or .md extension are required.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]
    assert_includes last_response.body, %q(<button type="submit">Create)
  end

  def test_delete_file_signed_out
    create_document "test_file.txt"

    get "/"
    assert_includes last_response.body, "test_file.txt"

    post "test_file.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]

    get "/"
    assert_includes last_response.body, "test_file.txt"
  end

  def test_delete_file_admin
    create_document "test_file.txt"

    get "/", {}, admin_session
    assert_includes last_response.body, "test_file.txt"

    post "test_file.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "test_file.txt has been deleted.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]

    get "/"
    refute_includes last_response.body, "test_file.txt"
  end

  def test_duplicate_file_signed_out
    create_document "test_file.txt"

    post "test_file.txt/duplicate"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]

    get "/"
    refute_includes last_response.body, "copy_of_test_file.txt"
  end

  def test_duplicate_file_admin
    create_document "test_file.txt"

    post "test_file.txt/duplicate", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test_file.txt has been duplicated.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]

    get "/"
    assert_includes last_response.body, "copy_of_test_file.txt"
  end

  def test_register_new_user
    write_users_yml_file "{}"

    get "/users/register"
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<form action="/users/register" method="post">)

    post "/users/register", { username: "test_user", password: "test_password" }
    assert_equal "Welcome aboard, test_user!", session[:message]
    assert_equal "test_user", session[:username]
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]
    assert_includes last_response.body, "Signed in as test_user"

    post "/users/signout"
    
    get "/users/signin"
    
    post "/users/signin", { username: "test_user", password: "test_password" }
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:message]
    assert_includes last_response.body, "Signed in as test_user"
  end

  def test_not_found
    get "somethingthat/does/not/exist"
    assert_equal 404, last_response.status
  end

  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.rm_rf(credentials_path)
  end
end
