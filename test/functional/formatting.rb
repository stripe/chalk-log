require File.expand_path('../_lib', __FILE__)

require 'chalk-log'

module Critic::Functional
  class LogTest < Test
    def enable_timestamp
      configatron.chalk.log.stubs(:timestamp).returns(true)
    end

    def disable_timestamp
      configatron.chalk.log.stubs(:timestamp).returns(false)
    end

    def disable_tagging
      configatron.chalk.log.stubs(:tagging).returns(false)
    end

    before do
      Chalk::Log.init
      Process.stubs(:pid).returns(9973)
      disable_timestamp
    end

    class MyClass
      include Chalk::Log
    end

    describe 'when called without arguments' do
      it 'does not loop infinitely' do
        MyClass.log.info
      end
    end

    describe 'when called with a message' do
      it 'does not mutate the input' do
        canary = "'hello, world!'"
        baseline = canary.dup
        MyClass.log.info(canary)
        assert_equal(baseline, canary)
      end
    end

    describe 'layout' do
      before do
        @layout = MyClass::Layout.new
      end

      def layout(opts)
        event = Critic::Fake::Event.new(opts)
        formatted = @layout.format(event)

        # Everything should end with a newline, but they're annoying
        # to have to test elsewhere, so strip it away.
        assert_equal("\n", formatted[-1], "Layout did not end with a newline: #{formatted.inspect}")
        formatted.chomp
      end

      it 'log entry from info' do
        rendered = layout(data: ["A Message", {:key1 => "ValueOne", :key2 => ["An", "Array"]}])
        assert_equal('[9973] A Message: key1=ValueOne key2=["An","Array"]', rendered)
      end

      it 'logs the action_id correctly' do
        LSpace.with(action_id: 'action') do
          rendered = layout(data: ["A Message", {:key1 => "ValueOne", :key2 => ["An", "Array"]}])
          assert_equal('[9973|action] A Message: key1=ValueOne key2=["An","Array"]', rendered)
        end
      end

      it 'logs timestamp correctly' do
        enable_timestamp
        LSpace.with(action_id: 'action') do
          rendered = layout(data: ["A Message", {:key1 => "ValueOne", :key2 => ["An", "Array"]}])
          assert_equal('[1979-04-09 00:00:00.000000] [9973|action] A Message: key1=ValueOne key2=["An","Array"]', rendered)
        end
      end

      it 'log from info hash without a message' do
        rendered = layout(data: [{:key1 => "ValueOne", :key2 => ["An", "Array"]}])
        assert_equal('[9973] key1=ValueOne key2=["An","Array"]', rendered)
      end

      it 'renders [no backtrace] as appropriate' do
        rendered = layout(data: ["Another Message", StandardError.new('msg')])
        assert_equal("[9973] Another Message: error_class=StandardError error=msg\n[9973]   [no backtrace]", rendered)
      end

      it 'renders when given error and info hash' do
        rendered = layout(data: ["Another Message", StandardError.new('msg'), {:key1 => "ValueOne", :key2 => ["An", "Array"]}])
        assert_equal(%Q{[9973] Another Message: key1=ValueOne key2=["An","Array"] error_class=StandardError error=msg\n[9973]   [no backtrace]}, rendered)
      end

      it 'renders an error with a backtrace' do
        error = StandardError.new('msg')
        backtrace = ["a fake", "backtrace"]
        error.set_backtrace(backtrace)

        rendered = layout(data: ["Yet Another Message", error])
        assert_equal("[9973] Yet Another Message: error_class=StandardError error=msg\n[9973]   a fake\n[9973]   backtrace", rendered)
      end

      it 'renders an error passed alone' do
        error = StandardError.new('msg')
        backtrace = ["a fake", "backtrace"]
        error.set_backtrace(backtrace)

        rendered = layout(data: [error])
        assert_equal("[9973] error_class=StandardError error=msg\n[9973]   a fake\n[9973]   backtrace", rendered)
      end

      it 'handles bad unicode' do
        rendered = layout(data: [{:key1 => "ValueOne", :key2 => "\xC3"}])
        assert_equal("[9973] key1=ValueOne key2=\"\\xC3\" [JSON-FAILED]", rendered)
      end

      it 'allows disabling tagging' do
        enable_timestamp
        disable_tagging

        LSpace.with(action_id: 'action') do
          rendered = layout(data: [{:key1 => "ValueOne", :key2 => "Value Two"}])
          assert_equal(%Q{key1=ValueOne key2="Value Two"}, rendered)
        end
      end

      describe 'faults' do
        it 'handles single faults' do
          e = StandardError.new('msg')
          @layout.expects(:do_format).raises(e)
          rendered = layout(data: ['hi'])

          lines = rendered.split("\n")
          assert_equal('[Chalk::Log fault: Could not format message] error_class=StandardError error=msg', lines[0])
          assert(lines.length > 1)
        end

        it 'handles double-faults' do
          e = StandardError.new('msg')
          def e.to_s; raise 'Time to double-fault'; end

          @layout.expects(:do_format).raises(e)
          rendered = layout(data: ['hi'])

          lines = rendered.split("\n")
          assert_match(/Chalk::Log fault: Double fault while formatting message/, lines[0])
          assert_equal(1, lines.length, "Lines: #{lines.inspect}")
        end

        it 'handles triple-faults' do
          e = StandardError.new('msg')
          def e.to_s
            f = StandardError.new('double')
            def f.to_s; raise 'Time to triple fault'; end
            raise f
          end

          @layout.expects(:do_format).raises(e)
          rendered = layout(data: ['hi'])

          lines = rendered.split("\n")
          assert_match(/Chalk::Log fault: Triple fault while formatting message/, lines[0])
          assert_equal(1, lines.length, "Lines: #{lines.inspect}")
        end
      end
    end
  end
end
