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
    rescue ::ActiveRecord::ConnectionTimeoutError
      logger.info 'FutureRecords: Failed to obtain a connection. Falling back to non-threaded query'
      method(:exec_queries).super_method.call
      super
    end
  end

  class << self
    def future(&block)
      Result.new(&block)
    end
  end

  class Result
    def initialize(&block)
      @block = block
      @thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          @records = yield
        end
      end
    end

    def records
      @thread.join
      @records
    rescue ::ActiveRecord::ConnectionTimeoutError
      ActiveRecord::Base.logger.info 'FutureRecords: Failed to obtain a connection. Falling back to non-threaded query'
      @block.call
    end
  end
end

ActiveSupport.on_load :active_record do
  ActiveRecord::Relation.include FutureRecords::FutureMethod
end
