---
---

# Plan 01 — RestCli View Associations

## Context

Read before starting:
- `~/.local/share/ppm/gems/rest_cli/lib/rest_cli/view.rb` — View base class with columns/detail_fields DSL
- `~/.local/share/ppm/gems/rest_cli/lib/rest_cli/view/detail_renderer.rb` — renders key-value pairs for `show`
- `~/.local/share/ppm/gems/rest_cli/lib/rest_cli/view/table_renderer.rb` — renders tabular list output
- `~/.local/share/ppm/gems/flat_record/lib/flat_record/associations.rb` — FlatRecord's `_associations_registry`

## Goal

Add a `has_many` DSL to `RestCli::View` so that `show` (detail view) can render associated records as inline tables below the main key-value fields. This is a generic RestCli feature — not PCS-specific.

## Implementation

### Step 1: Add `has_many` class method to RestCli::View

In `rest_cli/lib/rest_cli/view.rb`, add a class-level `has_many` method that stores association rendering config:

```ruby
class View
  def self._view_associations
    @_view_associations ||= []
  end

  def self.has_many(name, columns:)
    _view_associations << { name: name, columns: columns }
  end
end
```

### Step 2: Update `show` to pass associations to DetailRenderer

In `View#show`, pass the association definitions:

```ruby
def show(record, format: :text, quiet: false, **)
  if format == :text
    renderer = RestCli::View::DetailRenderer.new(
      fields: self.class.detail_fields,
      associations: self.class._view_associations,
      output: output
    )
    renderer.render(record, quiet: quiet)
  else
    # ... existing formatter path
  end
end
```

### Step 3: Update DetailRenderer to render associations

In `rest_cli/lib/rest_cli/view/detail_renderer.rb`:

```ruby
def initialize(fields:, associations: [], output: $stdout)
  @fields = fields
  @associations = associations
  @output = output
  @pastel = Pastel.new
end

def render(record, quiet: false)
  pairs = @fields.map { |field| [field, record.send(field)] }
  quiet ? render_quiet(pairs) : render_detail(pairs, record)
end

private

def render_detail(pairs, record)
  max_key_width = pairs.map { |k, _| k.to_s.length }.max || 0

  pairs.each do |field, value|
    next if value.nil?
    key = @pastel.bold(field.to_s.ljust(max_key_width))
    @output.puts "#{key}  #{value}"
  end

  @associations.each do |assoc|
    render_association(record, assoc)
  end
end

def render_association(record, assoc)
  children = record.send(assoc[:name])
  return if children.nil? || children.none?

  @output.puts
  @output.puts @pastel.bold(assoc[:name].to_s.capitalize) + ":"

  table_renderer = RestCli::View::TableRenderer.new(
    columns: assoc[:columns],
    output: @output,
    indent: 2
  )
  table_renderer.render(children, quiet: false)
end
```

### Step 4: Add indent support to TableRenderer

In `rest_cli/lib/rest_cli/view/table_renderer.rb`, add an `indent` option:

```ruby
def initialize(columns:, output: $stdout, indent: 0)
  @columns = columns
  @output = output
  @indent = indent
end
```

When rendering rows, prepend `" " * @indent` to each line. This ensures association tables are visually nested under the parent record.

### Step 5: Ensure backward compatibility

The `associations:` parameter defaults to `[]`, so existing views with no `has_many` declarations render exactly as before. No changes needed to existing PCS views yet — that comes in later plans.

## Test Spec

### Unit tests for RestCli::View

```ruby
# spec/rest_cli/view_spec.rb
RSpec.describe RestCli::View do
  describe ".has_many" do
    it "registers an association with columns" do
      view_class = Class.new(RestCli::View) do
        has_many :items, columns: [:name, :count]
      end
      expect(view_class._view_associations).to eq([{ name: :items, columns: [:name, :count] }])
    end

    it "defaults to empty associations" do
      view_class = Class.new(RestCli::View)
      expect(view_class._view_associations).to eq([])
    end
  end
end
```

### Integration test for DetailRenderer with associations

```ruby
# spec/rest_cli/view/detail_renderer_spec.rb
RSpec.describe RestCli::View::DetailRenderer do
  it "renders associations as inline tables" do
    child = OpenStruct.new(name: "eth0", ip: "10.0.0.1")
    parent = OpenStruct.new(hostname: "n1", interfaces: [child])

    output = StringIO.new
    renderer = described_class.new(
      fields: [:hostname],
      associations: [{ name: :interfaces, columns: [:name, :ip] }],
      output: output
    )
    renderer.render(parent)

    text = output.string
    expect(text).to include("n1")
    expect(text).to include("Interfaces:")
    expect(text).to include("eth0")
    expect(text).to include("10.0.0.1")
  end

  it "skips empty associations" do
    parent = OpenStruct.new(hostname: "n1", interfaces: [])
    output = StringIO.new
    renderer = described_class.new(
      fields: [:hostname],
      associations: [{ name: :interfaces, columns: [:name, :ip] }],
      output: output
    )
    renderer.render(parent)

    expect(output.string).not_to include("Interfaces:")
  end
end
```

## Verification

```bash
cd ~/.local/share/ppm/gems/rest_cli
bundle exec rspec
```
