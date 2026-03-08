---
---

# Plan 01 — FlatRecord Pathname Internals

## Objective

Convert FlatRecord's `data_paths` storage from strings to Pathnames internally. The setter coerces any input (String or Pathname) to Pathname. All internal code uses Pathname methods. `.to_s` is called only at actual IO boundaries (File.read, YAML.safe_load, File.exist? etc.).

## Context — Read Before Starting

- `~/.local/share/ppm/gems/flat_record/lib/flat_record/configuration.rb` — `data_path`, `data_paths` accessors
- `~/.local/share/ppm/gems/flat_record/lib/flat_record/store.rb` — `effective_data_paths`, all file path operations
- `~/.local/share/ppm/gems/flat_record/lib/flat_record/base.rb` — per-model `data_paths` class attribute
- `~/.local/share/ppm/gems/flat_record/spec/` — existing specs

## Implementation

### 1. Configuration — `lib/flat_record/configuration.rb`

Change `data_paths=` setter to coerce to Pathname:

```ruby
def data_paths=(value)
  @_data_paths = Array(value).map { |p| Pathname(p) }
end
```

Change `data_path=` (singular) setter:

```ruby
def data_path=(value)
  @_data_paths = [Pathname(value)]
end
```

Change the initializer default:

```ruby
def initialize
  @_data_paths = [Pathname("./data")]
  # ... rest unchanged
end
```

`data_path` (singular getter) should return a Pathname:

```ruby
def data_path
  @_data_paths.last
end
```

`data_paths` (plural getter) returns the Pathname array as-is (already Pathnames from the setter).

### 2. Per-model data_paths — `lib/flat_record/base.rb`

Find where per-model `data_paths=` is defined (class-level `@data_paths` instance variable). Update the setter to coerce:

```ruby
def self.data_paths=(value)
  @data_paths = Array(value).map { |p| Pathname(p) }
end
```

### 3. Store — `lib/flat_record/store.rb`

`effective_data_paths` already returns the array. Consumers of this method use the paths for file operations. Audit every usage:

- `Pathname.new(path)` calls can be simplified since paths are already Pathnames — just use the path directly
- `File.join(path, ...)` calls should become `path.join(...)`
- `File.exist?(file)` calls should become `file.exist?`
- String concatenation with paths should use Pathname#join

Key methods to update:
- `primary_data_path` — returns last element (already Pathname)
- `collection_file_path` — uses `File.join(primary_data_path, ...)` → use `primary_data_path.join(...).to_s` at IO boundary
- `individual_dir` — same pattern
- `individual_file_path` — same pattern
- `load_records_collection`, `load_records_individual`, `load_records_multi_path_*` — all path construction
- `save_all_collection`, `save_all_individual` — write paths

### 4. Project — `lib/flat_record/project.rb`

Check if this file uses data paths. Update if needed.

## Test Spec

### Update existing specs

Existing specs in `spec/flat_record/configuration_spec.rb` and `spec/flat_record/store_spec.rb` should continue to pass. Strings passed to `data_paths=` should be accepted and coerced.

### New specs — `spec/flat_record/configuration_spec.rb`

Add to existing configuration spec:

```ruby
describe "Pathname coercion" do
  it "coerces string data_path to Pathname" do
    FlatRecord.configure { |c| c.data_path = "/tmp/test" }
    expect(FlatRecord.configuration.data_path).to be_a(Pathname)
    expect(FlatRecord.configuration.data_path.to_s).to eq("/tmp/test")
  end

  it "coerces string data_paths to Pathnames" do
    FlatRecord.configure { |c| c.data_paths = ["/tmp/a", "/tmp/b"] }
    FlatRecord.configuration.data_paths.each do |p|
      expect(p).to be_a(Pathname)
    end
  end

  it "accepts Pathnames in data_paths" do
    FlatRecord.configure { |c| c.data_paths = [Pathname("/tmp/a")] }
    expect(FlatRecord.configuration.data_paths.first).to be_a(Pathname)
  end

  it "accepts mixed strings and Pathnames" do
    FlatRecord.configure { |c| c.data_paths = ["/tmp/a", Pathname("/tmp/b")] }
    FlatRecord.configuration.data_paths.each do |p|
      expect(p).to be_a(Pathname)
    end
  end
end
```

### New specs — per-model data_paths

Add to the appropriate spec (wherever per-model data_paths is tested):

```ruby
describe "per-model data_paths coercion" do
  it "coerces strings to Pathnames" do
    model_class.data_paths = ["/tmp/models"]
    expect(model_class.data_paths.first).to be_a(Pathname)
  end
end
```

## Verification

1. `cd ~/.local/share/ppm/gems/flat_record && bundle exec rspec` — all green
2. `cd ~/.local/share/ppm/gems/pim && bundle exec rspec` — all green (PIM specs still pass with Pathname data_paths)
3. Grep: no `Pathname.new(` wrapping of values from `effective_data_paths` in store.rb (they're already Pathnames)
