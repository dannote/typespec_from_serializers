<h1 align="center">
TypeSpec From Serializers
<p align="center">
<a href="https://travis-ci.org/dannote/typespec_from_serializers"><img alt="Build Status" src="https://travis-ci.org/dannote/typespec_from_serializers.svg"/></a>
<a href="http://inch-ci.org/github/dannote/typespec_from_serializers"><img alt="Inline docs" src="http://inch-ci.org/github/dannote/typespec_from_serializers.svg"/></a>
<a href="https://rubygems.org/gems/typespec_from_serializers"><img alt="Gem Version" src="https://img.shields.io/gem/v/typespec_from_serializers.svg?colorB=e9573f"/></a>
<a href="https://github.com/dannote/typespec_from_serializers/blob/main/LICENSE.txt"><img alt="License" src="https://img.shields.io/badge/license-MIT-428F7E.svg"/></a>
</p>
</h1>

[aliases]: https://vite-ruby.netlify.app/guide/development.html#import-aliases-%F0%9F%91%89
[config options]: https://github.com/dannote/typespec_from_serializers/blob/main/lib/typespec_from_serializers/generator.rb#L82-L85
[readme]: https://github.com/dannote/typespec_from_serializers

**TypeSpec From Serializers** is a Ruby gem that automatically generates [TypeSpec](https://typespec.io) definitions from Ruby serializers and Rails routes. It is a derivative work of [`types_from_serializers`][types_from_serializers] by ElMassimo, originally designed to generate TypeScript definitions. This fork adapts the core functionality to produce TypeSpec descriptions, enabling Rails developers to define APIs compatible with TypeSpec’s ecosystem, including OpenAPI generation and client/server code scaffolding.

For more information, check the main [README].

### Installation 💿

Add this line to your application's Gemfile:

```ruby
gem 'typespec_from_serializers'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install typespec_from_serializers
