require 'nokogiri'
require 'open-uri'

def update_gemfile
  gsub_file 'Gemfile', "gem 'sqlite3'", ""

  # include gems into Gemfile
  gem "slim-rails"
  gem "html2slim"
  gem "modernizr-rails"
  gem "kaminari"
  gem "cocoon"
  gem "simple_form"
  gem 'bootstrap-sass', '~> 3.2.0'
  gem 'autoprefixer-rails'
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
end

def setup_gem_dependency_files
  run "rails generate devise:install"
  run "rails generate rspec:install"
  run "rails generate simple_form:install --bootstrap"
  run "rails generate friendly_id"

  gsub_file "config/initializers/devise.rb", "# config.scoped_views = false", "config.scoped_views = true"

  # Gem config files
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
Rails.application.config.assets.precompile += %w( admins.js admins.css users.js users.css)
  CODE

  run "rm config/initializers/session_store.rb"

  run 'mkdir app/views/pages'
  run 'mkdir spec/mailers'

  prepend_file 'spec/rails_helper.rb', "require 'simplecov'\nSimpleCov.start\n"

  file ".env", <<-TEXT
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
  TEXT

  run "cp .env config/.env.development.example"
end

def update_gitignore
  run 'cp config/database.yml config/database.example'
  run "echo 'config/database.yml' >> .gitignore"
  run "echo '.env' >> .gitignore"
  run "echo '.env' >> .gitignore"
  run "echo '/public/uploads' >> .gitignore"
end

def setup_devise_models
  setup_admins
  setup_users
end

def setup_users
  setup_default("user")

  file_name = Dir["db/migrate/*_devise_create_users.rb"].first

  gsub_file "app/models/admin.rb", ", :registerable", ", :registerable, :confirmable"

  gsub_file file_name, "# t.string   :confirmation_token", "t.string   :confirmation_token"
  gsub_file file_name, "# t.datetime :confirmed_at", "t.datetime :confirmed_at"
  gsub_file file_name, "# t.datetime :confirmation_sent_at", "t.datetime :confirmation_sent_at"
  gsub_file file_name, "# t.string   :unconfirmed_email", "t.string   :unconfirmed_email"
  gsub_file file_name, "# add_index :users, :confirmation_token", " add_index :users, :confirmation_token"

  # run "cp app/assets/stylesheets/application.css app/assets/stylesheets/users.css"
  run "cp app/assets/javascripts/application.js app/assets/javascripts/users.js"
  file "app/assets/stylesheets/users.css", <<-CODE
  @import 'bootstrap-sprockets';
  @import 'bootstrap';
  @import 'font-awesome';
CODE

  # gsub_file "app/assets/stylesheets/users.css", "*= require_tree .", ""
  gsub_file "app/assets/javascripts/admins.js", "//= require jquery_ujs\n", "//= require jquery_ujs\n//= require bootstrap-sprockets\n"

  file "app/views/layouts/users.html.erb", <<-CODE
<html>
  <head>
    <title>#{app_name.capitalize}</title>
    <%= stylesheet_link_tag    'users', media: 'all', 'data-turbolinks-track' => true %>
    <%= javascript_include_tag :modernizr %>
    <%= csrf_meta_tags %>
  </head>
  <body>
    <%= yield %>
    <%= javascript_include_tag :users %>
  </body>
</html>
  CODE
end

def setup_admins
  setup_default("admin")

  gsub_file "app/models/admin.rb", ", :registerable", ""

  get "https://raw.githubusercontent.com/IronSummitMedia/startbootstrap/master/templates/sb-admin-v2/css/sb-admin.css", "vendor/assets/stylesheets/admins/sb-admin.css"

  # run "cp app/assets/stylesheets/application.css app/assets/stylesheets/admins.css"
  run "cp app/assets/javascripts/application.js app/assets/javascripts/admins.js"
  file "app/assets/stylesheets/admins.css", <<-CODE
  @import 'bootstrap-sprockets';
  @import 'bootstrap';
  @import 'font-awesome';
  @import 'admins/sb-admin';
CODE

  # gsub_file "app/assets/stylesheets/admins.css", "*= require_tree .", "*= require admins/sb-admin"
  gsub_file "app/assets/javascripts/admins.js", "//= require jquery_ujs\n", "//= require jquery_ujs\n//= require bootstrap-sprockets\n//= require cocoon\n"

  layout_content = get_sb_admin_layout

  file "app/views/layouts/admins.html.erb", <<-CODE
<html>
  <head>
    <title>Admin Panel</title>
    <%= stylesheet_link_tag    'admins', media: 'all', 'data-turbolinks-track' => true %>
    <%= javascript_include_tag :modernizr %>
    <%= csrf_meta_tags %>
  </head>
  <body>
    #{layout_content}
    <%= javascript_include_tag :admins %>
  </body>
</html>
  CODE

  # TODO wrap the generated devise template by sbadmin page
  sign_in_content = get_sb_admin_login_page
  file "app/views/admins/sessions/new_styled.html.erb", sign_in_content
end

def setup_default(resource)
  # Generate users devise
  generate "devise #{resource}"
  generate "devise:views #{resource.pluralize}"
  run "erb2slim -d app/views"

  # generate controllers
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

  # file "app/views/layouts/#{resource.pluralize}.html.erb", <<-CODE
  # CODE
end

def update_application_environment
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
end

def update_application_layout
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

  gsub_file "app/assets/javascripts/application.js", "//= require_tree .", ""
end

def update_readme
  run "rm README.rdoc"
  file "README.md", <<-TEXT
Project
========


Gem Installed
========


TEXT
end

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


# setup rvm gemset
run "rvm --ruby-version use 2.1.1@#{app_name} --create"

update_gemfile

setup_gem_dependency_files

update_application_environment

update_application_layout

setup_devise_models

# Generate landing page
generate :controller, "home index --helper=false --assets=false --controller-specs=false"
route "root to: 'home#index'"

rake "db:migrate"

update_gitignore

update_readme


git :init
git add: ". -A"
git commit: %Q{ -m 'Initial commit' }


say <<-eos
============================================================================
  Your new Rails application is ready to go.
  Don't forget to scroll up for important messages from installed generators.
eos
