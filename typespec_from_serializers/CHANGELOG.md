# TypeSpec From Serializers Changelog

## [0.6.0] - 2026-03-03

### Added
- Automatic route namespace/interface disambiguation: names that collide with model names are suffixed (e.g., `namespace Task` → `namespace TaskRoutes` when `TaskSerializer` exists)
- New `route_namespace_suffix` config option (default: `"Routes"`) to control the disambiguation suffix
- Content-based cache keys: files are only rewritten when generated output actually changes, eliminating unnecessary diffs from internal representation changes

## [0.5.4] - 2025-12-23

### Fixed
- Transitive params extraction now follows method calls through intermediate methods
- Route-level `type:` declarations now only apply to actual path params (not inherited by collection routes)

## [0.5.3] - 2025-12-23

### Fixed
- Body params now scoped per action by analyzing which `*_params` methods are called

## [0.5.2] - 2025-12-22

### Fixed
- File permissions for all library files (now world-readable)

## [0.5.1] - 2025-12-22

### Fixed
- Routing patches now included in DSL module for production use

## [0.5.0] - 2025-12-22

### Fixed
- Route parameter typing with `type:` now works correctly without interfering with Rails routing

## [0.4.0] - 2025-12-22

### Added
- Linting system with 5 configurable rules to catch common issues during generation

### Fixed
- Add `implicitOptionality: true` to PATCH decorators to suppress TypeSpec 1.0+ warnings

## [0.3.1] - 2025-12-22

### Fixed
- Fix routes cache key to include documentation field (now uses `inspect` for all fields)
- Clean up `tsp-output` directory after OpenAPI compilation
- Make OpenAPI output deterministic by sorting body parameters alphabetically

### Added
- Tests for cache key invalidation when documentation changes

## [0.3.0] - 2025-12-20

### Features
- Extract RDoc comments from serializers and controllers to generate `@doc` decorators
- New `extract_docs` config option (enabled by default) to control documentation extraction
- Requires RDoc 7.0+ for Prism-based parser support

## [0.2.1] - 2025-12-19

### Fixed
- Correct `@service` decorator syntax to use `#{}` for object literals
- Add newline after `@service` decorator for better readability

## [0.2.0] - 2025-12-19

Initial release - fork of `types_from_serializers` adapted to generate TypeSpec instead of TypeScript.

### Features

**Routes Generation**
- Generate TypeSpec HTTP interfaces from Rails routes automatically
- Type path parameters in `routes.rb`: `type: { id: Integer }`
- Type request body in controllers with `type` DSL
- Nested routes organized in namespaces
- Filter exported routes with `export_if` configuration

**Sorbet Integration**
- Automatic type inference from Sorbet signatures
- Support for `T.nilable`, `T::Array`, unions, and complex shapes
- Works with RBI files (Tapioca-generated)

**Type System**
- Simple `type:` syntax for explicit types
- Union types: `type: "string | int32"`
- Automatic inference from SQL schema and ActiveRecord enums
- Custom TypeSpec model references

**OpenAPI**
- Compile TypeSpec to OpenAPI 3.0: `rake typespec_from_serializers:compile_openapi`
- Setup dependencies: `rake typespec_from_serializers:setup`

**Developer Experience**
- Automatic regeneration in development mode
- Vite live reload support
- Incremental generation for modified files only

---

# Previous versions (types_from_serializers)

## [2.3.0](https://github.com/ElMassimo/types_from_serializers/compare/types_from_serializers@2.2.0...types_from_serializers@2.3.0) (2024-08-23)


### Features

