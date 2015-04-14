# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/transaction_sample/segment'
require 'new_relic/transaction_sample/summary_segment'
require 'new_relic/transaction_sample/fake_segment'
require 'new_relic/transaction_sample/composite_segment'

module NewRelic
  module Agent
    class Transaction
      class Trace
        class FinishedTraceError < StandardError; end

        attr_reader :start_time, :root_segment
        attr_accessor :transaction_name, :uri, :guid, :xray_session_id,
                      :synthetics_resource_id, :agent_attributes,
                      :custom_attributes, :intrinsic_attributes, :segment_count,
                      :finished, :threshold, :profile

        def initialize(start_time)
          @start_time = start_time
          @segment_count = 0
          @root_segment = NewRelic::TransactionSample::Segment.new(0.0, "ROOT")
        end

        # offset from start of app
        @@start_time = Time.now
        def timestamp
          @start_time - @@start_time.to_f
        end

        def sample_id
          self.object_id
        end

        def count_segments
          self.segment_count
        end

        def duration
          self.root_segment.duration
        end

        def set_custom_param(*args)
        end

        def set_request_param(*args)
        end

        def to_s_compact
          @root_segment.to_s_compact
        end

        def create_segment(time_since_start, metric_name = nil)
          raise FinishedTraceError.new "Can't create additional segment for finished trace." if self.finished
          self.segment_count += 1
          NewRelic::TransactionSample::Segment.new(time_since_start, metric_name)
        end

        def each_segment(&block)
          self.root_segment.each_segment(&block)
        end

        def find_segment(segment_id)
          self.root_segment.find_segment(segment_id)
        end

        def request_attributes
          {}
        end

        def prepare_to_send!
          self
        end

        def collect_explain_plans!
          return unless NewRelic::Agent::Database.should_collect_explain_plans?
          threshold = NewRelic::Agent.config[:'transaction_tracer.explain_threshold']

          each_segment do |segment|
            if segment[:sql] && segment.duration > threshold
              segment[:explain_plan] = segment.explain_sql
            end
          end
        end

        # Iterates recursively over each segment in the entire transaction
        # sample tree while keeping track of nested segments
        def each_segment_with_nest_tracking(&block)
          @root_segment.each_segment_with_nest_tracking(&block)
        end

        def trace_tree
          destination = NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER
          [
            NewRelic::Coerce.float(self.start_time),
            {},
            {},
            self.root_segment.to_array,
            {
              'agentAttributes'  => self.agent_attributes.for_destination(destination),
              'customAttributes' => self.custom_attributes.for_destination(destination),
              'intrinsics'       => self.intrinsic_attributes.for_destination(destination)
            }
          ]
        end

        def to_collector_array(encoder)
          [
            NewRelic::Helper.time_to_millis(self.start_time),
            NewRelic::Helper.time_to_millis(self.root_segment.duration),
            NewRelic::Coerce.string(self.transaction_name),
            NewRelic::Coerce.string(self.uri),
            encoder.encode(trace_tree),
            NewRelic::Coerce.string(self.guid),
            forced?,
            NewRelic::Coerce.int_or_nil(xray_session_id),
            NewRelic::Coerce.string(self.synthetics_resource_id)
          ]
        end

        def forced?
          return true if NewRelic::Coerce.int_or_nil(xray_session_id)
          false
        end
      end
    end
  end
end
