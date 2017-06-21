module ReplicaPools
  # duck-types with ActiveRecord::ConnectionAdapters::QueryCache
  # but relies on ActiveRecord::Base.query_cache for state so we
  # don't fragment the cache across multiple connections
  #
  # we could use more of ActiveRecord's QueryCache if it only
  # used accessors for its internal ivars.
  module QueryCache
    query_cache_methods = ActiveRecord::ConnectionAdapters::QueryCache.instance_methods(false)

    # these methods can all use the leader connection
    (query_cache_methods - [:select_all]).each do |method_name|
      module_eval <<-END, __FILE__, __LINE__ + 1
        def #{method_name}(*a, &b)
          ActiveRecord::Base.connection.#{method_name}(*a, &b)
        end
      END
    end

    # select_all is trickier. it needs to use the leader
    # connection for cache logic, but ultimately pass its query
    # through to whatever connection is current.
    def select_all(*args)
      # there are more args, but we only care about arel and binds for caching
      arel, _, binds = args
      if query_cache_enabled && !locked?(arel)
        sql = to_sql(arel, binds)
        args[0] = sql
        cache_sql(sql, binds) { route_to(current, :select_all, *args) }
      else
        route_to(current, :select_all, *args)
      end
    end

    # these can use the unsafe delegation built into ConnectionProxy
    # [:insert, :update, :delete]
  end
end