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
        @records = yield
        if Thread.current[:child_thread_connections]
          Thread.current[:child_thread_connections].map {|conn| conn.pool}.uniq.each do |pool|
            pool.release_connection
          end
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

  module ThreadedConnectionRecorder
    def new_connection
      conn = super
      (Thread.current[:child_thread_connections] ||= []) << conn unless Thread.current == Thread.main
      conn
    end
  end
end

ActiveSupport.on_load :active_record do
  ActiveRecord::Relation.include FutureRecords::FutureMethod
  ActiveRecord::ConnectionAdapters::ConnectionPool.prepend FutureRecords::ThreadedConnectionRecorder
end
