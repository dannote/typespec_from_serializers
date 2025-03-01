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

Automatically generate TypeSpec descriptions from your [JSON serializers][oj_serializers]. A derivative work of [`types_from_serializers`][types_from_serializers] by ElMassimo, originally designed to generate TypeScript definitions.

_Currently, this library targets [`oj_serializers`][oj_serializers] and `ActiveRecord` in [Rails] applications_.

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
// Video.tsp
import "./Song.tsp";

model Video {
  id: int32;
  createdAt: utcDateTime;
  title?: string;
  youtubeId?: string;
  youtubeUrl?: string;
  song: Song;
}
```

> **Note**
>
> This reflects the default setup for TypeSpec generation. You can customize everything—check out the [configuration options][config] for full control!

## Installation 💿

Add this line to your application's Gemfile:

```ruby
gem 'typespec_from_serializers'
```

And then run:

    $ bundle install

## Usage 🚀

To get started, [create a `BaseSerializer`](https://github.com/dannote/typespec_from_serializers/blob/main/playground/vanilla/app/serializers/base_serializer.rb) that extends [`Oj::Serializer`][oj_serializers], and include the `TypeSpecFromSerializers::DSL` module.

```ruby
# app/serializers/base_serializer.rb

class BaseSerializer < Oj::Serializer
  include TypeSpecFromSerializers::DSL
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

### Model Attributes

When you want to be more strict than the SQL schema, or for attributes that are methods in the model, you can use:

```ruby
  attributes(
    name: {type: :string},
    status: {type: :Status}, # a custom type in ~/typespec/Status.tsp
  )
```

### Serializer Attributes

For attributes defined in the serializer, use the `type` helper:

```ruby
  type :boolean
  def suspended
    user.status.suspended?
  end
```

> **Note**
>
> When specifying a type, [`attribute`](https://github.com/ElMassimo/oj_serializers#serializer_attributes) will be called automatically.

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
`routes.tsp` file based on your Rails application's routes. This feature creates TypeSpec interfaces
for your API endpoints, mapping Rails controllers and actions to HTTP operations.

For example, given Rails routes like:

```ruby
Rails.application.routes.draw do
  resources :videos, only: [:index, :show]
end
```

The generator produces a `routes.tsp` file like:

```typespec
// routes.tsp
import "@typespec/http";

import "./models/Videos.tsp";

using TypeSpec.Http;

namespace Routes {
  @route("/videos")
  interface Videos {
    @get list(): Videos[];
    @get read(@path id: string): Videos;
  }
}
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

_Default:_ `nil`

Allows to specify a TypeSpec namespace and generate `.tsp` to make types
available globally, avoiding the need to import types explicitly.

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

Specifies [how to map](https://github.com/dannote/typespec_from_serializers/blob/main/typespec_from_serializers/lib/typespec_from_serializers/generator.rb#L297-L308) SQL column types to TypeSpec native and custom types.

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

### `transform_keys`

_Default:_ `->(key) { key.camelize(:lower).chomp("?") }`

You can provide a proc to transform property names.

This library assumes that you will transform the casing client-side, but you can
generate types preserving case by using `config.transform_keys = ->(key) { key }`.

## Contact ✉️

Please use [Issues] to report bugs you find, and [Discussions] to make feature requests or get help.

Don't hesitate to _⭐️ star the project_ if you find it useful!

Using it in production? Always love to hear about it! 😃

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
