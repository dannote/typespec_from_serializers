<h1 align="center">
TypeSpec From Serializers
<p align="center">
<a href="https://github.com/dannote/typespec_from_serializers/actions"><img alt="Build Status" src="https://github.com/dannote/typespec_from_serializers/workflows/build/badge.svg"/></a>
<a href="https://rubygems.org/gems/typespec_from_serializers"><img alt="Gem Version" src="https://img.shields.io/gem/v/typespec_from_serializers.svg?colorB=e9573f"/></a>
<a href="https://github.com/dannote/typespec_from_serializers/blob/master/LICENSE.txt"><img alt="License" src="https://img.shields.io/badge/license-MIT-428F7E.svg"/></a>
</p>
</h1>

[oj]: https://github.com/ohler55/oj
[oj_serializers]: https://github.com/ElMassimo/oj_serializers
[types_from_serializers]: https://github.com/ElMassimo/types_from_serializers
[ams]: https://github.com/rails-api/active_model_serializers
[Rails]: https://github.com/rails/rails
[Issues]: https://github.com/dannote/typespec_from_serializers/issues?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc
[Discussions]: https://github.com/dannote/typespec_from_serializers/discussions
[TypeSpec]: https://typespec.io
[Vite Ruby]: https://github.com/ElMassimo/vite_ruby
[vite-plugin-full-reload]: https://github.com/ElMassimo/vite-plugin-full-reload
[base_serializers]: https://github.com/dannote/typespec_from_serializers#base_serializers
[config]: https://github.com/dannote/typespec_from_serializers#configuration-%EF%B8%8F

Automatically generate TypeSpec descriptions from your [JSON serializers][oj_serializers].

_Currently, this library targets [`oj_serializers`][oj_serializers] and `ActiveRecord` in [Rails] applications_.

## Why? 🤔

It's easy for the backend and the frontend to become out of sync. Traditionally, preventing bugs
requires writing extensive integration tests.

[TypeSpec] is a great tool to catch this kind of bugs and mistakes, as it can define precise API
specifications and detect mismatches, but writing these specifications manually is cumbersome,
and they can become stale over time, giving a false sense of confidence.

This library takes advantage of the declarative nature of serializer libraries such as
[`active_model_serializers`][ams] and [`oj_serializers`][oj_serializers], extending them to allow
embedding type information, as well as inferring types from the SQL schema when available.

The project builds on [`types_from_serializers`][types_from_serializers] by ElMassimo, originally
designed for TypeScript definitions, adapting it to generate [TypeSpec] specifications instead.
This shift broadens interoperability with modern API specification tools and leverages TypeSpec’s
strengths in defining RESTful APIs, including route generation from Rails applications, to create
comprehensive, type-safe API descriptions.

As a result, it's possible to easily detect mismatches between the backend and the frontend, as
well as make the fields and endpoints more discoverable and provide great autocompletion in tools
that support TypeSpec, without having to manually write the specifications.

## Features ⚡️

