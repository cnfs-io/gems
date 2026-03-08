# frozen_string_literal: true

RSpec.describe "Pim console mode" do
  before do
    # Reset console mode before each test to prevent ordering leaks
    Pim.instance_variable_set(:@console_mode, false)
  end

  after do
    # Reset console mode after each test
    Pim.instance_variable_set(:@console_mode, false)
  end

  describe ".console_mode!" do
    it "sets console mode" do
      Pim.console_mode!
      expect(Pim.console_mode?).to be true
    end
  end

  describe ".console_mode?" do
    it "returns false by default" do
      expect(Pim.console_mode?).to be false
    end

    it "returns true after activation" do
      Pim.console_mode!
      expect(Pim.console_mode?).to be true
    end
  end

  describe ".exit!" do
    context "in normal mode" do
      it "calls Kernel.exit" do
        expect(Kernel).to receive(:exit).with(1)
        Pim.exit!(1)
      end

      it "prints message to stderr before exiting" do
        expect(Kernel).to receive(:exit).with(1)
        expect { Pim.exit!(1, message: "something failed") }.to output("something failed\n").to_stderr
      end
    end

    context "in console mode" do
      before { Pim.console_mode! }

      it "raises Pim::CommandError" do
        expect { Pim.exit!(1) }.to raise_error(Pim::CommandError)
      end

      it "includes message in the exception" do
        expect { Pim.exit!(1, message: "test error") }.to raise_error(Pim::CommandError, "test error")
      end

      it "prints message to stderr" do
        expect { Pim.exit!(1, message: "test error") rescue nil }.to output("test error\n").to_stderr
      end
    end
  end

  describe ".run" do
    it "dispatches to Dry::CLI" do
      expect { Pim.run("version") }.to output(/pim \d+\.\d+\.\d+/).to_stdout
    end

    it "handles boot failure gracefully" do
      # Running a command that requires boot outside a project should not crash
      expect { Pim.run("nonexistent-command") }.not_to raise_error
    end
  end
end
