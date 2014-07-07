require 'nokogiri'
require 'open-uri'

def get_sb_admin_login_page
  doc = Nokogiri::HTML(open('https://raw.githubusercontent.com/IronSummitMedia/startbootstrap/master/templates/sb-admin-v2/login.html'))

  # Do funky things with it using Nokogiri::XML::Node methods...

  ####
  # Search for nodes by css
  doc.css('body > .container').to_html
end

def get_sb_admin_layout
  doc = Nokogiri::HTML(open('https://raw.githubusercontent.com/IronSummitMedia/startbootstrap/master/templates/sb-admin-v2/blank.html'))

  doc.css('#wrapper').search("#page-wrapper").first.children.remove
  doc.css('#wrapper').to_html.sub('<div id="page-wrapper"></div>', '<div id="page-wrapper"><%= yield %></div>')
end

def get_bootstrap_files
  get "https://raw.githubusercontent.com/twbs/bootstrap/master/dist/css/bootstrap.css", "vendor/assets/stylesheets/bootstrap.css"
  get "https://raw.githubusercontent.com/twbs/bootstrap/master/dist/js/bootstrap.js",   "vendor/assets/javascripts/bootstrap.js"
  get "https://raw.githubusercontent.com/twbs/bootstrap/master/dist/fonts/glyphicons-halflings-regular.eot", "vendor/assets/fonts/glyphicons-halflings-regular.eot"
  get "https://raw.githubusercontent.com/twbs/bootstrap/master/dist/fonts/glyphicons-halflings-regular.svg", "vendor/assets/fonts/glyphicons-halflings-regular.svg"
  get "https://raw.githubusercontent.com/twbs/bootstrap/master/dist/fonts/glyphicons-halflings-regular.ttf", "vendor/assets/fonts/glyphicons-halflings-regular.ttf"
  get "https://raw.githubusercontent.com/twbs/bootstrap/master/dist/fonts/glyphicons-halflings-regular.woff", "vendor/assets/fonts/glyphicons-halflings-regular.woff"
end

def setup_default(resource)
  generate "devise #{resource}"
  generate "devise:views #{resource.pluralize}"

  generate :controller, "#{resource.pluralize}/base --helper=false --assets=false --controller-specs=false --no-view-specs"
  inject_into_file "app/controllers/#{resource.pluralize}/base_controller.rb", after: " < ApplicationController\n" do <<-CODE
    before_action :authenticate_#{resource}!
    layout '#{resource.pluralize}'
CODE
  end
  run "rmdir app/views/#{resource.pluralize}/base"

  generate :controller, "#{resource.pluralize}/dashboard index --helper=false --assets=false --controller-specs=false --no-view-specs"
  gsub_file "app/controllers/#{resource.pluralize}/dashboard_controller.rb", '< ApplicationController', "< #{resource.pluralize.capitalize}::BaseController"
  gsub_file "config/routes.rb", "get 'dashboard/index'", 'get "/" => "dashboard#index", as: :dashboard'

  # update factory girls
  inject_into_file "spec/factories/#{resource.pluralize}.rb", after: "factory :#{resource} do\n" do <<-CODE
    sequence(:email) { |n| "email\#{n}@example.com"}
    password "password"
CODE
  end
end



# ----- Setting rvm hidden files ---------------------------------------------------------------------

puts
say_status "RVM", "setting ruby version and gemset...\n", :yellow
puts '-'*80, ''; sleep 0.25

run "rvm --ruby-version use 2.1.1@#{app_name} --create"



# ----- Setting rvm hidden files ---------------------------------------------------------------------

puts
say_status "Gemfile", "adding gems to Gemfile...\n", :yellow
puts '-'*80, ''; sleep 0.25

gsub_file 'Gemfile', "gem 'sqlite3'", ""

gem "slim-rails"
gem "html2slim"
gem "modernizr-rails"
gem "kaminari"
gem "cocoon"
gem "simple_form"
gem "font-awesome-rails"

