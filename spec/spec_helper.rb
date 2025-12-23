require "simplecov"
SimpleCov.start {
  add_filter "/spec/"
  add_filter "/playground/"
}

ENV["RACK_ENV"] = "development"

# Add playground to load path so specs can require vanilla/config/boot
$LOAD_PATH.push File.expand_path("../playground", __dir__)

# Require oj_serializers for tests that need it
require "oj_serializers"

require "rspec/given"

begin
  require "pry-byebug"
rescue LoadError
end
