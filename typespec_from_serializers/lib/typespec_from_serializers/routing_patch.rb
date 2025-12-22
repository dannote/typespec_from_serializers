# frozen_string_literal: true

require "action_dispatch/routing/mapper"
require "action_dispatch/journey/route"

# Internal: Minimal surgical patches to ActionDispatch routing for TypeSpec metadata support.
#
# This module patches Rails routing to support the `type:` parameter for specifying
# path parameter types without interfering with Rails' route matching or URL generation.
#
# The type metadata is stored in route defaults under the :__typespec_types key and
# explicitly excluded from route requirements to prevent it from affecting routing behavior.
#
# Examples
#
#   # In routes.rb
#   resources :users, type: { id: Integer }
#   get '/posts/:id', to: 'posts#show', type: { id: Integer }
#
# The patches work at three interception points:
# 1. Mapper::Base#match - for GET/POST/PATCH/etc methods
# 2. Mapper::Resources#resources - for resources/resource methods
# 3. Journey::Route#requirements - filters metadata from route requirements
module TypeSpecFromSerializers
  # Internal: Shared logic for moving type metadata from options to defaults.
  module RoutingPatchHelpers
    module_function

    # Internal: Moves type: parameter from route options to defaults[:__typespec_types].
    #
    # This ensures type metadata is stored but doesn't interfere with routing.
    #
    # options - Hash of route options (will be modified in place)
    #
    # Returns the modified options Hash
    def move_type_to_defaults!(options)
      return options unless options.key?(:type)

      types = options.delete(:type)
      options[:defaults] = (options[:defaults] || {}).merge(__typespec_types: types)
      options
    end
  end

  # Internal: Patches ActionDispatch::Routing::Mapper::Base to intercept match method.
  #
  # Intercepts the low-level match method used by get, post, patch, delete, etc.
  module MapperPatch
    def match(path, *rest, &block)
      options = rest.last.is_a?(Hash) ? rest.pop.dup : {}
      RoutingPatchHelpers.move_type_to_defaults!(options)

      rest.push(options) unless options.empty?
      super(path, *rest, &block)
    end
  end

  # Internal: Patches ActionDispatch::Routing::Mapper::Resources to intercept resources method.
  #
  # Intercepts the resources/resource DSL methods to support type: parameter.
  module ResourcesPatch
    def resources(*resources, &block)
      options = resources.extract_options!
      RoutingPatchHelpers.move_type_to_defaults!(options)

      resources.push(options) unless options.empty?
      super(*resources, &block)
    end
  end

  # Internal: Patches ActionDispatch::Journey::Route to filter type metadata from requirements.
  #
  # The requirements method is used for route matching and URL generation.
  # We exclude :__typespec_types to ensure it doesn't affect routing behavior.
  module RoutePatch
    def requirements
      super.except(:__typespec_types)
    end
  end
end

# Apply patches to ActionDispatch
ActionDispatch::Routing::Mapper::Base.prepend(TypeSpecFromSerializers::MapperPatch)
ActionDispatch::Routing::Mapper::Resources.prepend(TypeSpecFromSerializers::ResourcesPatch)
ActionDispatch::Journey::Route.prepend(TypeSpecFromSerializers::RoutePatch)