gem "devise"
# gem "cancan"
gem "friendly_id", '~> 5.0.0'
gem "state_machine"

gem "redis-store"
gem "redis-rails"

gem "carrierwave"
gem "fog"
gem "mini_magick"

gem "asset_sync"

gem "high_voltage"

gem "puma"

gem "sidekiq"

gem_group :development do
  gem "bullet"
  gem 'premailer-rails'
  gem "pry-rails"
  gem "better_errors"
  gem "binding_of_caller"
  gem "meta_request"
  gem "quiet_assets"
  gem "awesome_print"
end

gem_group :development, :test do
  gem "sqlite3"

  gem "factory_girl_rails"
  gem "rspec-rails"
  gem "dotenv-rails"
  gem "dotenv-deployment"
end

gem_group :test do
  gem "simplecov", :require => false
end

gem_group :production do
  # TODO if it is heroku
  gem "newrelic_rpm"
  gem "heroku-deflater"
  gem "rails_12factor"
  gem "pg"
end

inject_into_file 'Gemfile', after: "source 'https://rubygems.org'\n" do <<-CODE

ruby '2.1.1'
CODE
end

run "bundle install"



# ----- Setting each gems ---------------------------------------------------------------------

puts
say_status "Gemfile", "install gem initializers and config files ...\n", :yellow
puts '-'*80, ''; sleep 0.25

run "rails generate devise:install"
run "rails generate rspec:install"
run "rails generate simple_form:install --bootstrap"
run "rails generate friendly_id"

gsub_file "config/initializers/devise.rb", "# config.scoped_views = false", "config.scoped_views = true"

initializer 'asset_sync.rb', <<-CODE
AssetSync.configure do |config|
  config.fog_provider = 'AWS'
  config.aws_access_key_id = ENV['S3_KEY']
  config.aws_secret_access_key = ENV['S3_SECRET']
  config.fog_directory = ENV['S3_ASSETS_BUCKET_NAME']
  config.fog_region = ENV['S3_REGION']
  config.gzip_compression = true
end
CODE

initializer 'carrierwave.rb', <<-CODE
module CarrierWave
  module RMagick
    def quality(percentage)
      manipulate! do |img|
        img.write(current_path){ self.quality = percentage } unless img.quality == percentage
        img = yield(img) if block_given?
        img
      end
    end
  end
end

CarrierWave.configure do |config|
  if Rails.env.test? || Rails.env.development?
    config.storage = :file
    config.enable_processing = true
  else
    config.fog_credentials = {
      :provider              => 'AWS',
      :aws_access_key_id     => ENV['S3_KEY'],
      :aws_secret_access_key => ENV['S3_SECRET'],
      :region                => ENV['S3_REGION']
    }

    config.storage = :fog
    config.enable_processing = true
    config.fog_directory    = ENV['S3_BUCKET_NAME']
    config.fog_public       = false
    config.fog_attributes   = {'Cache-Control'=>'max-age=315576000'}  # optional, defaults to {}
  end
end
CODE

initializer 'redis_store.rb', <<-CODE
if !Rails.env.test?
  require "redis-store"
  redis_url = ENV["REDISTOGO_URL"] || "redis://127.0.0.1:6379/0/#{app_name}"
  Rails.application.config.cache_store = :redis_store, redis_url
  Rails.application.config.session_store :redis_store, :servers => redis_url
end
CODE

append_file 'config/initializers/assets.rb', <<-CODE
Rails.application.config.assets.precompile += %w( admins.js admins.css users.js users.css *.eot *.svg *.woff *.ttf)
CODE

run "rm config/initializers/session_store.rb"

run 'mkdir app/views/pages'
run 'mkdir spec/mailers'

prepend_file 'spec/rails_helper.rb', "require 'simplecov'\nSimpleCov.start\n"

