ENV["RACK_ENV"] = "test"

require "fileutils"

require "minitest/autorun"
require "rack/test"
require "minitest/reporters"
Minitest::Reporters.use!

require_relative "../cms"

class CmsTest < Minitest::Test
  include Rack::Test::Methods

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def app
    Sinatra::Application
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
    assert_includes last_response.body, "<form action=\"/users/signin\""
  end

  def test_sign_in_valid
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Welcome!"

    get "/"
    assert_includes last_response.body, "Signed in as"
    refute_includes last_response.body, "Welcome!"
  end

  def test_invalid_sign_in
    post "/users/signin", username: "test", password: "test"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid credentials"
    assert_includes last_response.body, "<form action=\"/users/signin\""
  end

  def test_sign_out
    post "/users/signout"
    assert_equal 302, last_response.status
    
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have been signed out."
    assert_includes last_response.body, "<a class=\"user_status\" href=\"/users/signin\">"

    get "/"
    refute_includes last_response.body, "You have been signed out."
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

    get last_response["Location"] # Request the page that the user was redirected to
    assert_equal 200, last_response.status
    assert_includes last_response.body, "notafile.ext does not exist."

    get "/"
    refute_includes last_response.body, "notafile.ext does not exist."
  end

  def test_file_edit_form
    create_document "changes.txt"

    get "/changes.txt/edit"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Edit content of changes.txt"
    assert_includes last_response.body, "<form action=\"/changes.txt/edit\" method=\"post\">"
  end

  def test_updating_document
    post "/changes.txt/edit", contents: "new content" # pass in param key/value
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "changes.txt has been updated."

    get "/"
    refute_includes last_response.body, "changes.txt has been updated."

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_new_doc_form
    get "/new"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<button type=\"submit\">Create"
  end

  def test_create_document
    post "/new", filename: "test_file.md"
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "test_file.md has been created."

    get "/"
    assert_includes last_response.body, "test_file.md"
    refute_includes last_response.body, "test_file.md has been created."

    get "/test_file.md"
    assert_equal 200, last_response.status
  end

  def test_new_doc_validation
    post "/new", filename: "test_file"
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "A filename and extension are required."
    assert_includes last_response.body, "<button type=\"submit\">Create"

    get "/"
    refute_includes last_response.body, "test_file"

    get "/test_file"
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes  last_response.body, "test_file does not exist"

    post "/new", filename: ""
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "A filename and extension are required."
    assert_includes last_response.body, "<button type=\"submit\">Create"
  end

  def test_delete_file
    create_document "test_file.txt"

    get "/"
    assert_includes last_response.body, "test_file.txt"

    post "test_file.txt/delete"
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "test_file.txt has been deleted."

    get "/"
    refute_includes last_response.body, "test_file.txt"
  end

  def test_not_found
    get "somethingthat/does/not/exist"
    assert_equal 404, last_response.status
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end
end