- Start simple, no additional syntax required
- Infers types from Sorbet method signatures when available
- Infers types from a related `ActiveRecord` model, using the SQL schema
- Understands TypeSpec native types and how to map SQL columns: `string`, `boolean`, etc
- Automatically types [associations](https://github.com/ElMassimo/oj_serializers#associations-dsl-),
importing the generated types for the referenced serializers
- Detects [conditional attributes](https://github.com/ElMassimo/oj_serializers#rendering-an-attribute-conditionally)
and marks them as optional: `name?: string`
- Fallback to a custom interface using `typespec_from`
- Supports custom types and automatically adds the necessary imports
- Generates TypeSpec route interfaces from Rails routes, mapping controllers and actions to HTTP operations
- **Namespace support** with automatic reserved keyword handling - uses your Rails app name as namespace by default, avoiding conflicts with TypeSpec keywords
- **Smart field name escaping** - automatically escapes field names that conflict with TypeSpec keywords using backticks

## Demo 🎬

For a database schema like [this one](https://github.com/dannote/typespec_from_serializers/blob/main/playground/vanilla/db/schema.rb):

<details>
  <summary>DB Schema</summary>

```ruby
  create_table "composers", force: :cascade do |t|
    t.text "first_name"
    t.text "last_name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "songs", force: :cascade do |t|
    t.text "title"
    t.integer "composer_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "video_clips", force: :cascade do |t|
    t.text "title"
    t.text "youtube_id"
    t.integer "song_id"
    t.integer "composer_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end
```
</details>

and a serializer like this:

```ruby
class VideoSerializer < BaseSerializer
  object_as :video, model: :VideoClip

  attributes :id, :created_at, :title, :youtube_id

  type :string, optional: true
  def youtube_url
    "https://www.youtube.com/watch?v=#{video.youtube_id}" if video.youtube_id
  end

  has_one :song, serializer: SongSerializer
end
```

this fork generates a TypeSpec model like:

```typespec
import "./Song.tsp";

namespace SampleApp {
  model Video {
    id: int32;
    createdAt: utcDateTime;
    title?: string;
    youtubeId?: string;
    youtubeUrl?: string;
    song: Song;
  }
}
```

> **Note**
>
> This reflects the default setup for TypeSpec generation. You can customize everything—check out the [configuration options][config] for full control!

## Automatic Type Inference ✨

Types are inferred from enums and SQL schema. Use `type:` for custom methods:

```ruby
class Task < ApplicationRecord
  enum status: {pending: 0, in_progress: 1, completed: 2}
end

class TaskSerializer < BaseSerializer
  attributes :title, :status  # SQL + enum → string, union

  attribute :assignee_name, type: :string
  def assignee_name = task.assignee&.full_name || "Unassigned"

  attribute :notes, type: :string, optional: true
  def notes = task.internal_notes

  attribute :external_id, type: "string | int32"
  def external_id = task.external_system_id || task.legacy_id

  # Sorbet sigs auto-infer complex types too
  attribute :watchers
  sig { returns(T::Array[{id: Integer, email: String}]) }
  def watchers = task.watchers.map { |w| {id: w.id, email: w.email} }
end
```

**Generates:**

```typespec
model Task {
  title: string;
  status: "pending" | "in_progress" | "completed";
  assigneeName: string;
  notes?: string;
  externalId: string | int32;
  watchers: {id: int32, email: string}[];
}
```

## Installation 💿

Add this line to your application's Gemfile:

```ruby
gem 'typespec_from_serializers'
```

And then run:

    $ bundle install

## Usage 🚀

To get started, [create a `BaseSerializer`](https://github.com/dannote/typespec_from_serializers/blob/main/playground/vanilla/app/serializers/base_serializer.rb) that extends [`Oj::Serializer`][oj_serializers], and include the `TypeSpecFromSerializers::DSL::Serializer` module.

```ruby
# app/serializers/base_serializer.rb

class BaseSerializer < Oj::Serializer
  include TypeSpecFromSerializers::DSL::Serializer
end
```

> **Note**
>
> You can customize this behavior using [`base_serializers`][base_serializers].

> **Warning**
>
> All serializers should extend one of the [`base_serializers`][base_serializers], or they won't be
detected.


### SQL Attributes

In most cases, you'll want to let `TypeSpecFromSerializers` infer the types from the [SQL schema](https://github.com/dannote/typespec_from_serializers/blob/main/playground/vanilla/db/schema.rb).

If you are using `ActiveRecord`, the model related to the serializer will be inferred can be inferred from the serializer name:

```ruby
UserSerializer => User
```

It can also be inferred from an [object alias](https://github.com/ElMassimo/oj_serializers#using-a-different-alias-for-the-internal-object) if provided:

```ruby
class PersonSerializer < BaseSerializer
  object_as :user
```

In cases where we want to use a different alias, you can provide the model name explicitly:

```ruby
class PersonSerializer < BaseSerializer
  object_as :person, model: :User
```

### Explicit Type Annotations

When you want to be more strict than the SQL schema, or for attributes that are methods in the model, you can explicitly specify types:

```ruby
  attributes(
    name: {type: :string},
    status: {type: :Status}, # a custom type in ~/typespec/Status.tsp
  )
```

### Type Declarations

Use the `type` helper to declare types for serializer methods. It accepts TypeSpec type symbols (`:string`, `:boolean`) and plain Ruby classes (`String`, `Integer`):

```ruby
class ComposerSerializer < BaseSerializer
  # TypeSpec type symbol
  type :boolean
  def active
    object.status == "active"
  end

  # Ruby class
  type String
  def full_name
    [object.first_name, object.last_name].join(" ")
  end
end
```

This generates:

```typespec
model Composer {
  active: boolean;
  fullName: string;
}
```

If you're using Sorbet, the `type` helper also accepts Sorbet type annotations (`T.nilable`, `T::Array`, etc.):

```ruby
type T.nilable(Integer)
def age
  object.age
end

type T::Array[String]
def tags
  ["classical", "baroque"]
end
```

> **Note**
>
> When specifying a type, [`attribute`](https://github.com/ElMassimo/oj_serializers#serializer_attributes) will be called automatically.

### Sorbet Type Inference

`TypeSpecFromSerializers` automatically infers types from [Sorbet](https://sorbet.org) method signatures when `sorbet-runtime` is available. This provides type safety without requiring manual type annotations in your serializers.

Add `sorbet-runtime` to your Gemfile:

```ruby
gem 'sorbet-runtime'
```

Then add Sorbet signatures to your models or serializers:

```ruby
class Composer < ApplicationRecord
  extend T::Sig

  sig { returns(String) }
  def name
    [first_name, last_name].compact.join(" ")
  end

  sig { returns(T.nilable(String)) }
  def bio
    # Returns optional string
  end

  sig { returns(T::Array[String]) }
  def tags
    ["classical", "baroque"]
  end
end
```

Now when you use these attributes in your serializer, types are inferred automatically:

```ruby
class ComposerSerializer < BaseSerializer
  attributes :name, :bio, :tags
end
```

This generates:

```typespec
model Composer {
  name: string;
  bio?: string;
  tags: string[];
}
```


### Fallback Attributes

You can also specify `typespec_from` to provide a TypeSpec model that should
be used to obtain the field types:

```ruby
class LocationSerializer < BaseSerializer
  object_as :location, typespec_from: :GoogleMapsLocation

  attributes(
    :lat,
    :lng,
  )
end
```

```typespec
import "./typespec/GoogleMapsLocation.tsp";

model Location {
  lat: GoogleMapsLocation.lat::type;
  lng: GoogleMapsLocation.lng::type;
}
```

## Generation 📜

To get started, run `bin/rails s` to start the `Rails` development server.

`TypeSpecFromSerializers` will automatically register a `Rails` reloader, which
detects changes to serializer files, and will generate code on-demand only for
the modified files.

It can also detect when new serializer files are added, or removed, and update
the generated code accordingly.

### Manually

To generate types manually, use the rake task:

```
bundle exec rake typespec_from_serializers:generate
```

or if you prefer to do it manually from the console:

```ruby
require "typespec_from_serializers/generator"

TypeSpecFromSerializers.generate(force: true)
```

### OpenAPI Generation 📄

`TypeSpecFromSerializers` can compile your generated TypeSpec files to OpenAPI 3.0 specifications, enabling integration with API documentation tools, client generators, and testing frameworks.

#### Setup

First, install the required TypeSpec dependencies:

```bash
bundle exec rake typespec_from_serializers:setup
```

#### Compiling to OpenAPI

Generate an OpenAPI specification from your TypeSpec files:

```bash
bundle exec rake typespec_from_serializers:compile_openapi
```

The generated OpenAPI spec will be available in your `typespec/` directory and can be used with tools like Swagger UI, Redoc, or API client generators.

### With [`vite-plugin-full-reload`][vite-plugin-full-reload] ⚡️

When using _[Vite Ruby]_, you can add [`vite-plugin-full-reload`][vite-plugin-full-reload]
to automatically reload the page when modifying serializers, causing the Rails
reload process to be triggered, which is when generation occurs.

```ts
// vite.config.tsp
import { defineConfig } from 'vite'
import ruby from 'vite-plugin-ruby'
import reloadOnChange from 'vite-plugin-full-reload'

defineConfig({
  plugins: [
    ruby(),
    reloadOnChange(['app/serializers/**/*.rb'], { delay: 200 }),
  ],
})
```

As a result, when modifying a serializer and hitting save, the type for that
serializer will be updated instantly!

### Routes Generation 🛤️

In addition to generating TypeSpec models from serializers, `TypeSpecFromSerializers` can generate a
`routes.tsp` file based on your Rails application's routes.

For example:

```ruby
# config/routes.rb
defaults format: :json, export: true do
  resources :videos do
    member do
      post :publish
    end
    collection do
      post :search
    end
    resources :comments, only: [:index, :create, :update, :destroy]
  end
end

# app/controllers/videos_controller.rb
class VideosController < ApplicationController
  def show
    video = Video.find(params[:id])
    render json: VideoWithCommentsSerializer.one(video)
  end
end
```

Generates:

```typespec
import "@typespec/http";

import "./models/Video.tsp";
import "./models/VideoWithComments.tsp";
import "./models/Comment.tsp";

using TypeSpec.Http;

@service(#{
  title: "SampleApp API",
})
namespace SampleApp {
  namespace Routes {
    @route("/videos")
    interface Videos {
      @get index(): Video[];
      @post create(): Video;
      @get show(@path id: string): VideoWithComments;
      @patch update(@path id: string): Video;
      @delete destroy(@path id: string): Video;
      @route("/{id}/publish")
      @post publish(@path id: string): Video;
      @route("/search")
      @post search(): Video[];
    }

    @route("/videos/{video_id}/comments")
    interface Comments {
      @get index(@path video_id: string): Comment[];
      @post create(@path video_id: string): Comment;
      @patch update(@path video_id: string, @path id: string): Comment;
      @delete destroy(@path video_id: string, @path id: string): Comment;
    }
  }
}
```

#### Typing Request Parameters

TypeSpec distinguishes between **path parameters** (in the URL) and **body parameters** (in the request payload). You declare each in the appropriate place:

**Path Parameters (in routes.rb)**

Path parameters like `:id`, `:slug` appear in the URL path. Declare their types in `routes.rb` using `type:`:

```ruby
# config/routes.rb
defaults format: :json, export: true do
  # Type path parameters where routes are defined
  get 'videos/:id', to: 'videos#show', type: { id: Integer }

  resources :articles, type: { id: Integer, slug: String }

  # Nested routes - type each level's parameters
  resources :videos, type: { id: Integer } do
    resources :comments, type: { video_id: Integer, id: Integer }
  end
end
```

Generates:
```typespec
@get video(@path id: int32): Video;
@get article(@path id: int32, @path slug: string): Article;
@get video_comment(@path video_id: int32, @path id: int32): Comment;
```

**Body Parameters (in controllers)**

Body parameters are sent in POST/PATCH request payloads. Declare their types in controllers using `type` before `*_params` methods:

```ruby
# app/controllers/videos_controller.rb
class VideosController < ApplicationController
  include TypeSpecFromSerializers::DSL::Controller

  # Type the request body parameters
  type title: String, published: TrueClass, duration: Integer
  def video_params
    params.require(:video).permit(:title, :published, :duration)
  end

  def create
    video = Video.create(video_params)
    render json: VideoSerializer.one(video)
  end
end
```

Generates:
```typespec
@post create_videos(title: string, published: boolean, duration: int32): Video;
```

## Configuration ⚙️

You can configure generation in a Rails initializer:

```ruby
# config/initializers/typespec_from_serializers.rb

if Rails.env.development?
  TypeSpecFromSerializers.config do |config|
    config.name_from_serializer = ->(name) { name }
  end
end
```

### `namespace`

_Default:_ Rails application name (e.g., `"SampleApp"`) or `"Schema"` as fallback

Wraps all generated models and routes in a TypeSpec namespace.

Set to `nil` to disable namespacing.

### `base_serializers`

_Default:_ `["BaseSerializer"]`

Allows you to specify the base serializers, that are used to detect other
serializers in the app that you would like to generate interfaces for.

### `serializers_dirs`

_Default:_ `["app/serializers"]`

The dirs where the serializer files are located.

### `output_dir`

_Default:_ `"app/frontend/typespec/generated"`

The dir where the generated TypeSpec interface files are placed.

### `custom_typespec_dir`

_Default:_ `"app/frontend/types"`

The dir where the custom types are placed.

### `name_from_serializer`

_Default:_ `->(name) { name.delete_suffix("Serializer") }`

A `Proc` that specifies how to convert the name of the serializer into the name
of the generated TypeSpec interface.

### `global_types`

_Default:_ `["Array", "Record", "Date"]`

Types that don't need to be imported in TypeSpec.

You can extend this list as needed if you are using global definitions.

### `skip_serializer_if`

_Default:_ `->(serializer) { false }`

You can provide a proc to avoid generating serializers.

Along with `base_serializers`, this provides more fine-grained control in cases
where a single backend supports several frontends, allowing to generate types
separately.

### `sql_to_typespec_type_mapping`

Specifies how to map SQL column types to TypeSpec native and custom types.

```ruby
# Example: You have response middleware that automatically converts date strings
# into Date objects, and you want TypeSpec to treat those fields as `plainDate`.
config.sql_to_typespec_type_mapping.update(
  date: :plainDate,
  datetime: :utcDateTime,
)

# Example: You won't transform fields when receiving data in the frontend
# (date fields are serialized to JSON as strings).
config.sql_to_typespec_type_mapping.update(
  date: :string,
  datetime: :utcDateTime,
)
```

### `sorbet_to_typespec_type_mapping`

Specifies how to map Sorbet types to TypeSpec types. This is used when inferring types from Sorbet method signatures.

_Default mapping:_

```ruby
{
  "String" => :string,
  "Integer" => :int32,
  "Float" => :float64,
  "TrueClass" => :boolean,
  "FalseClass" => :boolean,
  "T::Boolean" => :boolean,
  "Date" => :plainDate,
  "DateTime" => :utcDateTime,
  "Time" => :utcDateTime,
  "Symbol" => :string,
}
```

You can customize this mapping:

```ruby
config.sorbet_to_typespec_type_mapping.update(
  "BigDecimal" => :float64,
  "Money" => :float64,
)
```

### `transform_keys`

_Default:_ `->(key) { key.camelize(:lower).chomp("?") }`

You can provide a proc to transform property names.

This library assumes that you will transform the casing client-side, but you can
generate types preserving case by using `config.transform_keys = ->(key) { key }`.

### `export_if`

_Default:_ `->(route) { route.defaults[:export] }`

Controls which routes are included in the generated `routes.tsp` file. By default, only routes with `export: true` are included.

```ruby
# Export all routes
config.export_if = ->(route) { true }

# Export routes for specific controllers
config.export_if = ->(route) {
  route.defaults[:controller]&.start_with?('api/')
}
```

### `param_method_suffix`

_Default:_ `"_params"`

Specifies the suffix for controller methods that define request parameters. The generator looks for methods ending with this suffix (e.g., `video_params`, `article_params`) to extract body parameter types.

```ruby
# Use a different suffix
config.param_method_suffix = "_parameters"
```

### `action_to_operation_mapping`

_Default:_ `{}`

Maps Rails action names to custom operation names in the generated TypeSpec routes.

```ruby
# Customize operation names
config.action_to_operation_mapping = {
  "index" => "list",
  "show" => "read",
  "create" => "create",
  "update" => "update",
  "destroy" => "delete",
}
```

This generates operations like `@get list()` instead of `@get index()`.

### `openapi_path`

_Default:_ `"public/openapi.yaml"`

Specifies where the compiled OpenAPI specification file should be placed.

```ruby
# Place in a custom location
config.openapi_path = Rails.root.join("docs", "api.yaml")
```

## Contact ✉️

Please use [Issues] to report bugs you find, and [Discussions] to make feature requests or get help.

Don't hesitate to _⭐️ star the project_ if you find it useful!

Using it in production? Always love to hear about it! 😃

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