file ".env", <<-CODE
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_DOMAIN=gmail.com
SMTP_USER_NAME=xxxxx@gmail.com
SMTP_PASSWORD=xxxxx
S3_ASSETS_BUCKET_NAME=xxxxx-assets-dev
S3_BUCKET_NAME=xxxxx-dev
S3_KEY=xxxxx
S3_REGION=ap-southeast-1
S3_SECRET=xxxxx
CODE

run "cp .env config/.env.development.example"



# ----- Setting application.rb, development.rb, production.rb ---------------------------------------------------------------------

puts
say_status "application.rb", "Update rails environment configuration ...\n", :yellow
puts '-'*80, ''; sleep 0.25

application(nil, env: "development") do
  'config.action_mailer.default_url_options={host: "http://localhost:3000"}'
end

application(nil, env: "test") do
  'config.action_mailer.default_url_options={host: "http://localhost:3000"}'
end

application(nil, env: "production") do
  "config.action_mailer.default_url_options={host: 'http://#{app_name}-herokuapp.com'}"
end

application do <<-CODE
config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address:              ENV["SMTP_SERVER"],
    port:                 ENV["SMTP_PORT"],
    domain:               ENV["SMTP_DOMAIN"],
    user_name:            ENV["SMTP_USER_NAME"],
    password:             ENV["SMTP_PASSWORD"],
    authentication:       'plain',
    enable_starttls_auto: true
  }
CODE
end



# ----- Setup bootstrap ---------------------------------------------------------------------

puts
say_status "bootstrap", "Downloading bootstrap files and update asset pipeline ...\n", :yellow
puts '-'*80, ''; sleep 0.25

get_bootstrap_files

gsub_file "app/assets/javascripts/application.js", "//= require_tree .", ""
gsub_file "app/assets/stylesheets/application.css", "*= require_tree .", "*= require bootstrap\n *= require font-awesome\n *= require font"

file "vendor/assets/stylesheets/font.css.scss", <<-CODE
@font-face {
  font-family: 'Glyphicons Halflings';
  src: asset-url('glyphicons-halflings-regular.eot');
  src: asset-url('glyphicons-halflings-regular.eot?#iefix') format('embedded-opentype'),
       asset-url('glyphicons-halflings-regular.woff') format('woff'),
       asset-url('glyphicons-halflings-regular.ttf') format('truetype'),
       asset-url('glyphicons-halflings-regular.svg#glyphicons_halflingsregular') format('svg');
}

.fa {
  padding: 3px 0px;
}
CODE



# ----- Generate user devise ---------------------------------------------------------------------

puts
say_status "devise", "Generating user ...\n", :yellow
puts '-'*80, ''; sleep 0.25

setup_default("user")

file_name = Dir["db/migrate/*_devise_create_users.rb"].first

gsub_file "app/models/user.rb", ", :registerable", ", :registerable, :confirmable"

gsub_file file_name, "# t.string   :confirmation_token", "t.string   :confirmation_token"
gsub_file file_name, "# t.datetime :confirmed_at", "t.datetime :confirmed_at"
gsub_file file_name, "# t.datetime :confirmation_sent_at", "t.datetime :confirmation_sent_at"
gsub_file file_name, "# t.string   :unconfirmed_email", "t.string   :unconfirmed_email"
gsub_file file_name, "# add_index :users, :confirmation_token", " add_index :users, :confirmation_token"

run "cp app/assets/javascripts/application.js app/assets/javascripts/users.js"
run "cp app/assets/stylesheets/application.css app/assets/stylesheets/users.css"

inject_into_file "app/assets/javascripts/users.js", "\n//= require bootstrap", after: "//= require jquery_ujs"

file "app/views/layouts/users.html.erb", <<-CODE
<!DOCTYPE html>
<html>
  <head>
    <title>#{app_name.capitalize}</title>
    <%= stylesheet_link_tag    'users', media: 'all', 'data-turbolinks-track' => true %>
    <%= javascript_include_tag :modernizr %>
    <%= csrf_meta_tags %>
  </head>
  <body class="controller-<%= params[:controller] %> action-<%= params[:action] %>">
    <%= yield %>
    <%= javascript_include_tag :users %>
  </body>
