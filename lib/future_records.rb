# frozen_string_literal: true

module FutureRecords
  module FutureMethod
    def future
      extend FutureFeature
      exec_queries
      self
    end
  end

  module FutureFeature
    private def exec_queries(&block)
      @query_thread = Thread.new do
        connection_pool.with_connection do
          super
        end
      end
    end

    def records
      @query_thread.join
      @records
    end
  end

  class << self
    def future(&block)
      Result.new(&block)
    end
  end

  class Result
    def initialize
      @thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          @records = yield
        end
      end
    end

    def records
      @thread.join
      @records
    end
  end
end

ActiveSupport.on_load :active_record do
  ActiveRecord::Relation.include FutureRecords::FutureMethod
end