* generate types for inline serializers, exclude them from the index ([1c3657c](https://github.com/ElMassimo/types_from_serializers/commit/1c3657c61a1bc891f3219f6eaf8557cd3cd6344a)), closes [#19](https://github.com/ElMassimo/types_from_serializers/issues/19)



# [2.2.0](https://github.com/ElMassimo/types_from_serializers/compare/types_from_serializers@2.1.0...types_from_serializers@2.2.0) (2024-08-23)


### Bug Fixes

* be more accurate regarding decimal serialization ([cd63653](https://github.com/ElMassimo/types_from_serializers/commit/cd636530a5710112a14746cc7d0e3f15016cd5e1))


### Features

* infer type from enums ([#20](https://github.com/ElMassimo/types_from_serializers/issues/20)) ([49dc61d](https://github.com/ElMassimo/types_from_serializers/commit/49dc61da2718256e9b5f5743b5a65c4746d64c2f))



# [2.1.0](https://github.com/ElMassimo/types_from_serializers/compare/types_from_serializers@2.0.2...types_from_serializers@2.1.0) (2023-07-19)


### Features

* add `namespace` option to generate `.d.ts` files ([#9](https://github.com/ElMassimo/types_from_serializers/issues/9)) ([6f67b1a](https://github.com/ElMassimo/types_from_serializers/commit/6f67b1ad9283868e8e3325042645bceccc85b047))



## [2.0.2](https://github.com/ElMassimo/types_from_serializers/compare/types_from_serializers@2.0.1...types_from_serializers@2.0.2) (2023-04-05)


### Features

* map citext from PostgreSQL to string ([#7](https://github.com/ElMassimo/types_from_serializers/issues/7)) ([d8c6848](https://github.com/ElMassimo/types_from_serializers/commit/d8c6848b99b0f4ba3770871f491755c229a2c4b0))



## [2.0.1](https://github.com/ElMassimo/types_from_serializers/compare/types_from_serializers@2.0.0...types_from_serializers@2.0.1) (2023-04-03)


### Bug Fixes

* `add_attribute` now expects keyword arguments ([154b49e](https://github.com/ElMassimo/types_from_serializers/commit/154b49e463e3e6533b21520b7f0d699e6f0f47ba))



## [2.0.0](https://github.com/ElMassimo/types_from_serializers/compare/types_from_serializers@0.1.2...types_from_serializers@2.0.0) (2023-04-02)

This version adds support for `oj_serializers-2.0.2`, supporting all changes in:

- https://github.com/ElMassimo/oj_serializers/pull/9

### Features ✨

- Now keys will match the [`transform_keys`](https://github.com/ElMassimo/oj_serializers#transforming-attribute-keys-) configuration instead of always being camelized
- Support for [`flat_one`](https://github.com/ElMassimo/oj_serializers#composing-serializers-)
- Use relative paths for imports to make the output configuration more flexible
- Define the order of properties in the interface with `sort_properties_by`

## [0.1.3](https://github.com/ElMassimo/types_from_serializers/compare/types_from_serializers@0.1.2...types_from_serializers@0.1.3) (2022-07-12)


### Features

* apply the sql mapping fallback as the default ([64898c4](https://github.com/ElMassimo/types_from_serializers/commit/64898c4e3a3f83ea67294f2200f253cd2a64aea9))



## [0.1.2](https://github.com/ElMassimo/types_from_serializers/compare/types_from_serializers@0.1.1...types_from_serializers@0.1.2) (2022-07-12)


### Bug Fixes

* avoid having the full file path in the cache key ([556f8f6](https://github.com/ElMassimo/types_from_serializers/commit/556f8f667608fa950a3ad0647540055b1b5f1dc8))



## [0.1.1](https://github.com/ElMassimo/types_from_serializers/compare/types_from_serializers@0.1.0...types_from_serializers@0.1.1) (2022-07-12)



# 0.1.0 (2022-07-12)


### Features

- Start simple, no additional syntax required
- Infers types from a related `ActiveRecord` model, using the SQL schema
- Understands JS native types and how to map SQL columns: `string`, `boolean`, etc
- Automatically types [associations](https://github.com/ElMassimo/oj_serializers#associations-dsl-), importing the generated types for the referenced serializers
- Detects [conditional attributes](https://github.com/ElMassimo/oj_serializers#rendering-an-attribute-conditionally) and marks them as optional: `name?: string`
- Fallback to a custom interface using `type_from`
- Supports custom types and automatically adds the necessary imports
- handle non-ActiveRecord models and extract types from unions ([ea9b2a7](https://github.com/ElMassimo/types_from_serializers/commit/ea9b2a71cb85503ff691e5ef115ab73f89b005af))
- support specifying base serializers and additional dirs to scan ([164cfe1](https://github.com/ElMassimo/types_from_serializers/commit/164cfe17bb0527c59cf95441381aef7bf797a568))