</html>
CODE


# ----- Generate admin devise ---------------------------------------------------------------------

puts
say_status "devise", "Generating admin ...\n", :yellow
puts '-'*80, ''; sleep 0.25

setup_default("admin")

gsub_file "app/models/admin.rb", ", :registerable", ""

get "https://raw.githubusercontent.com/IronSummitMedia/startbootstrap/master/templates/sb-admin-v2/css/sb-admin.css", "vendor/assets/stylesheets/admins/sb-admin.css"

# run "cp app/assets/stylesheets/application.css app/assets/stylesheets/admins.css"
run "cp app/assets/javascripts/application.js app/assets/javascripts/admins.js"
run "cp app/assets/stylesheets/application.css app/assets/stylesheets/admins.css"

inject_into_file "app/assets/stylesheets/admins.css", "*= require admins/sb-admin\n ", before: "*= require_self"

inject_into_file "app/assets/javascripts/admins.js", "//= require bootstrap\n//= require cocoon\n", after: "//= require jquery_ujs\n"

layout_content = get_sb_admin_layout

file "app/views/layouts/admins.html.erb", <<-CODE
<!DOCTYPE html>
<html>
  <head>
    <title>Admin Panel</title>
    <%= stylesheet_link_tag    'admins', media: 'all', 'data-turbolinks-track' => true %>
    <%= javascript_include_tag :modernizr %>
    <%= csrf_meta_tags %>
  </head>
  <body class="controller-<%= params[:controller] %> action-<%= params[:action] %>">
    #{layout_content}
    <%= javascript_include_tag :admins %>
  </body>
</html>
CODE

# TODO wrap the generated devise template by sbadmin page
sign_in_content = get_sb_admin_login_page
file "app/views/admins/sessions/new_styled.html.erb", sign_in_content



# ----- Setting layout and stylesheets ---------------------------------------------------------------------

puts
say_status "application.html.erb", "Update layout files ...\n", :yellow
puts '-'*80, ''; sleep 0.25

inject_into_file "app/controllers/application_controller.rb", after: "protect_from_forgery with: :exception\n" do <<-CODE
  layout :layout_by_resource
  protected

  def layout_by_resource
    if devise_controller? && resource_name == :user
      "users"
    elsif devise_controller? && resource_name == :admin
      # TODO without menu bar
      "admins"
    else
      "users"
    end
  end
CODE
end

generate :controller, "home index --helper=false --assets=false --controller-specs=false"
route "root to: 'home#index'"

rake "db:migrate"



# ----- Slim ---------------------------------------------------------------------

puts
say_status "slim", "changing all erb to slim ...\n", :yellow
puts '-'*80, ''; sleep 0.25

run "erb2slim -d app/views"



# ----- Updating .gitignore ---------------------------------------------------------------------

puts
say_status ".gitignore", "adding sensitive files ...\n", :yellow
puts '-'*80, ''; sleep 0.25

run 'cp config/database.yml config/database.example'
run "echo 'config/database.yml' >> .gitignore"
run "echo '.env' >> .gitignore"
run "echo '.env' >> .gitignore"
run "echo '/public/uploads' >> .gitignore"



# ----- README ---------------------------------------------------------------------

puts
say_status "README.md", "updating readme ...\n", :yellow
puts '-'*80, ''; sleep 0.25

run "rm README.rdoc"
file "README.md", <<-CODE
Project
========


Gem Installed
========


CODE



# ----- Git ---------------------------------------------------------------------

puts
say_status "git", "git init ...\n", :yellow
puts '-'*80, ''; sleep 0.25

git :init
git add: ". -A"
git commit: %Q{ -m 'Initial commit' }



say <<-eos
============================================================================
  Your new Rails application is ready to go.
  Don't forget to scroll up for important messages from installed generators.
eos
