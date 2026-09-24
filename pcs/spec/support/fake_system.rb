# frozen_string_literal: true

# Stands in for Pcs::Adapters::SystemCmd: records each argv and answers from
# scripted results (matched by argv prefix), so adapters and operations can be
# tested without running anything.
class FakeSystem
  attr_reader :commands

  def initialize
    @commands = []
    @responses = []
  end

  def on(*prefix, stdout: "", stderr: "", status: 0)
    @responses << [prefix.map(&:to_s), stdout, stderr, status]
    self
  end

  def run(*argv, **)
    argv = argv.flatten.map(&:to_s)
    @commands << argv
    _, stdout, stderr, status = @responses.find { |prefix, *| argv.first(prefix.size) == prefix }
    Pcs::Adapters::SystemCmd::Result.new(argv, stdout.to_s, stderr.to_s, status || 0)
  end

  def run!(...)
    run(...).tap { |r| raise Pcs::Adapters::SystemCmd::Failed, r unless r.success? }
  end
end
