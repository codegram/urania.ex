defmodule Urania do
  @moduledoc """
  Efficient and elegant data access for Elixir.

  It's a port of a Clojure library named Urania.

  A brief explanation blatantly stolen from
  https://funcool.github.io/urania/latest/ ensues:

  Oftentimes, your business logic relies on remote data that you need to fetch
  from different sources: databases, caches, web services, or third party APIs,
  and you can’t mess things up. Urania helps you to keep your business logic
  clear of low-level details while performing efficiently:

  * batch multiple requests to the same data source

  * request data from multiple data sources concurrently

  * cache previous requests

  Having all this gives you the ability to access remote data sources in a
  concise and consistent way, while the library handles batching and overlapping
  requests to multiple data sources behind the scenes.
  """

  alias Pinky, as: P

  defmodule Done do
    @moduledoc false
    defstruct [:value]
  end

  defmodule UMap do
    @moduledoc false
    defstruct [:f, :values]
  end

  defmodule FlatMap do
    @moduledoc false
    defstruct [:f, :values]
  end

  defmodule Value do
    @moduledoc false
    defstruct [:value]
  end

  defmodule Impl do
    @moduledoc false

    def is_data_source(x) do
      !!Urania.DataSource.impl_for(x)
    end

    def is_ast(x) do
      !!Urania.AST.impl_for(x)
    end

    def is_composed_ast(x) do
      !!Urania.ComposedAST.impl_for(x)
    end

    def assert_not_ast!(x) do
      if is_ast(x), do: throw "Value is already an AST: #{x}"
    end

    def is_batched_source(x) do
      !!Urania.BatchedSource.impl_for(x)
    end

    def inject_into(env, node) do
      if is_data_source(node) do
        cached_or(env, node)
      else
        Urania.AST.inject(node, env)
      end
    end

    def comp(f, g) do
      fn x -> f.(g.(x)) end
    end

    def identity(x) do
      x
    end

    def resource_name(res), do: to_string(Map.get(res, :__struct__))
    def cache_id(res), do: Urania.DataSource.identity(res)

    def cached_or(env, res) do
      cache = env[:cache]
      cached = cache |> Map.get(resource_name(res), %{}) |> Map.get(cache_id(res), :not_found)
      if :not_found == cached do
        %UMap { f: &identity/1, values: [res] }
      else
        %Done { value: cached }
      end
    end

    def run_fetch(env, muse) do
      P.promise(fn -> Urania.DataSource.fetch(muse, env) end)
    end

    def run_fetch_multi(env, muse, muses) do
      P.promise(fn -> Urania.BatchedSource.fetch_multi(muse, muses, env) end)
    end

    def fetch_many_caching(opts, sources) do
      ids = Enum.map(sources, &cache_id/1)
      response_tasks = Enum.map(sources, fn x -> run_fetch(opts, x) end)
      P.all(response_tasks)
      |> P.map(fn responses ->
        Enum.reduce(Enum.zip(ids, responses), %{}, fn({id, response}, acc) -> Map.put(acc, id, response) end)
      end)
    end

    def fetch_one_caching(opts, source) do
      run_fetch(opts, source)
      |> P.map(fn result ->
        %{cache_id(source) => result}
      end)
    end

    def fetch_sources(opts, [source]) do
      fetch_one_caching(opts, source)
    end

    def fetch_sources(opts, [head | tail]) do
      if is_batched_source(head) do
        run_fetch_multi(opts, head, tail)
      else
        fetch_many_caching(opts, [head | tail])
      end
    end

    def dedupe_sources(sources) do
      values = sources |> Enum.group_by(&cache_id/1) |> Map.values
      Enum.map(values, &List.first/1)
    end

    def fetch_resource(opts, {resource_name, sources}) do
      fetch_sources(opts, dedupe_sources(sources))
      |> P.map(fn results ->
        {resource_name, results}
      end)
    end

    def next_level(node) do
      if is_data_source(node) do
        [node]
      else
        children = Urania.AST.children(node)
        if children do
          Enum.concat(Enum.map(Urania.AST.children(node), &next_level/1))
        else
          []
        end
      end
    end

    def interpret_ast(node, opts) do
      ast_node = inject_into(opts, node)
      requests = next_level(ast_node)
      if Enum.empty?(requests) do
        if Urania.AST.done?(ast_node) do
          P.resolved({ast_node.value, opts[:cache]})
        else
          interpret_ast(ast_node, opts)
        end
      else
        requests_by_type = Map.to_list(Enum.group_by(requests, &resource_name/1))
        response_tasks = Enum.map(requests_by_type, fn x -> fetch_resource(opts, x) end)
        P.all(response_tasks)
        |> P.flat_map(fn responses ->
          cache_map = Enum.reduce(responses, %{}, fn ({k, v}, acc) -> Map.put(acc, k, v) end)
          next_cache = Map.merge(opts[:cache], cache_map, &Map.merge/2)
          next_opts = Map.put(opts, :cache, next_cache)
          interpret_ast(ast_node, next_opts)
        end)
      end
    end

    def run_defaults, do: %{cache: %{}}
  end

  defprotocol DataSource do
    def identity(this)
    def fetch(this, env)
  end

  defprotocol BatchedSource do
    def fetch_multi(this, resources, env)
  end

  defprotocol AST do
    @moduledoc false
    def children(this)
    def inject(this, env)
    def done?(this)
  end

  defprotocol ComposedAST do
    @moduledoc false
    def compose_ast(this, f)
  end

  defimpl ComposedAST, for: Done do
    def compose_ast(this, f2), do: %Done { value: f2.(this.value) }
  end

  defimpl AST, for: Done do
    def children(_), do: nil
    def done?(_), do: true
    def inject(this, _), do: this
  end

  defimpl ComposedAST, for: UMap do
    import Urania.Impl
    def compose_ast(this, f2), do: %UMap { f: comp(f2, this.f), values: this.values }
  end

  defimpl AST, for: UMap do
    def children(this), do: this.values
    def done?(_), do: false
    def inject(this, env) do
      import Urania.Impl
      next = Enum.map(this.values, fn x -> inject_into(env, x) end)
      if Enum.all?(next, &AST.done?/1) do
        if Enum.count(next) == 1 do
          %Done { value: this.f.(List.first(next).value) }
        else
          %Done { value: this.f.(Enum.map(next, &(&1.value))) }
        end
      else
        %UMap { f: this.f, values: next }
      end
    end
  end

  defimpl ComposedAST, for: FlatMap do
    import Urania.Impl
    def compose_ast(this, f2), do: %UMap { f: comp(f2, this.f), values: this.values }
  end

  defimpl AST, for: FlatMap do
    import Urania.Impl
    def children(this), do: this.values
    def done?(_), do: false
    def inject(this, env) do
      next = Enum.map(this.values, fn x -> inject_into(env, x) end)
      if Enum.all?(next, &AST.done?/1) do
        result = if Enum.count(next) == 1 do
          this.f.(List.first(next).value)
        else
          this.f.(Enum.map(next, &(&1.value)))
        end
        result = inject_into(env, result)
        if is_data_source(result) do
          %UMap { f: &identity/1, values: [result] }
        else
          result
        end
      else
        %FlatMap { f: this.f, values: next }
      end
    end
  end

  defimpl ComposedAST, for: Value do
    def compose_ast(this, f2), do: %UMap { f: f2, values: [this.value] }
  end

  defimpl AST, for: Value do
    import Urania.Impl
    def children(this), do: [this.value]
    def done?(_), do: false
    def inject(this, env) do
      next = Impl.inject_into(env, this.value)
      if AST.done?(next) do
        %Done { value: next }
      else
        next
      end
    end
  end

  @doc """
  Constructs a muse that will evaluate to a predefined value.

  ## Examples

      iex> Urania.run!(Urania.value(3))
      {:ok, 3}

  """
  def value(v) do
    import Urania.Impl
    assert_not_ast!(v)
    %Done { value: v }
  end

  @doc """
  Returns a new muse that will have a function applied to its value.

  ## Examples

      iex> Urania.value(3) |> Urania.map(fn x -> x + 1 end) |> Urania.run!
      {:ok, 4}

  """
  def map(muses, f) when is_list(muses) do
    import Urania.Impl
    if Enum.count(muses) == 1 and is_composed_ast(List.first(muses)) do
      ComposedAST.compose_ast(List.first(muses), f)
    else
      %UMap { f: f, values: muses }
    end
  end

  def map(muse, f) do
    %UMap { f: f, values: [muse] }
  end

  @doc """
  Returns a new muse that will have a function applied to its value, assuming
  the function will return another muse.

  ## Examples

      iex> Urania.value(3) |> Urania.flat_map(fn x -> Urania.value(x + 1) end) |> Urania.run!
      {:ok, 4}

  """
  def flat_map(muses, f) when is_list(muses) do
    %FlatMap { f: f, values: muses }
  end

  def flat_map(muse, f) do
    flat_map([muse], f)
  end

  @doc """
  Groups a list of muses and returns a new muse that will evaluate to a list of
  all the muses' results.

  ## Examples

      iex> Urania.collect([Urania.value(3), Urania.value(5)]) |> Urania.run!
      {:ok, [3, 5]}

  """
  def collect([]) do
    value([])
  end

  def collect(muses) do
    import Urania.Impl
    map(muses, &identity/1)
  end

  @doc """
  Groups a list of muses and returns a new muse that will evaluate to a list of
  all the muses' results.

  ## Examples

      iex> [Urania.value(3), Urania.value(5)]
      ...> |> Urania.traverse(fn x -> Urania.value(x + 1) end)
      ...> |> Urania.run!
      {:ok, [4, 6]}

  """
  def traverse(muses, f) do
    flat_map(muses, fn xs -> collect(Enum.map(xs, f)) end)
  end

  @doc """
  Runs a Urania muse and returns a Pinky promise of { result, data_source_cache_map }.

  ## Examples

      iex> Urania.value(3) |> Urania.execute |> Pinky.extract
      {:ok, {3, %{}}}

  """
  def execute(ast_node) do
    import Urania.Impl
    execute(ast_node, run_defaults())
  end

  def execute(ast_node, opts) do
    import Urania.Impl
    interpret_ast(ast_node, Map.merge(run_defaults(), opts))
  end

  @doc """
  Runs a Urania muse and returns a Pinky promise of the result, discarding the cache.

  ## Examples

      iex> Urania.value(3) |> Urania.run |> Pinky.extract
      {:ok, 3}

  """
  def run(ast) do
    import Urania.Impl
    run(ast, run_defaults())
  end

  def run(ast, opts) do
    execute(ast, opts) |> P.map(fn ({val, _cache}) -> val end)
  end

  @doc """
  Runs a Urania muse and extracts it from the promise. It blocks until the
  run is completed.

  ## Examples

      iex> Urania.value(3) |> Urania.run!
      {:ok, 3}

  """
  def run!(ast) do
    P.extract(run(ast))
  end

  def run!(ast, opts) do
    P.extract(run(ast, opts))
  end
end
